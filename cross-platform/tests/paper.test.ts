import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { strFromU8, strToU8, unzipSync, zipSync } from "fflate";
import { readPaper, writePaper } from "../src/formats/paper";
import type { PMNode } from "../src/formats/model";

const fixture = (name: string) => new Uint8Array(readFileSync(`${process.cwd()}/tests/fixtures/${name}`));
const text = (node: PMNode): string => node.text ?? (node.content ?? []).map(text).join("");

describe(".paper files", () => {
  it("opens a document written by Wired Paper for Mac", () => {
    const { doc, pageSetup, warnings } = readPaper(fixture("mac-sample.paper"));
    const blocks = doc.content!;
    expect(pageSetup?.paperSize).toEqual([612, 792]);
    expect(warnings).toEqual([]);
    expect(blocks[0]).toMatchObject({ type: "heading", attrs: { level: 1, wpStyle: "title" } });
    expect(text(blocks[0])).toBe("Mac Title");
    expect(blocks[1]).toMatchObject({ type: "heading", attrs: { level: 2 } });
    expect(blocks[2].content!.find((n) => n.text === "italic")?.marks).toEqual([{ type: "italic" }]);
    expect(blocks[3].type).toBe("blockquote");
    expect(text(blocks[3])).toBe("A quotation.");
    expect(blocks[4].type).toBe("orderedList");
    expect(blocks[4].content!.map(text)).toEqual(["First", "Second"]);
  });

  it("round-trips and keeps unknown metadata", () => {
    const original = readPaper(fixture("mac-sample.paper"));
    const metadata = { ...original.metadata, futureField: { keep: true }, comments: [{ id: "x" }] };
    const bytes = writePaper(original.doc, original.pageSetup!, metadata);
    const entries = unzipSync(bytes);
    expect(Object.keys(entries)[0]).toBe("mimetype");
    const json = JSON.parse(strFromU8(entries["Document.json"]));
    expect(json.futureField).toEqual({ keep: true });
    expect(json.comments).toEqual([]);
    expect(json.documentID).toBe(original.metadata!.documentID);
    expect(json.modified).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);

    const again = readPaper(bytes);
    expect(again.doc).toEqual(original.doc);
  });

  it("warns about Mac-only features", () => {
    const original = readPaper(fixture("mac-sample.paper"));
    const bytes = writePaper(original.doc, original.pageSetup!, original.metadata);
    const entries = unzipSync(bytes);
    const json = JSON.parse(strFromU8(entries["Document.json"]));
    json.comments = [{ id: "c1" }];
    json.revisions = [{ id: "r1" }];
    const patched = zipSync({ ...entries, "Document.json": strToU8(JSON.stringify(json)) });
    expect(readPaper(patched).warnings[0]).toContain("comments and tracked changes");
  });

  it("rejects other ZIP files and newer formats", () => {
    expect(() => readPaper(zipSync({ mimetype: strToU8("application/zip") }))).toThrow(/not a Wired Paper/);
    expect(() => readPaper(new Uint8Array([1, 2, 3]))).toThrow(/not a valid/);
    const newer = zipSync({ mimetype: strToU8("application/vnd.wiredpaper.paper"), "Document.json": strToU8('{"formatVersion": 9}'), "Content.rtfd/TXT.rtf": strToU8("{\\rtf1 x}") });
    expect(() => readPaper(newer)).toThrow(/newer version/);
  });
});
