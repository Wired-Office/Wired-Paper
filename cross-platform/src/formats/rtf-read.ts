import { styleLook } from "./rtf-write";
import {
  DEFAULT_FONT, DEFAULT_SIZE, bytesToDataURL, fontStack, imageSize, mimeForFilename,
  type Mark, type PMNode, type PageSetup, type ParagraphStyleID,
} from "./model";

/**
 * Reads RTF, in particular the dialect macOS writes for `.paper` / RTFD
 * documents, into Tiptap JSON. Covers character formatting, fonts, sizes,
 * colors, alignment, lists, tables, links, line and page breaks, and images
 * (RTFD `\NeXTGraphic` attachments and embedded `\pict` PNG/JPEG data).
 *
 * Text offsets are tracked exactly as NSAttributedString counts them (UTF-16,
 * one character per paragraph end, attachment and list marker character), so
 * the Mac app's paragraph-style runs from Document.json can be applied.
 */

export interface RTFReadOptions {
  /** Resolves an RTFD attachment file name to its bytes. */
  attachment?: (name: string) => Uint8Array | undefined;
  /** Paragraph style runs (`WPParagraphStyle`) from Document.json. */
  styleRuns?: { location: number; length: number; value: string }[];
}

export interface RTFReadResult {
  doc: PMNode;
  pageSetup?: PageSetup;
}

// MARK: - Parser state

interface CharState {
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  font: number;
  size: number; // half-points
  fg: number;
  bg: number;
  vertical: -1 | 0 | 1;
  ucSkip: number;
  link: string | null;
}

interface ParaState {
  align: "left" | "center" | "right" | "justify" | null;
  inTable: boolean;
  list: number;
  level: number;
}

type Destination =
  | { kind: "fonttbl"; current: number; name: string; family: string }
  | { kind: "colortbl"; r: number; g: number; b: number; any: boolean }
  | { kind: "listtable"; listID: number; levels: number[]; currentNFC: number }
  | { kind: "listoverride"; listID: number }
  | { kind: "fldinst"; text: string; field: FieldState }
  | { kind: "nextgraphic"; text: string; width: number; height: number }
  | { kind: "pict"; hex: string; format: string | null; width: number; height: number; goalW: number; goalH: number }
  | { kind: "listtext"; text: string }
  | { kind: "skip" };

interface FieldState {
  url: string | null;
}

interface Group {
  char: CharState;
  para: ParaState;
  dest: Destination | null;
  field: FieldState | null;
  /** Set by `\*`: skip the group if its destination is unknown. */
  ignorable: boolean;
}

type Inline =
  | { kind: "text"; text: string; marks: Mark[]; key: string }
  | { kind: "image"; src: string; width?: number; height?: number }
  | { kind: "break" };

interface Para {
  inlines: Inline[];
  align: ParaState["align"];
  list: { ls: number; level: number } | null;
  start: number;
}

interface Table {
  kind: "table";
  rows: Para[][][];
}

type Block = { kind: "para"; para: Para } | Table | { kind: "pageBreak" };

const CP1252: Record<number, number> = {
  0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
  0x88: 0x02c6, 0x89: 0x2030, 0x8a: 0x0160, 0x8b: 0x2039, 0x8c: 0x0152, 0x8e: 0x017d, 0x91: 0x2018,
  0x92: 0x2019, 0x93: 0x201c, 0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02dc,
  0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a, 0x9c: 0x0153, 0x9e: 0x017e, 0x9f: 0x0178,
};

const cp1252 = (byte: number) => String.fromCharCode(CP1252[byte] ?? byte);

/** Destinations whose content is never shown. */
const SKIPPED = new Set([
  "info", "stylesheet", "header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf",
  "pntext", "pntxta", "pntxtb", "expandedcolortbl", "xmlnstbl", "generator", "themedata", "colorschememapping",
  "latentstyles", "datastore", "footnote", "annotation", "atnid", "atnauthor", "comment", "bkmkstart", "bkmkend",
  "object", "objdata", "revtbl", "rsidtbl", "pgdsctbl", "filetbl", "listpicture", "mmathPr", "userprops",
  "nonshppict", "shpinst", "falt", "panose", "fname", "template",
]);

const defaultChar = (): CharState => ({
  bold: false, italic: false, underline: false, strike: false, font: 0, size: DEFAULT_SIZE * 2,
  fg: 0, bg: 0, vertical: 0, ucSkip: 1, link: null,
});
const defaultPara = (): ParaState => ({ align: null, inTable: false, list: 0, level: 0 });

export function readRTF(input: string | Uint8Array, options: RTFReadOptions = {}): RTFReadResult {
  // Decode bytes as Latin-1 so raw 8-bit characters survive; they are mapped through CP1252 below.
  const source = typeof input === "string" ? input : latin1(input);
  const parser = new Parser(source, options);
  parser.run();
  return parser.result();
}

function latin1(bytes: Uint8Array): string {
  let out = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) out += String.fromCharCode(...bytes.subarray(i, i + chunk));
  return out;
}

class Parser {
  private pos = 0;
  private stack: Group[] = [];
  private group: Group = { char: defaultChar(), para: defaultPara(), dest: null, field: null, ignorable: false };

  private fonts = new Map<number, { name: string; family: string }>();
  private colors: (string | null)[] = [];
  private lists = new Map<number, number[]>(); // listid → nfc per level
  private overrides = new Map<number, number>(); // ls → listid
  private defaultFont = 0;

  private blocks: Block[] = [];
  private para: Para;
  private table: Table | null = null;
  private row: Para[][] | null = null;
  private cell: Para[] = [];
  /** UTF-16 offset in the equivalent NSAttributedString. */
  private offset = 0;
  private pendingSkip = 0;
  private skipAttachmentChar = false;
  private paper: { w?: number; h?: number; l?: number; r?: number; t?: number; b?: number } = {};
  /** Paragraph properties where text was last added, for a final paragraph after its group closed. */
  private lastPara: ParaState = defaultPara();

  constructor(private src: string, private options: RTFReadOptions) {
    this.para = this.newPara();
  }

  run() {
    const src = this.src;
    while (this.pos < src.length) {
      const ch = src[this.pos];
      if (ch === "{") {
        this.pos++;
        this.stack.push(this.group);
        this.group = { char: { ...this.group.char }, para: { ...this.group.para }, dest: this.inheritedDest(), field: this.group.field, ignorable: false };
      } else if (ch === "}") {
        this.pos++;
        this.closeGroup();
      } else if (ch === "\\") {
        this.control();
      } else if (ch === "\r" || ch === "\n") {
        this.pos++;
      } else {
        // A run of plain text up to the next special character.
        let end = this.pos;
        while (end < src.length && !"{}\\\r\n".includes(src[end])) end++;
        const raw = src.slice(this.pos, end);
        this.pos = end;
        let text = "";
        for (let i = 0; i < raw.length; i++) {
          if (this.pendingSkip > 0) { this.pendingSkip--; continue; }
          const code = raw.charCodeAt(i);
          text += code >= 0x80 ? cp1252(code) : raw[i];
        }
        this.text(text);
      }
    }
  }

  /** Children of a skipped or collecting destination stay in it. */
  private inheritedDest(): Destination | null {
    const dest = this.group.dest;
    if (!dest) return null;
    switch (dest.kind) {
      case "skip": case "listtext": case "fldinst": case "fonttbl": case "colortbl": case "listtable": case "listoverride":
        return dest;
      default:
        return { kind: "skip" };
    }
  }

  private closeGroup() {
    const closing = this.group;
    this.group = this.stack.pop() ?? this.group;
    const dest = closing.dest;
    if (!dest || dest === this.group.dest) return;
    switch (dest.kind) {
      case "fldinst": {
        const match = /HYPERLINK\s+(?:\\l\s+)?"([^"]*)"/i.exec(dest.text) ?? /HYPERLINK\s+(\S+)/i.exec(dest.text);
        if (match) dest.field.url = match[1];
        break;
      }
      case "listtext":
        this.offset += dest.text.length;
        break;
      case "nextgraphic": {
        const name = dest.text.trim();
        const bytes = this.options.attachment?.(name);
        if (bytes) {
          const size = imageSize(bytes);
          this.inline({
            kind: "image",
            src: bytesToDataURL(bytes, mimeForFilename(name)),
            width: dest.width ? Math.round(dest.width / 20) : size?.width,
            height: dest.height ? Math.round(dest.height / 20) : size?.height,
          });
        } else {
          this.offset += 1;
        }
        this.skipAttachmentChar = true;
        break;
      }
      case "pict": {
        if (dest.format && dest.hex.length > 0) {
          const clean = dest.hex.replace(/[^0-9a-fA-F]/g, "");
          const bytes = new Uint8Array(clean.length >> 1);
          for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
          const width = dest.goalW ? dest.goalW / 20 : dest.width;
          const height = dest.goalH ? dest.goalH / 20 : dest.height;
          this.inline({ kind: "image", src: bytesToDataURL(bytes, dest.format), width: Math.round(width) || undefined, height: Math.round(height) || undefined });
        }
        break;
      }
      case "listtable":
        if (dest.listID) this.lists.set(dest.listID, dest.levels);
        break;
      default:
        break;
    }
  }

  private control() {
    const src = this.src;
    this.pos++; // backslash
    const ch = src[this.pos];
    if (ch === undefined) return;
    if (!/[a-zA-Z]/.test(ch)) {
      this.pos++;
      switch (ch) {
        case "\\": case "{": case "}": this.text(ch); break;
        case "~": this.text(" "); break;
        case "_": this.text("‑"); break;
        case "-": break;
        case "*": this.group.ignorable = true; break;
        case "\n": case "\r": this.word("par", null); break;
        case "'": {
          const hex = src.substr(this.pos, 2);
          this.pos += 2;
          if (this.pendingSkip > 0) { this.pendingSkip--; break; }
          this.text(cp1252(parseInt(hex, 16)));
          break;
        }
        default: break;
      }
      return;
    }
    let end = this.pos;
    while (end < src.length && /[a-zA-Z]/.test(src[end])) end++;
    const name = src.slice(this.pos, end);
    let param: number | null = null;
    let numEnd = end;
    if (src[numEnd] === "-" || /[0-9]/.test(src[numEnd] ?? "")) {
      numEnd++;
      while (numEnd < src.length && /[0-9]/.test(src[numEnd])) numEnd++;
      param = parseInt(src.slice(end, numEnd), 10);
    }
    this.pos = numEnd;
    if (src[this.pos] === " ") this.pos++; // delimiter space belongs to the control word
    this.word(name, param);
  }

  private word(name: string, param: number | null) {
    const g = this.group;
    const dest = g.dest;
    const on = param === null || param !== 0;

    // Unknown groups nested in a table destination (e.g. \*\panose in fonttbl) are skipped.
    if ((dest?.kind === "fonttbl" || dest?.kind === "colortbl" || dest?.kind === "listtable" || dest?.kind === "listoverride")
        && (g.ignorable || SKIPPED.has(name))) {
      g.dest = { kind: "skip" };
      return;
    }

    // Destination-specific words.
    if (dest?.kind === "fonttbl") {
      if (name === "f") { dest.current = param ?? 0; dest.name = ""; dest.family = "nil"; }
      else if (["fnil", "froman", "fswiss", "fmodern", "fscript", "fdecor", "ftech", "fbidi"].includes(name)) dest.family = name.slice(1);
      return;
    }
    if (dest?.kind === "colortbl") {
      if (name === "red") { dest.r = param ?? 0; dest.any = true; }
      else if (name === "green") { dest.g = param ?? 0; dest.any = true; }
      else if (name === "blue") { dest.b = param ?? 0; dest.any = true; }
      return;
    }
    if (dest?.kind === "listtable") {
      if (name === "list") { dest.listID = 0; dest.levels = []; }
      else if (name === "listid") dest.listID = param ?? 0;
      else if (name === "levelnfc") dest.levels.push(param ?? 0);
      return;
    }
    if (dest?.kind === "listoverride") {
      if (name === "listid") dest.listID = param ?? 0;
      else if (name === "ls") this.overrides.set(param ?? 0, dest.listID);
      return;
    }
    if (dest?.kind === "nextgraphic") {
      if (name === "width") dest.width = param ?? 0;
      else if (name === "height") dest.height = param ?? 0;
      return;
    }
    if (dest?.kind === "pict") {
      switch (name) {
        case "pngblip": dest.format = "image/png"; break;
        case "jpegblip": dest.format = "image/jpeg"; break;
        case "picw": dest.width = param ?? 0; break;
        case "pich": dest.height = param ?? 0; break;
        case "picwgoal": dest.goalW = param ?? 0; break;
        case "pichgoal": dest.goalH = param ?? 0; break;
        case "bin": break;
      }
      return;
    }
    if (dest?.kind === "skip") return;

    // Destinations.
    switch (name) {
      case "fonttbl": g.dest = { kind: "fonttbl", current: 0, name: "", family: "nil" }; return;
      case "colortbl": g.dest = { kind: "colortbl", r: 0, g: 0, b: 0, any: false }; return;
      case "listtable": g.dest = { kind: "listtable", listID: 0, levels: [], currentNFC: 0 }; return;
      case "listoverridetable": g.dest = { kind: "listoverride", listID: 0 }; return;
      case "listtext": g.dest = { kind: "listtext", text: "" }; return;
      case "NeXTGraphic": g.dest = { kind: "nextgraphic", text: "", width: 0, height: 0 }; return;
      case "pict": g.dest = { kind: "pict", hex: "", format: null, width: 0, height: 0, goalW: 0, goalH: 0 }; return;
      case "field": g.field = { url: null }; return;
      case "fldinst": g.dest = { kind: "fldinst", text: "", field: g.field ?? { url: null } }; return;
      case "fldrslt": if (g.field?.url) g.char.link = g.field.url; return;
    }
    if (SKIPPED.has(name) || (g.ignorable && !g.dest)) {
      g.dest = { kind: "skip" };
      return;
    }
    if (dest?.kind === "listtext" || dest?.kind === "fldinst") {
      if (name === "tab") this.text("\t");
      else if (name === "u" && param !== null) this.text(String.fromCharCode(param < 0 ? param + 65536 : param));
      else if (name === "uc") g.char.ucSkip = param ?? 1;
      return;
    }

    const c = g.char;
    const p = g.para;
    switch (name) {
      // Document
      case "deff": this.defaultFont = param ?? 0; break;
      case "paperw": this.paper.w = param ?? undefined; break;
      case "paperh": this.paper.h = param ?? undefined; break;
      case "margl": this.paper.l = param ?? undefined; break;
      case "margr": this.paper.r = param ?? undefined; break;
      case "margt": this.paper.t = param ?? undefined; break;
      case "margb": this.paper.b = param ?? undefined; break;
      // Characters
      case "plain": Object.assign(c, defaultChar(), { font: this.defaultFont, ucSkip: c.ucSkip, link: c.link }); break;
      case "b": c.bold = on; break;
      case "i": c.italic = on; break;
      case "ul": c.underline = on; break;
      case "uld": case "uldb": case "ulw": case "uldash": case "ulth": case "ulwave": c.underline = on; break;
      case "ulnone": c.underline = false; break;
      case "strike": case "striked": c.strike = on; break;
      case "f": c.font = param ?? 0; break;
      case "fs": c.size = param ?? DEFAULT_SIZE * 2; break;
      case "cf": c.fg = param ?? 0; break;
      case "cb": case "highlight": case "chcbpat": c.bg = param ?? 0; break;
      case "super": c.vertical = 1; break;
      case "sub": c.vertical = -1; break;
      case "nosupersub": c.vertical = 0; break;
      case "up": c.vertical = (param ?? 6) > 0 ? 1 : 0; break;
      case "dn": c.vertical = (param ?? 6) > 0 ? -1 : 0; break;
      case "uc": c.ucSkip = param ?? 1; break;
      case "u": {
        if (param === null) break;
        this.text(String.fromCharCode(param < 0 ? param + 65536 : param));
        this.pendingSkip = c.ucSkip;
        break;
      }
      // Special characters
      case "tab": this.text("\t"); break;
      case "line": this.inline({ kind: "break" }); break;
      case "emdash": this.text("—"); break;
      case "endash": this.text("–"); break;
      case "bullet": this.text("•"); break;
      case "lquote": this.text("‘"); break;
      case "rquote": this.text("’"); break;
      case "ldblquote": this.text("“"); break;
      case "rdblquote": this.text("”"); break;
      case "emspace": case "enspace": case "qmspace": this.text(" "); break;
      // Paragraphs
      case "pard": Object.assign(p, defaultPara()); break;
      case "ql": p.align = "left"; break;
      case "qc": p.align = "center"; break;
      case "qr": p.align = "right"; break;
      case "qj": p.align = "justify"; break;
      case "intbl": p.inTable = true; break;
      case "itap": p.inTable = (param ?? 1) > 0; break;
      case "ls": p.list = param ?? 0; break;
      case "ilvl": p.level = param ?? 0; break;
      case "par": this.endParagraph("par"); break;
      case "sect": this.endParagraph("par"); break;
      case "page": this.endParagraph("par"); this.pushBlock({ kind: "pageBreak" }); break;
      // Tables
      case "cell": case "nestcell": this.endParagraph("cell"); break;
      case "row": case "nestrow": this.endRow(); break;
      default: break;
    }
  }

  private text(text: string) {
    if (!text) return;
    const dest = this.group.dest;
    if (dest) {
      switch (dest.kind) {
        case "fonttbl": {
          for (const ch of text) {
            if (ch === ";") {
              this.fonts.set(dest.current, { name: dest.name.trim(), family: dest.family });
              dest.name = "";
            } else dest.name += ch;
          }
          return;
        }
        case "colortbl": {
          for (const ch of text) {
            if (ch !== ";") continue;
            this.colors.push(dest.any ? rgbHex(dest.r, dest.g, dest.b) : null);
            dest.r = dest.g = dest.b = 0;
            dest.any = false;
          }
          return;
        }
        case "listtext": dest.text += text; return;
        case "fldinst": dest.text += text; return;
        case "nextgraphic": dest.text += text; return;
        case "pict": dest.hex += text; return;
        default: return;
      }
    }
    if (this.skipAttachmentChar) {
      this.skipAttachmentChar = false;
      if (text[0] === "¬" || text[0] === "￼") text = text.slice(1);
      if (!text) return;
    }
    this.lastPara = { ...this.group.para };
    const marks = this.marks();
    const key = JSON.stringify(marks);
    const last = this.para.inlines[this.para.inlines.length - 1];
    if (last?.kind === "text" && last.key === key) last.text += text;
    else this.para.inlines.push({ kind: "text", text, marks, key });
    this.offset += text.length;
  }

  private inline(inline: Inline) {
    this.lastPara = { ...this.group.para };
    this.para.inlines.push(inline);
    this.offset += 1;
  }

  private marks(): Mark[] {
    const c = this.group.char;
    const marks: Mark[] = [];
    if (c.bold) marks.push({ type: "bold" });
    if (c.italic) marks.push({ type: "italic" });
    if (c.underline) marks.push({ type: "underline" });
    if (c.strike) marks.push({ type: "strike" });
    if (c.vertical === 1) marks.push({ type: "superscript" });
    if (c.vertical === -1) marks.push({ type: "subscript" });
    if (c.link) marks.push({ type: "link", attrs: { href: c.link } });
    const style: Record<string, string> = {};
    const font = this.fonts.get(c.font);
    const family = font ? familyFromFontName(font.name) : null;
    if (family && family !== DEFAULT_FONT && family !== "Helvetica") style.fontFamily = fontStack(family);
    if (c.size !== DEFAULT_SIZE * 2) style.fontSize = `${c.size / 2}pt`;
    const fg = this.colors[c.fg];
    if (c.fg > 0 && fg && fg !== "#000000" && !c.link) style.color = fg;
    const bg = this.colors[c.bg];
    if (c.bg > 0 && bg && bg !== "#ffffff") style.backgroundColor = bg;
    if (Object.keys(style).length) marks.push({ type: "textStyle", attrs: style });
    return marks;
  }

  private newPara(): Para {
    return { inlines: [], align: null, list: null, start: this.offset };
  }

  private endParagraph(kind: "par" | "cell", p: ParaState = this.group.para) {
    const para = this.para;
    para.align = p.align;
    if (p.list > 0) para.list = { ls: p.list, level: p.level };
    this.offset += 1; // paragraph separator / cell end
    this.skipAttachmentChar = false;
    if (kind === "cell" || p.inTable) {
      this.cell.push(para);
      if (kind === "cell") {
        this.row ??= [];
        this.row.push(this.cell);
        this.cell = [];
      }
    } else {
      this.pushBlock({ kind: "para", para });
    }
    this.para = this.newPara();
  }

  private endRow() {
    if (this.cell.length) {
      this.row ??= [];
      this.row.push(this.cell);
      this.cell = [];
    }
    if (!this.row) return;
    this.table ??= { kind: "table", rows: [] };
    this.table.rows.push(this.row);
    this.row = null;
  }

  private pushBlock(block: Block) {
    if (this.table) {
      this.blocks.push(this.table);
      this.table = null;
    }
    this.blocks.push(block);
  }

  result(): RTFReadResult {
    // A final paragraph without \par.
    if (this.para.inlines.length) this.endParagraph("par", this.lastPara);
    if (this.row || this.cell.length) this.endRow();
    if (this.table) {
      this.blocks.push(this.table);
      this.table = null;
    }
    const doc = new Assembler(this.lists, this.overrides, this.options.styleRuns ?? []).assemble(this.blocks);
    let pageSetup: PageSetup | undefined;
    const { w, h, l, r, t, b } = this.paper;
    if (w && h && w >= 2880 && h >= 2880) {
      pageSetup = {
        paperSize: [w / 20, h / 20],
        margins: { top: (t ?? 1440) / 20, left: (l ?? 1800) / 20, bottom: (b ?? 1440) / 20, right: (r ?? 1800) / 20 },
      };
    }
    return { doc, pageSetup };
  }
}

function rgbHex(r: number, g: number, b: number): string {
  return "#" + [r, g, b].map((v) => Math.max(0, Math.min(255, v)).toString(16).padStart(2, "0")).join("");
}

/** "HelveticaNeue-Bold" → "Helvetica Neue", "TimesNewRomanPSMT" → "Times New Roman". */
export function familyFromFontName(name: string): string {
  let base = name.replace(/;$/, "").trim();
  if (!base) return DEFAULT_FONT;
  if (/\s/.test(base)) return base.replace(/\s+(Bold|Italic|Oblique|Regular|Light|Medium)(\s+(Bold|Italic|Oblique))?$/i, "");
  base = base.split("-")[0].replace(/(PSMT|PS|MT)$/, "");
  return base.replace(/([a-z])([A-Z])/g, "$1 $2");
}

// MARK: - Blocks → Tiptap JSON

class Assembler {
  constructor(
    private lists: Map<number, number[]>,
    private overrides: Map<number, number>,
    private styleRuns: { location: number; length: number; value: string }[],
  ) {}

  assemble(blocks: Block[]): PMNode {
    const content: PMNode[] = [];
    let i = 0;
    while (i < blocks.length) {
      const block = blocks[i];
      if (block.kind === "para" && block.para.list) {
        const run: Para[] = [];
        while (i < blocks.length) {
          const next = blocks[i];
          if (next.kind !== "para" || !next.para.list) break;
          run.push(next.para);
          i++;
        }
        content.push(...this.buildLists(run));
        continue;
      }
      if (block.kind === "para") {
        const style = this.styleAt(block.para.start);
        if (style === "quote" || style === "code") {
          const run: Para[] = [];
          while (i < blocks.length) {
            const next = blocks[i];
            if (next.kind !== "para" || next.para.list || this.styleAt(next.para.start) !== style) break;
            run.push(next.para);
            i++;
          }
          content.push(style === "quote"
            ? { type: "blockquote", content: run.map((p) => this.paragraph(p, "normal", "quote")) }
            : { type: "codeBlock", content: textOf(run) ? [{ type: "text", text: textOf(run) }] : undefined });
          continue;
        }
        content.push(this.paragraph(block.para, style));
      } else if (block.kind === "pageBreak") {
        content.push({ type: "pageBreak" });
      } else {
        content.push(this.table(block));
      }
      i++;
    }
    if (!content.length) content.push({ type: "paragraph" });
    return { type: "doc", content };
  }

  private styleAt(offset: number): ParagraphStyleID {
    for (const run of this.styleRuns) {
      if (offset >= run.location && offset < run.location + run.length) return run.value as ParagraphStyleID;
    }
    return "normal";
  }

  /** `look` is the style whose formatting is implied by the node (e.g. italic in a quote). */
  private paragraph(para: Para, style: ParagraphStyleID = this.styleAt(para.start), look: ParagraphStyleID = style): PMNode {
    const attrs: Record<string, unknown> = {};
    if (para.align && para.align !== "left") attrs.textAlign = para.align;
    const heading = /^heading([1-6])$/.exec(style);
    const isHeading = heading || style === "title";
    if (style !== "normal" && !(heading && Number(heading[1]) <= 6)) attrs.wpStyle = style;
    const content = this.inlines(para.inlines, look, !!isHeading);
    const node: PMNode = isHeading
      ? { type: "heading", attrs: { ...attrs, level: heading ? Number(heading[1]) : 1 } }
      : { type: "paragraph", attrs: Object.keys(attrs).length ? attrs : undefined };
    if (content.length) node.content = content;
    if (!node.attrs) delete node.attrs;
    return node;
  }

  private inlines(inlines: Inline[], style: ParagraphStyleID, heading: boolean): PMNode[] {
    const look = styleLook(style);
    const nodes: PMNode[] = [];
    for (const inline of inlines) {
      if (inline.kind === "break") nodes.push({ type: "hardBreak" });
      else if (inline.kind === "image") {
        nodes.push({ type: "image", attrs: { src: inline.src, width: inline.width ?? null, height: inline.height ?? null } });
      } else {
        // Line separators and stray form feeds from the Mac become breaks.
        const parts = inline.text.split(/[\u2028\f]/);
        parts.forEach((part, index) => {
          if (index > 0) nodes.push({ type: "hardBreak" });
          if (!part) return;
          // Formatting implied by the paragraph's style isn't repeated as marks;
          // headings get their whole look from the style.
          const marks = inline.marks
            .filter((m) => !(m.type === "bold" && (look.bold || heading)) && !(m.type === "italic" && look.italic))
            .map((m) => {
              if (m.type !== "textStyle") return m;
              const attrs = { ...(m.attrs ?? {}) };
              if (heading) {
                delete attrs.fontSize;
                delete attrs.color;
                delete attrs.fontFamily;
              }
              if (attrs.fontSize === `${look.size}pt`) delete attrs.fontSize;
              if (look.color && typeof attrs.color === "string" && similarColor(attrs.color, look.color)) delete attrs.color;
              if (look.font && typeof attrs.fontFamily === "string" && attrs.fontFamily.includes(look.font)) delete attrs.fontFamily;
              return { ...m, attrs };
            })
            .filter((m) => m.type !== "textStyle" || Object.keys(m.attrs ?? {}).length);
          nodes.push(marks.length ? { type: "text", text: part, marks } : { type: "text", text: part });
        });
      }
    }
    return nodes;
  }

  private listKind(ls: number): "bulletList" | "orderedList" {
    const listID = this.overrides.get(ls) ?? ls;
    const nfc = this.lists.get(listID)?.[0];
    return nfc === undefined || nfc === 23 || nfc === 255 ? "bulletList" : "orderedList";
  }

  /** Nests consecutive list paragraphs by level. */
  private buildLists(paras: Para[]): PMNode[] {
    const result: PMNode[] = [];
    // Stack of open lists: each with its level and node.
    const stack: { level: number; node: PMNode }[] = [];
    for (const para of paras) {
      const { ls, level } = para.list!;
      const kind = this.listKind(ls);
      while (stack.length && stack[stack.length - 1].level > level) stack.pop();
      let top = stack[stack.length - 1];
      if (top && top.level === level && top.node.type !== kind) {
        stack.pop();
        top = stack[stack.length - 1];
      }
      if (!top || top.level < level) {
        const list: PMNode = { type: kind, content: [] };
        if (top) {
          const items = top.node.content!;
          const lastItem = items[items.length - 1];
          if (lastItem) lastItem.content!.push(list);
          else items.push({ type: "listItem", content: [{ type: "paragraph" }, list] });
        } else {
          result.push(list);
        }
        stack.push({ level, node: list });
        top = stack[stack.length - 1];
      }
      top.node.content!.push({ type: "listItem", content: [this.paragraph(para, "normal")] });
    }
    return result;
  }

  private table(table: Table): PMNode {
    const columns = Math.max(1, ...table.rows.map((r) => r.length));
    return {
      type: "table",
      content: table.rows.map((row) => {
        const cells = row.map((cell) => ({
          type: "tableCell",
          attrs: { colspan: 1, rowspan: 1, colwidth: null },
          content: cell.length ? cell.map((p) => this.paragraph(p, "normal")) : [{ type: "paragraph" }],
        }));
        while (cells.length < columns) cells.push({ type: "tableCell", attrs: { colspan: 1, rowspan: 1, colwidth: null }, content: [{ type: "paragraph" }] });
        return { type: "tableRow", content: cells };
      }),
    };
  }
}

function textOf(paras: Para[]): string {
  return paras
    .map((p) => p.inlines.map((i) => (i.kind === "text" ? i.text : i.kind === "break" ? "\n" : "")).join(""))
    .join("\n");
}

function similarColor(a: string, b: string): boolean {
  const parse = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const [x, y] = [parse(a), parse(b)];
  return x.every((v, i) => Math.abs(v - y[i]) <= 24);
}
