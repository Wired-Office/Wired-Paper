import {
  AlignmentType, Document, ExternalHyperlink, HeadingLevel, ImageRun, LevelFormat, Packer, PageBreak,
  PageOrientation, Paragraph, ShadingType, Table, TableCell, TableRow, TextRun, WidthType,
  type IRunOptions, type ParagraphChild,
} from "docx";
import { dataURLToBytes, imageSize, primaryFamily, type Mark, type PMNode, type PageSetup } from "./model";

/** Word documents: imported with mammoth (to HTML), exported with docx. */

export async function readDocx(bytes: Uint8Array): Promise<string> {
  const mammoth = (await import("mammoth")).default;
  const result = await mammoth.convertToHtml(
    { arrayBuffer: bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer },
    {
      convertImage: mammoth.images.imgElement(async (image) => ({
        src: `data:${image.contentType};base64,${await image.read("base64")}`,
      })),
    },
  );
  return result.value;
}

const HEADINGS = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3, HeadingLevel.HEADING_4, HeadingLevel.HEADING_5, HeadingLevel.HEADING_6];
const ALIGN: Record<string, (typeof AlignmentType)[keyof typeof AlignmentType]> = {
  center: AlignmentType.CENTER, right: AlignmentType.RIGHT, justify: AlignmentType.JUSTIFIED,
};
const tw = (points: number) => Math.round(points * 20);

export async function writeDocx(doc: PMNode, setup: PageSetup): Promise<Uint8Array> {
  const writer = new DocxWriter(setup);
  const children = writer.blocks(doc.content ?? []);
  const [w, h] = setup.paperSize;
  const levels = (format: "bullet" | "decimal") => [0, 1, 2, 3, 4].map((level) => ({
    level,
    format: format === "bullet" ? LevelFormat.BULLET : LevelFormat.DECIMAL,
    text: format === "bullet" ? ["•", "◦", "▪"][level % 3] : `%${level + 1}.`,
    alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 720 * (level + 1), hanging: 360 } } },
  }));
  const document = new Document({
    creator: "Wired Paper",
    styles: { default: { document: { run: { font: "Helvetica Neue", size: 24 }, paragraph: { spacing: { after: 160, line: 276 } } } } },
    numbering: {
      config: [
        { reference: "bullets", levels: levels("bullet") },
        { reference: "numbers", levels: levels("decimal") },
      ],
    },
    sections: [{
      properties: {
        page: {
          size: { width: tw(Math.min(w, h)), height: tw(Math.max(w, h)), orientation: w > h ? PageOrientation.LANDSCAPE : PageOrientation.PORTRAIT },
          margin: { top: tw(setup.margins.top), bottom: tw(setup.margins.bottom), left: tw(setup.margins.left), right: tw(setup.margins.right) },
        },
      },
      children: children.length ? children : [new Paragraph({})],
    }],
  });
  const base64 = await Packer.toBase64String(document);
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

class DocxWriter {
  private listInstance = 0;

  constructor(private setup: PageSetup) {}

  blocks(nodes: PMNode[], quote = false): (Paragraph | Table)[] {
    return nodes.flatMap((node) => this.block(node, quote));
  }

  private block(node: PMNode, quote: boolean): (Paragraph | Table)[] {
    const alignment = ALIGN[String(node.attrs?.textAlign ?? "")];
    switch (node.type) {
      case "paragraph":
        return [new Paragraph({
          children: this.inlines(node.content ?? [], quote ? { italics: true, color: "5C636B" } : {}),
          alignment,
          indent: quote ? { left: 720, right: 720 } : undefined,
        })];
      case "heading": {
        const level = Math.min(Math.max(Number(node.attrs?.level ?? 1), 1), 6);
        const heading = node.attrs?.wpStyle === "title" ? HeadingLevel.TITLE : HEADINGS[level - 1];
        return [new Paragraph({ children: this.inlines(node.content ?? []), heading, alignment })];
      }
      case "blockquote":
        return this.blocks(node.content ?? [], true);
      case "codeBlock": {
        const text = (node.content ?? []).map((n) => n.text ?? "").join("");
        return text.split("\n").map((line) => new Paragraph({ children: [new TextRun({ text: line, font: "Consolas", size: 20 })], spacing: { after: 0 } }));
      }
      case "bulletList":
      case "orderedList":
        return this.list(node, 0);
      case "table":
        return [this.table(node)];
      case "pageBreak":
        return [new Paragraph({ children: [new PageBreak()] })];
      case "horizontalRule":
        return [new Paragraph({ border: { bottom: { style: "single", size: 6, color: "999999", space: 1 } } })];
      default:
        return this.blocks(node.content ?? [], quote);
    }
  }

  private list(node: PMNode, level: number): (Paragraph | Table)[] {
    const reference = node.type === "orderedList" ? "numbers" : "bullets";
    const instance = ++this.listInstance;
    const out: (Paragraph | Table)[] = [];
    for (const item of node.content ?? []) {
      for (const child of item.content ?? []) {
        if (child.type === "bulletList" || child.type === "orderedList") out.push(...this.list(child, level + 1));
        else if (child.type === "paragraph" || child.type === "heading") {
          out.push(new Paragraph({ children: this.inlines(child.content ?? []), numbering: { reference, level, instance } }));
        } else out.push(...this.block(child, false));
      }
    }
    return out;
  }

  private table(node: PMNode): Table {
    return new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      rows: (node.content ?? []).map((row) => new TableRow({
        children: (row.content ?? []).map((cell) => new TableCell({
          columnSpan: Number(cell.attrs?.colspan ?? 1),
          rowSpan: Number(cell.attrs?.rowspan ?? 1),
          children: this.blocks(cell.content ?? []).filter((b): b is Paragraph => b instanceof Paragraph),
          shading: cell.type === "tableHeader" ? { type: ShadingType.CLEAR, fill: "F2F2F2", color: "auto" } : undefined,
        })),
      })),
    });
  }

  private inlines(nodes: PMNode[], base: Partial<IRunOptions> = {}): ParagraphChild[] {
    const out: ParagraphChild[] = [];
    for (const node of nodes) {
      if (node.type === "hardBreak") {
        out.push(new TextRun({ break: 1 }));
      } else if (node.type === "image") {
        const image = this.image(node);
        if (image) out.push(image);
      } else if (node.type === "text") {
        const link = node.marks?.find((m) => m.type === "link")?.attrs?.href as string | undefined;
        const run = new TextRun({ ...base, ...runOptions(node.marks ?? []), text: node.text ?? "", ...(link ? { style: "Hyperlink" } : {}) });
        out.push(link ? new ExternalHyperlink({ link, children: [run] }) : run);
      }
    }
    return out;
  }

  private image(node: PMNode): ImageRun | null {
    const data = dataURLToBytes(String(node.attrs?.src ?? ""));
    if (!data) return null;
    const type = ({ "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/bmp": "bmp" } as const)[data.mime as "image/png"];
    if (!type) return null;
    const natural = imageSize(data.bytes);
    const maxWidth = this.setup.paperSize[0] - this.setup.margins.left - this.setup.margins.right;
    let width = Number(node.attrs?.width) || natural?.width || 200;
    let height = Number(node.attrs?.height) || (natural ? (natural.height * width) / natural.width : 150);
    if (width > maxWidth) {
      height = (height * maxWidth) / width;
      width = maxWidth;
    }
    // docx sizes images in pixels at 96 dpi; editor sizes are points.
    return new ImageRun({ type, data: data.bytes, transformation: { width: Math.round(width * 4 / 3), height: Math.round(height * 4 / 3) } });
  }
}

function runOptions(marks: Mark[]): Partial<IRunOptions> {
  const options: Record<string, unknown> = {};
  for (const mark of marks) {
    switch (mark.type) {
      case "bold": options.bold = true; break;
      case "italic": options.italics = true; break;
      case "underline": options.underline = {}; break;
      case "strike": options.strike = true; break;
      case "superscript": options.superScript = true; break;
      case "subscript": options.subScript = true; break;
      case "code": options.font = "Consolas"; break;
      case "textStyle": {
        const attrs = mark.attrs ?? {};
        const family = primaryFamily(attrs.fontFamily);
        if (family) options.font = family;
        const size = /^([\d.]+)pt$/.exec(String(attrs.fontSize ?? ""));
        if (size) options.size = Math.round(parseFloat(size[1]) * 2);
        const color = hex(attrs.color);
        if (color) options.color = color;
        const background = hex(attrs.backgroundColor);
        if (background) options.shading = { type: ShadingType.CLEAR, fill: background, color: "auto" };
        break;
      }
    }
  }
  return options as Partial<IRunOptions>;
}

function hex(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = /^#?([0-9a-f]{6})$/i.exec(value.trim());
  if (match) return match[1].toUpperCase();
  const rgb = /^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(value);
  return rgb ? [rgb[1], rgb[2], rgb[3]].map((n) => Number(n).toString(16).padStart(2, "0")).join("").toUpperCase() : null;
}
