import { strFromU8, strToU8, unzipSync, zipSync, type Zippable } from "fflate";
import type { LoadedDocument, PMNode, PageSetup } from "./model";
import { readRTF } from "./rtf-read";
import { writeRTF } from "./rtf-write";
import { APP_VERSION, platformName } from "../version";

/**
 * `.paper`, Wired Paper's native single-file format, shared with the Mac app:
 *
 *     mimetype                 "application/vnd.wiredpaper.paper", stored first
 *     Document.json            page setup, styles and other metadata
 *     Content.rtfd/TXT.rtf     text and formatting (RTF)
 *     Content.rtfd/<images>    embedded pictures
 */
export const PAPER_MIME = "application/vnd.wiredpaper.paper";
const CONTENT = "Content.rtfd/";
const METADATA = "Document.json";
const FORMAT_VERSION = 1;

/** Mac-only data this app can't edit; it would point at the wrong text after editing. */
const MAC_ONLY: Record<string, string> = {
  comments: "comments",
  revisions: "tracked changes",
  footnotes: "footnotes",
};

export function readPaper(bytes: Uint8Array): LoadedDocument {
  let entries: Record<string, Uint8Array>;
  try {
    entries = unzipSync(bytes);
  } catch {
    throw new Error("The file is not a valid Wired Paper document.");
  }
  const mime = entries["mimetype"];
  if (mime && strFromU8(mime).trim() !== PAPER_MIME) throw new Error("The file is not a Wired Paper document.");

  let metadata: Record<string, unknown> | undefined;
  const json = entries[METADATA];
  if (json) {
    try {
      metadata = JSON.parse(strFromU8(json));
    } catch {
      // A damaged Document.json must never keep the user from their text.
    }
  }
  if (metadata && Number(metadata.formatVersion ?? 1) > FORMAT_VERSION) {
    throw new Error("This document was created by a newer version of Wired Paper. Update Wired Paper to open it.");
  }

  const rtfName = Object.keys(entries).find((name) => name.startsWith(CONTENT) && /\/TXT\.rtf$/i.test(name));
  if (!rtfName) throw new Error("The document's text is missing.");
  const runs = (metadata?.attributeRuns as Record<string, { location: number; length: number; value: string }[]> | undefined) ?? {};
  const legacyRuns = (metadata?.styleRuns as { location: number; length: number; style: string }[] | undefined) ?? [];
  const styleRuns = runs.WPParagraphStyle ?? legacyRuns.map((r) => ({ location: r.location, length: r.length, value: r.style }));

  const { doc, pageSetup: rtfSetup } = readRTF(entries[rtfName], {
    attachment: (name) => entries[CONTENT + name],
    styleRuns,
  });

  const warnings: string[] = [];
  const unsupported = Object.entries(MAC_ONLY)
    .filter(([key]) => Array.isArray(metadata?.[key]) && (metadata![key] as unknown[]).length > 0)
    .map(([, label]) => label);
  const otherRuns = Object.keys(runs).filter((key) => key !== "WPParagraphStyle" && runs[key]?.length);
  if (otherRuns.length && !unsupported.length) unsupported.push("some Mac-only formatting");
  if (unsupported.length) {
    warnings.push(`This document uses ${joinList(unsupported)} from Wired Paper for Mac. They are shown as plain text here and will be removed if you save it.`);
  }

  return { doc, pageSetup: parsePageSetup(metadata?.pageSetup) ?? rtfSetup, metadata, warnings };
}

export function writePaper(doc: PMNode, pageSetup: PageSetup, metadata?: Record<string, unknown>): Uint8Array {
  const { rtf, assets, styleRuns } = writeRTF(doc, { pageSetup, images: "rtfd" });
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const meta: Record<string, unknown> = { ...(metadata ?? {}) };
  meta.formatVersion = FORMAT_VERSION;
  meta.documentID ??= crypto.randomUUID().toUpperCase();
  meta.created ??= now;
  meta.modified = now;
  meta.generator = `Wired Paper ${APP_VERSION} (${platformName()})`;
  meta.pageSetup = { paperSize: pageSetup.paperSize, margins: pageSetup.margins };
  meta.attributeRuns = styleRuns.length ? { WPParagraphStyle: styleRuns } : {};
  delete meta.styleRuns;
  for (const key of Object.keys(MAC_ONLY)) meta[key] = [];

  const files: Zippable = {
    mimetype: [strToU8(PAPER_MIME), { level: 0 }],
    [METADATA]: [strToU8(JSON.stringify(sortKeys(meta), null, 2)), { level: 6 }],
    [CONTENT + "TXT.rtf"]: [latin1Bytes(rtf), { level: 6 }],
  };
  for (const asset of assets) files[CONTENT + asset.name] = [asset.bytes, { level: 0 }];
  return zipSync(files);
}

function parsePageSetup(value: unknown): PageSetup | undefined {
  const v = value as { paperSize?: unknown; margins?: Record<string, unknown> } | undefined;
  if (!v || !Array.isArray(v.paperSize) || v.paperSize.length !== 2 || !v.margins) return undefined;
  const [w, h] = v.paperSize.map(Number);
  const m = v.margins;
  const margins = { top: Number(m.top), left: Number(m.left), bottom: Number(m.bottom), right: Number(m.right) };
  if (!(w >= 144 && h >= 144) || Object.values(margins).some((n) => !(n >= 0))) return undefined;
  return { paperSize: [w, h], margins };
}

/** RTF from the writer is 7-bit apart from the RTFD attachment character (0xAC). */
export function latin1Bytes(text: string): Uint8Array {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xff;
  return bytes;
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value as object).sort().map((k) => [k, sortKeys((value as Record<string, unknown>)[k])]));
  }
  return value;
}

function joinList(items: string[]): string {
  return items.length <= 1 ? items.join("") : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}
