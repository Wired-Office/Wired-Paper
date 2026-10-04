import { readDocx, writeDocx } from "./docx";
import type { LoadedDocument, PMNode, PageSetup } from "./model";
import { latin1Bytes, readPaper, writePaper } from "./paper";
import { readRTF } from "./rtf-read";
import { writeRTF } from "./rtf-write";

export type FormatID = "paper" | "docx" | "rtf" | "html" | "txt";

export interface FormatInfo {
  id: FormatID;
  name: string;
  extensions: string[];
  /** Saving in this format loses formatting, so it's offered under Export rather than as the document's format. */
  lossy?: boolean;
}

export const FORMATS: FormatInfo[] = [
  { id: "paper", name: "Wired Paper Document", extensions: ["paper"] },
  { id: "docx", name: "Word Document", extensions: ["docx"] },
  { id: "rtf", name: "Rich Text Document", extensions: ["rtf"] },
  { id: "html", name: "Web Page", extensions: ["html", "htm"] },
  { id: "txt", name: "Plain Text", extensions: ["txt", "text", "md"], lossy: true },
];

export function formatForPath(path: string): FormatInfo | undefined {
  const ext = path.split(/[\\/]/).pop()?.split(".").pop()?.toLowerCase() ?? "";
  return FORMATS.find((f) => f.extensions.includes(ext));
}

/** A loaded document: Tiptap JSON, or HTML for formats converted through HTML. */
export interface Loaded extends Omit<LoadedDocument, "doc"> {
  doc?: PMNode;
  html?: string;
}

export async function load(bytes: Uint8Array, format: FormatID): Promise<Loaded> {
  switch (format) {
    case "paper":
      return readPaper(bytes);
    case "rtf": {
      const { doc, pageSetup } = readRTF(bytes);
      return { doc, pageSetup, warnings: [] };
    }
    case "docx":
      return { html: await readDocx(bytes), warnings: [] };
    case "html": {
      const html = new TextDecoder().decode(bytes);
      const body = new DOMParser().parseFromString(html, "text/html").body;
      body.querySelectorAll("script, style, iframe, object, embed").forEach((el) => el.remove());
      return { html: body.innerHTML, warnings: [] };
    }
    case "txt": {
      const text = new TextDecoder().decode(bytes).replace(/\r\n?/g, "\n");
      return { doc: textToDoc(text), warnings: [] };
    }
  }
}

export interface SaveInput {
  doc: PMNode;
  html: string;
  text: string;
  title: string;
  pageSetup: PageSetup;
  metadata?: Record<string, unknown>;
}

export async function save(format: FormatID, input: SaveInput): Promise<Uint8Array> {
  switch (format) {
    case "paper":
      return writePaper(input.doc, input.pageSetup, input.metadata);
    case "rtf":
      return latin1Bytes(writeRTF(input.doc, { images: "embedded", pageSetup: input.pageSetup }).rtf);
    case "docx":
      return writeDocx(input.doc, input.pageSetup);
    case "html":
      return new TextEncoder().encode(htmlDocument(input));
    case "txt":
      return new TextEncoder().encode(input.text.replace(/\n/g, lineEnding()));
  }
}

export function textToDoc(text: string): PMNode {
  const lines = text.split("\n");
  if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
  return {
    type: "doc",
    content: lines.map((line) => (line ? { type: "paragraph", content: [{ type: "text", text: line.replace(/\t/g, "    ") }] } : { type: "paragraph" })),
  };
}

function htmlDocument({ html, title, pageSetup }: SaveInput): string {
  const [w, h] = pageSetup.paperSize;
  const m = pageSetup.margins;
  const escaped = title.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="generator" content="Wired Paper">
<title>${escaped}</title>
<style>
@page { size: ${w}pt ${h}pt; margin: ${m.top}pt ${m.right}pt ${m.bottom}pt ${m.left}pt; }
body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 12pt; line-height: 1.15; max-width: ${w - m.left - m.right}pt; margin: 2em auto; }
p { margin: 0 0 8pt; }
table { border-collapse: collapse; width: 100%; }
td, th { border: 1px solid #999; padding: 4pt 6pt; vertical-align: top; }
blockquote { margin: 4pt 36pt 8pt; font-style: italic; color: #5c636b; }
img { max-width: 100%; height: auto; }
.page-break { break-after: page; }
</style>
</head>
<body>
${html}
</body>
</html>
`;
}

function lineEnding(): string {
  return typeof navigator !== "undefined" && /Windows/i.test(navigator.userAgent) ? "\r\n" : "\n";
}
