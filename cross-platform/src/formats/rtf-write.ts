import {
  DEFAULT_FONT, dataURLToBytes, extensionForMime, imageSize, primaryFamily,
  type Mark, type PMNode, type PageSetup, type ParagraphStyleID,
} from "./model";

/**
 * Writes Tiptap JSON as RTF that both macOS (NSAttributedString) and Word
 * read. In `rtfd` mode images become `\NeXTGraphic` attachments stored as
 * separate files, as in the Mac app's Content.rtfd; otherwise PNG and JPEG
 * images are embedded as `\pict` data.
 */

export interface RTFWriteOptions {
  pageSetup?: PageSetup;
  images: "rtfd" | "embedded";
}

export interface RTFAsset {
  name: string;
  bytes: Uint8Array;
}

export interface RTFWriteResult {
  rtf: string;
  assets: RTFAsset[];
  /** `WPParagraphStyle` runs for Document.json, in NSAttributedString offsets. */
  styleRuns: { location: number; length: number; value: string }[];
}

interface StyleLook {
  size: number;
  bold?: boolean;
  italic?: boolean;
  color?: string;
  font?: string;
  before: number;
  after: number;
  lineHeight: number;
  indent?: number;
}

const HEADING_INK = "#124a59";
const SECONDARY_INK = "#5c636b";

/** The Mac app's built-in styles (StyleSheet.builtIns), so documents look the same there. */
const LOOKS: Record<ParagraphStyleID, StyleLook> = {
  normal: { size: 12, before: 0, after: 8, lineHeight: 1.15 },
  noSpacing: { size: 12, before: 0, after: 0, lineHeight: 1 },
  title: { size: 27.5, bold: true, color: HEADING_INK, before: 0, after: 4, lineHeight: 1 },
  subtitle: { size: 15, color: SECONDARY_INK, before: 0, after: 16, lineHeight: 1 },
  heading1: { size: 18, bold: true, color: HEADING_INK, before: 18, after: 6, lineHeight: 1 },
  heading2: { size: 15, bold: true, color: HEADING_INK, before: 14, after: 4, lineHeight: 1 },
  heading3: { size: 13, bold: true, color: SECONDARY_INK, before: 12, after: 4, lineHeight: 1 },
  heading4: { size: 12, bold: true, italic: true, color: HEADING_INK, before: 10, after: 3, lineHeight: 1 },
  heading5: { size: 12, bold: true, color: SECONDARY_INK, before: 10, after: 2, lineHeight: 1 },
  heading6: { size: 12, italic: true, color: SECONDARY_INK, before: 8, after: 2, lineHeight: 1 },
  heading7: { size: 11.5, bold: true, before: 8, after: 2, lineHeight: 1 },
  heading8: { size: 11, italic: true, before: 6, after: 2, lineHeight: 1 },
  heading9: { size: 11, italic: true, color: SECONDARY_INK, before: 6, after: 2, lineHeight: 1 },
  quote: { size: 12, italic: true, color: SECONDARY_INK, before: 4, after: 8, lineHeight: 1.15, indent: 36 },
  caption: { size: 10, italic: true, color: SECONDARY_INK, before: 0, after: 10, lineHeight: 1 },
  code: { size: 11, font: "Menlo", before: 0, after: 0, lineHeight: 1.1 },
};

export function styleLook(id: ParagraphStyleID): StyleLook {
  return LOOKS[id] ?? LOOKS.normal;
}

interface ParaContext {
  style: ParagraphStyleID;
  align?: string;
  list?: { kind: "bullet" | "ordered"; level: number; number: number };
  inTable?: boolean;
  /** Last paragraph of a table cell: ends with \cell instead of \par. */
  endsCell?: boolean;
}

const tw = (points: number) => Math.round(points * 20);

export function writeRTF(doc: PMNode, options: RTFWriteOptions): RTFWriteResult {
  return new Writer(options).write(doc);
}

class Writer {
  private fonts: string[] = [DEFAULT_FONT];
  private colors: string[] = [];
  private body: string[] = [];
  private assets: RTFAsset[] = [];
  private offset = 0;
  private styleRuns: RTFWriteResult["styleRuns"] = [];
  private usesLists = false;

  constructor(private options: RTFWriteOptions) {}

  write(doc: PMNode): RTFWriteResult {
    for (const node of doc.content ?? []) this.block(node, { style: "normal" });
    const setup = this.options.pageSetup;
    const header = [
      "{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc0",
      `{\\fonttbl${this.fonts.map((f, i) => `\\f${i}\\fnil\\fcharset0 ${escapePlain(f)};`).join("")}}`,
      `{\\colortbl;${this.colors.map((c) => `\\red${parseInt(c.slice(1, 3), 16)}\\green${parseInt(c.slice(3, 5), 16)}\\blue${parseInt(c.slice(5, 7), 16)};`).join("")}}`,
    ];
    if (this.usesLists) header.push(LIST_TABLE);
    if (setup) {
      const [w, h] = setup.paperSize;
      const m = setup.margins;
      header.push(`\\paperw${tw(w)}\\paperh${tw(h)}\\margl${tw(m.left)}\\margr${tw(m.right)}\\margt${tw(m.top)}\\margb${tw(m.bottom)}`);
      if (w > h) header.push("\\landscape");
    }
    const rtf = header.join("\n") + "\n" + this.body.join("") + "}";
    return { rtf, assets: this.assets, styleRuns: this.styleRuns };
  }

  // MARK: Tables

  private font(family: string): number {
    let index = this.fonts.indexOf(family);
    if (index < 0) index = this.fonts.push(family) - 1;
    return index;
  }

  private color(hex: string): number {
    const normalized = normalizeColor(hex);
    if (!normalized) return 0;
    let index = this.colors.indexOf(normalized);
    if (index < 0) index = this.colors.push(normalized) - 1;
    return index + 1;
  }

  // MARK: Blocks

  private block(node: PMNode, ctx: ParaContext) {
    switch (node.type) {
      case "paragraph":
        this.paragraph(node, { ...ctx, style: (node.attrs?.wpStyle as ParagraphStyleID) || ctx.style, align: node.attrs?.textAlign as string });
        break;
      case "heading": {
        const level = Number(node.attrs?.level ?? 1);
        const style = (node.attrs?.wpStyle as ParagraphStyleID) || (`heading${level}` as ParagraphStyleID);
        this.paragraph(node, { ...ctx, style, align: node.attrs?.textAlign as string });
        break;
      }
      case "blockquote":
        for (const child of node.content ?? []) this.block(child, { ...ctx, style: "quote" });
        break;
      case "codeBlock": {
        const text = (node.content ?? []).map((n) => n.text ?? "").join("");
        for (const line of text.split("\n")) {
          this.paragraph({ type: "paragraph", content: line ? [{ type: "text", text: line }] : [] }, { ...ctx, style: "code" });
        }
        break;
      }
      case "bulletList":
      case "orderedList":
        this.list(node, ctx, 0);
        break;
      case "table":
        this.table(node);
        break;
      case "pageBreak":
        this.body.push("\\pard\\plain \\page\n");
        this.offset += 1;
        break;
      case "horizontalRule":
        this.paragraph({ type: "paragraph", content: [{ type: "text", text: "\u2014".repeat(20) }] }, { ...ctx, style: "normal", align: "center" });
        break;
      default:
        for (const child of node.content ?? []) this.block(child, ctx);
    }
  }

  private list(node: PMNode, ctx: ParaContext, level: number) {
    this.usesLists = true;
    const kind = node.type === "orderedList" ? "ordered" : "bullet";
    let number = Number(node.attrs?.start ?? 1);
    for (const item of node.content ?? []) {
      let first = true;
      for (const child of item.content ?? []) {
        if (child.type === "bulletList" || child.type === "orderedList") {
          this.list(child, ctx, level + 1);
        } else if (first && (child.type === "paragraph" || child.type === "heading")) {
          this.paragraph(child, { ...ctx, style: "normal", align: child.attrs?.textAlign as string, list: { kind, level, number } });
          first = false;
        } else {
          this.block(child, ctx);
        }
      }
      if (first) this.paragraph({ type: "paragraph" }, { ...ctx, style: "normal", list: { kind, level, number } });
      number++;
    }
  }

  private table(node: PMNode) {
    const rows = node.content ?? [];
    const setup = this.options.pageSetup;
    const contentWidth = setup ? setup.paperSize[0] - setup.margins.left - setup.margins.right : 468;
    rows.forEach((row, rowIndex) => {
      const cells = row.content ?? [];
      const totalSpan = cells.reduce((sum, cell) => sum + Number(cell.attrs?.colspan ?? 1), 0) || 1;
      let right = 0;
      let def = "\\itap1\\trowd \\trgaph108\\trleft-108";
      const border = "\\brdrs\\brdrw20";
      for (const cell of cells) {
        right += (contentWidth * Number(cell.attrs?.colspan ?? 1)) / totalSpan;
        def += ` \\clbrdrt${border} \\clbrdrl${border} \\clbrdrb${border} \\clbrdrr${border} \\cellx${tw(right)}`;
      }
      this.body.push(def + "\n");
      for (const cell of cells) {
        const paras = (cell.content ?? []).length ? cell.content! : [{ type: "paragraph" }];
        paras.forEach((para, index) => {
          const last = index === paras.length - 1;
          if (para.type === "paragraph" || para.type === "heading") {
            this.paragraph(para, { style: "normal", align: para.attrs?.textAlign as string, inTable: true, endsCell: last });
          } else {
            // Nested blocks in cells are flattened to their text.
            this.paragraph({ type: "paragraph", content: [{ type: "text", text: plainText(para) || " " }] }, { style: "normal", inTable: true, endsCell: last });
          }
        });
      }
      this.body.push(rowIndex === rows.length - 1 ? "\\lastrow\\row\n" : "\\row\n");
    });
  }

  private paragraph(node: PMNode, ctx: ParaContext) {
    const look = styleLook(ctx.style);
    const start = this.offset;
    let out = "\\pard";
    if (ctx.inTable) out += "\\intbl\\itap1";
    const indent = look.indent ?? 0;
    if (ctx.list) {
      const left = 36 * (ctx.list.level + 1);
      out += `\\li${tw(left)}\\fi-${tw(18)}\\ls${ctx.list.kind === "bullet" ? 1 : 2}\\ilvl${ctx.list.level}`;
    } else if (indent) {
      out += `\\li${tw(indent)}\\ri${tw(indent)}`;
    }
    switch (ctx.align) {
      case "center": out += "\\qc"; break;
      case "right": out += "\\qr"; break;
      case "justify": out += "\\qj"; break;
    }
    if (look.before) out += `\\sb${tw(look.before)}`;
    if (look.after && !ctx.inTable) out += `\\sa${tw(look.after)}`;
    if (look.lineHeight !== 1) out += `\\sl${Math.round(240 * look.lineHeight)}\\slmult1`;
    out += "\\plain ";

    if (ctx.list) {
      const marker = ctx.list.kind === "bullet" ? BULLETS[ctx.list.level % BULLETS.length] : `${ctx.list.number}.`;
      const listText = `\t${marker}\t`;
      out += `{\\listtext${escapeText(listText)}}`;
      this.offset += listText.length;
    }

    const base: RunLook = {
      font: look.font ?? DEFAULT_FONT, size: look.size, bold: !!look.bold, italic: !!look.italic,
      color: look.color ?? null,
    };
    out += this.inlines(node.content ?? [], base);
    out += ctx.endsCell ? "\\cell\n" : "\\par\n";
    this.offset += 1;
    this.body.push(out);
    if (ctx.style !== "normal") {
      this.styleRuns.push({ location: start, length: this.offset - start, value: ctx.style });
    }
  }

  // MARK: Inline content

  private inlines(nodes: PMNode[], base: RunLook): string {
    let out = "";
    let i = 0;
    while (i < nodes.length) {
      const node = nodes[i];
      const link = node.marks?.find((m) => m.type === "link")?.attrs?.href as string | undefined;
      if (link) {
        // Consecutive runs with the same link share one field.
        let inner = "";
        while (i < nodes.length && nodes[i].marks?.find((m) => m.type === "link")?.attrs?.href === link) {
          inner += this.inline(nodes[i], base);
          i++;
        }
        out += `{\\field{\\*\\fldinst{HYPERLINK "${escapePlain(link).replace(/"/g, "%22")}"}}{\\fldrslt ${inner}}}`;
        continue;
      }
      out += this.inline(node, base);
      i++;
    }
    return out;
  }

  private inline(node: PMNode, base: RunLook): string {
    switch (node.type) {
      case "text": {
        const text = node.text ?? "";
        this.offset += text.length;
        return `{${this.runFormat(node.marks ?? [], base)} ${escapeText(text)}}`;
      }
      case "hardBreak":
        this.offset += 1;
        return "\\line ";
      case "image":
        return this.image(node);
      default:
        return "";
    }
  }

  private runFormat(marks: Mark[], base: RunLook): string {
    const has = (type: string) => marks.some((m) => m.type === type);
    const style = (marks.find((m) => m.type === "textStyle")?.attrs ?? {}) as Record<string, unknown>;
    const family = primaryFamily(style.fontFamily) ?? base.font;
    const size = parseSize(style.fontSize) ?? base.size;
    const link = has("link");
    const color = (style.color as string | undefined) ?? (link ? "#0066cc" : base.color);
    const background = style.backgroundColor as string | undefined;

    let out = `\\f${this.font(family)}\\fs${Math.round(size * 2)}`;
    if (has("bold") || base.bold) out += "\\b";
    if (has("italic") || base.italic) out += "\\i";
    if (has("underline") || link) out += "\\ul";
    if (has("strike")) out += "\\strike";
    if (has("superscript")) out += "\\super";
    else if (has("subscript")) out += "\\sub";
    if (has("code")) out = out.replace(/^\\f\d+/, `\\f${this.font("Menlo")}`);
    if (color) out += `\\cf${this.color(color)}`;
    if (background) out += `\\cb${this.color(background)}\\highlight${this.color(background)}`;
    return out;
  }

  private image(node: PMNode): string {
    const src = node.attrs?.src as string | undefined;
    const data = src ? dataURLToBytes(src) : null;
    if (!data) return "";
    const natural = imageSize(data.bytes);
    const width = Number(node.attrs?.width) || natural?.width || 100;
    const height = Number(node.attrs?.height) || (natural ? (natural.height * width) / natural.width : 100);
    this.offset += 1;
    if (this.options.images === "rtfd") {
      const name = `image${this.assets.length + 1}.${extensionForMime(data.mime)}`;
      this.assets.push({ name, bytes: data.bytes });
      return `{{\\NeXTGraphic ${name} \\width${tw(width)} \\height${tw(height)} \\appleattachmentpadding0 \\appleembedtype0 \\appleaqc\n}\u00ac}`;
    }
    const blip = data.mime === "image/png" ? "\\pngblip" : data.mime === "image/jpeg" ? "\\jpegblip" : null;
    if (!blip) return "";
    let hex = "";
    for (let i = 0; i < data.bytes.length; i++) {
      hex += data.bytes[i].toString(16).padStart(2, "0");
      if (i % 64 === 63) hex += "\n";
    }
    return `{\\pict${blip}\\picw${natural?.width ?? Math.round(width)}\\pich${natural?.height ?? Math.round(height)}\\picwgoal${tw(width)}\\pichgoal${tw(height)}\n${hex}}`;
  }
}

interface RunLook {
  font: string;
  size: number;
  bold: boolean;
  italic: boolean;
  color: string | null;
}

const BULLETS = ["\u2022", "\u25e6", "\u25aa"];

/** One bullet list (ls1: disc, circle, square) and one numbered list (ls2), in the form macOS writes. */
const LIST_TABLE = [
  "{\\*\\listtable",
  "{\\list\\listtemplateid1\\listhybrid",
  ...["disc", "circle", "square"].map((marker, level) =>
    `{\\listlevel\\levelnfc23\\levelnfcn23\\leveljc0\\leveljcn0\\levelfollow0\\levelstartat1\\levelspace360\\levelindent0{\\*\\levelmarker \\{${marker}\\}}{\\leveltext\\leveltemplateid${level + 1}\\'01\\u${BULLETS[level].charCodeAt(0)} ;}{\\levelnumbers;}\\fi-360\\li${720 * (level + 1)}\\lin${720 * (level + 1)} }`),
  "{\\listname ;}\\listid1}",
  "{\\list\\listtemplateid2\\listhybrid",
  ...[0, 1, 2].map((level) =>
    `{\\listlevel\\levelnfc0\\levelnfcn0\\leveljc0\\leveljcn0\\levelfollow0\\levelstartat1\\levelspace360\\levelindent0{\\*\\levelmarker \\{decimal\\}.}{\\leveltext\\leveltemplateid${level + 11}\\'02\\'0${level}.;}{\\levelnumbers\\'01;}\\fi-360\\li${720 * (level + 1)}\\lin${720 * (level + 1)} }`),
  "{\\listname ;}\\listid2}}",
  "{\\*\\listoverridetable{\\listoverride\\listid1\\listoverridecount0\\ls1}{\\listoverride\\listid2\\listoverridecount0\\ls2}}",
].join("");

/** Escapes text for an RTF body: specials, tabs and non-ASCII as \u. */
function escapeText(text: string): string {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    const ch = text[i];
    if (ch === "\\" || ch === "{" || ch === "}") out += "\\" + ch;
    else if (ch === "\t") out += "\\tab ";
    else if (ch === "\n" || ch === "\u2028") out += "\\line ";
    else if (code < 0x20) continue;
    else if (code < 0x80) out += ch;
    else out += `\\u${code > 32767 ? code - 65536 : code} `;
  }
  return out;
}

/** Escapes text in table entries (font names, URLs). */
function escapePlain(text: string): string {
  return escapeText(text).replace(/\\tab |\\line /g, " ");
}

function normalizeColor(value: string): string | null {
  const v = value.trim().toLowerCase();
  let match = /^#([0-9a-f]{6})$/.exec(v);
  if (match) return "#" + match[1];
  match = /^#([0-9a-f])([0-9a-f])([0-9a-f])$/.exec(v);
  if (match) return "#" + match[1] + match[1] + match[2] + match[2] + match[3] + match[3];
  const rgb = /^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(v);
  if (rgb) return "#" + [rgb[1], rgb[2], rgb[3]].map((n) => Math.min(255, Number(n)).toString(16).padStart(2, "0")).join("");
  return null;
}

function parseSize(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const match = /^([\d.]+)(pt|px)?$/.exec(value.trim());
  if (!match) return null;
  const n = parseFloat(match[1]);
  return match[2] === "px" ? n * 0.75 : n;
}

export function plainText(node: PMNode): string {
  if (node.text) return node.text;
  if (node.type === "hardBreak") return "\n";
  return (node.content ?? []).map(plainText).join(node.type === "doc" || node.type === "tableRow" ? "\n" : "");
}
