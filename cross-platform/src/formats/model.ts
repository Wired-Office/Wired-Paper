/** ProseMirror/Tiptap JSON, the editor's document model and the common ground of all codecs. */
export interface Mark {
  type: string;
  attrs?: Record<string, unknown>;
}

export interface PMNode {
  type: string;
  attrs?: Record<string, unknown>;
  content?: PMNode[];
  text?: string;
  marks?: Mark[];
}

export interface Margins {
  top: number;
  left: number;
  bottom: number;
  right: number;
}

/** Paper size and margins in points, matching the Mac app's `PageSetup`. */
export interface PageSetup {
  /** [width, height], already oriented. */
  paperSize: [number, number];
  margins: Margins;
}

export const PAPER_PRESETS = {
  letter: { name: "US Letter", size: [612, 792] as [number, number] },
  legal: { name: "US Legal", size: [612, 1008] as [number, number] },
  a4: { name: "A4", size: [595.28, 841.89] as [number, number] },
  a5: { name: "A5", size: [419.53, 595.28] as [number, number] },
};
export type PaperPreset = keyof typeof PAPER_PRESETS;

export function defaultPageSetup(): PageSetup {
  // US and Canada use Letter; everyone else A4.
  const region = (navigator.language || "en-US").split("-")[1]?.toUpperCase();
  const preset: PaperPreset = region === "US" || region === "CA" ? "letter" : "a4";
  return { paperSize: [...PAPER_PRESETS[preset].size], margins: { top: 72, left: 72, bottom: 72, right: 72 } };
}

export function matchPreset(setup: PageSetup): PaperPreset | null {
  const [w, h] = setup.paperSize;
  const portrait = [Math.min(w, h), Math.max(w, h)];
  for (const [key, preset] of Object.entries(PAPER_PRESETS)) {
    if (Math.abs(preset.size[0] - portrait[0]) < 2 && Math.abs(preset.size[1] - portrait[1]) < 2) return key as PaperPreset;
  }
  return null;
}

/** A document as loaded from disk. */
export interface LoadedDocument {
  doc: PMNode;
  pageSetup?: PageSetup;
  /** The raw Document.json of a .paper file, kept so saving preserves what we don't edit. */
  metadata?: Record<string, unknown>;
  /** Things the user should know, e.g. Mac-only features that won't survive saving. */
  warnings: string[];
}

export const emptyDoc = (): PMNode => ({ type: "doc", content: [{ type: "paragraph" }] });

/** The Mac app's named paragraph styles (`ParagraphStyleKind`). */
export type ParagraphStyleID =
  | "normal" | "noSpacing" | "title" | "subtitle" | "quote" | "caption" | "code"
  | "heading1" | "heading2" | "heading3" | "heading4" | "heading5" | "heading6"
  | "heading7" | "heading8" | "heading9";

export const DEFAULT_FONT = "Helvetica Neue";
export const DEFAULT_SIZE = 12;

/** Font stacks so Mac fonts degrade gracefully on Windows and Linux. */
export function fontStack(family: string): string {
  const name = family.split(",")[0].trim().replace(/^["']|["']$/g, "");
  const lower = name.toLowerCase();
  const quoted = /\s/.test(name) ? `"${name}"` : name;
  if (/mono|menlo|courier|consolas|code/.test(lower)) return `${quoted}, Menlo, Consolas, "DejaVu Sans Mono", monospace`;
  if (/times|georgia|garamond|baskerville|palatino|serif|cambria|book|minion|charter/.test(lower) && !/sans/.test(lower)) {
    return `${quoted}, Georgia, "Times New Roman", "DejaVu Serif", serif`;
  }
  return `${quoted}, "Helvetica Neue", Helvetica, Arial, "Liberation Sans", sans-serif`;
}

/** The first family of a CSS font-family list. */
export function primaryFamily(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  return value.split(",")[0].trim().replace(/^["']|["']$/g, "");
}

export function dataURLToBytes(src: string): { bytes: Uint8Array; mime: string } | null {
  const match = /^data:([^;,]+)?(;base64)?,(.*)$/s.exec(src);
  if (!match) return null;
  const mime = match[1] || "application/octet-stream";
  if (match[2]) {
    const binary = atob(match[3]);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return { bytes, mime };
  }
  return { bytes: new TextEncoder().encode(decodeURIComponent(match[3])), mime };
}

export function bytesToDataURL(bytes: Uint8Array, mime: string): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return `data:${mime};base64,${btoa(binary)}`;
}

export function mimeForFilename(name: string): string {
  const ext = name.split(".").pop()?.toLowerCase();
  switch (ext) {
    case "png": return "image/png";
    case "jpg": case "jpeg": return "image/jpeg";
    case "gif": return "image/gif";
    case "tif": case "tiff": return "image/tiff";
    case "heic": return "image/heic";
    case "webp": return "image/webp";
    case "bmp": return "image/bmp";
    case "pdf": return "application/pdf";
    default: return "application/octet-stream";
  }
}

export function extensionForMime(mime: string): string {
  switch (mime) {
    case "image/png": return "png";
    case "image/jpeg": return "jpg";
    case "image/gif": return "gif";
    case "image/webp": return "webp";
    case "image/bmp": return "bmp";
    case "image/tiff": return "tiff";
    default: return "bin";
  }
}

/** Reads the pixel size of PNG, JPEG and GIF data without decoding it. */
export function imageSize(bytes: Uint8Array): { width: number; height: number } | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length > 24 && bytes[0] === 0x89 && bytes[1] === 0x50) {
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (bytes.length > 10 && bytes[0] === 0x47 && bytes[1] === 0x49) {
    return { width: view.getUint16(6, true), height: view.getUint16(8, true) };
  }
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) return null;
      const marker = bytes[offset + 1];
      const length = view.getUint16(offset + 2);
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { width: view.getUint16(offset + 7), height: view.getUint16(offset + 5) };
      }
      offset += 2 + length;
    }
  }
  return null;
}
