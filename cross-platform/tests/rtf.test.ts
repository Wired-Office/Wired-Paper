import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { readRTF } from "../src/formats/rtf-read";
import { writeRTF } from "../src/formats/rtf-write";
import type { PMNode } from "../src/formats/model";

const fixture = (name: string) => new Uint8Array(readFileSync(`${process.cwd()}/tests/fixtures/${name}`));

/** Flattens text with marks for compact assertions. */
function runs(node: PMNode): string[] {
  if (node.type === "text") return [`${node.text}${node.marks?.length ? "[" + node.marks.map((m) => m.type + (m.attrs ? JSON.stringify(m.attrs) : "")).join(",") + "]" : ""}`];
  return (node.content ?? []).flatMap(runs);
}

describe("reading macOS RTFD", () => {
  const rtf = fixture("cocoa-sample.rtfd/TXT.rtf");
  const png = fixture("cocoa-sample.rtfd/pic.png");
  const { doc, pageSetup } = readRTF(rtf, {
    attachment: (name) => (name === "pic.png" ? png : undefined),
    styleRuns: [{ location: 0, length: 18, value: "heading1" }],
  });
  const blocks = doc.content!;

  it("reads page setup", () => {
    expect(pageSetup?.paperSize[0]).toBeCloseTo(595.25, 0);
    expect(pageSetup?.margins.left).toBe(90);
  });

  it("applies paragraph style runs and decodes CP1252", () => {
    expect(blocks[0]).toMatchObject({ type: "heading", attrs: { level: 1 } });
    expect(runs(blocks[0])).toEqual(["Heading Ünïcode €"]);
  });

  it("reads character formatting, colors and links", () => {
    const text = runs(blocks[1]);
    expect(text[0]).toBe('Bold [bold]');
    expect(text[1]).toBe('italic [italic]');
    expect(text[2]).toBe('under [underline]');
    expect(text).toContain('strike [strike]');
    expect(text.find((t) => t.startsWith("red"))).toBe('red[textStyle{"color":"#fb0007","backgroundColor":"#ffff0b"}]');
    expect(text.find((t) => t.includes("link"))).toBe(' link[link{"href":"https://example.com"}]');
  });

  it("reads lists without the marker text", () => {
    expect(blocks[2].type).toBe("bulletList");
    expect(blocks[2].content!.map((item) => runs(item).join(""))).toEqual(["Item one", "Item two"]);
  });

  it("reads tables", () => {
    const table = blocks[3];
    expect(table.type).toBe("table");
    expect(table.content!.map((row) => row.content!.map((cell) => runs(cell).join("")))).toEqual([["A1", "B1"], ["A2", "B2"]]);
  });

  it("reads RTFD images, sub- and superscript", () => {
    const para = blocks[4];
    const image = para.content![0];
    expect(image.type).toBe("image");
    expect(image.attrs).toMatchObject({ width: 20, height: 10 });
    expect(String(image.attrs!.src)).toMatch(/^data:image\/png;base64,/);
    expect(runs(para)).toEqual([" after image"]);
    expect(runs(blocks[5])).toEqual(["Sub", "2[subscript]", " sup", "3[superscript]"]);
  });
});

describe("writing RTF", () => {
  const doc: PMNode = {
    type: "doc",
    content: [
      { type: "heading", attrs: { level: 2 }, content: [{ type: "text", text: "Größe {1}" }] },
      { type: "paragraph", attrs: { textAlign: "center" }, content: [
        { type: "text", text: "bold", marks: [{ type: "bold" }] },
        { type: "text", text: " and " },
        { type: "text", text: "red", marks: [{ type: "textStyle", attrs: { color: "#ff0000", fontSize: "18pt", fontFamily: '"Times New Roman", serif' } }] },
        { type: "hardBreak" },
        { type: "text", text: "site", marks: [{ type: "link", attrs: { href: "https://wired.example" } }] },
      ] },
      { type: "orderedList", content: [
        { type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "One" }] }] },
        { type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "Two" }] },
          { type: "bulletList", content: [{ type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "Nested" }] }] }] }] },
      ] },
      { type: "table", content: [
        { type: "tableRow", content: [
          { type: "tableCell", content: [{ type: "paragraph", content: [{ type: "text", text: "x" }] }] },
          { type: "tableCell", content: [{ type: "paragraph", content: [{ type: "text", text: "y" }] }] },
        ] },
      ] },
      { type: "blockquote", content: [{ type: "paragraph", content: [{ type: "text", text: "Quoted" }] }] },
      { type: "paragraph", content: [{ type: "text", text: "😀 end" }] },
    ],
  };

  it("round-trips through the reader", () => {
    const written = writeRTF(doc, { images: "embedded", pageSetup: { paperSize: [612, 792], margins: { top: 72, left: 72, bottom: 72, right: 72 } } });
    const { doc: back, pageSetup } = readRTF(written.rtf, { styleRuns: written.styleRuns });
    const blocks = back.content!;
    expect(pageSetup?.paperSize).toEqual([612, 792]);
    expect(blocks[0]).toMatchObject({ type: "heading", attrs: { level: 2 } });
    expect(runs(blocks[0])).toEqual(["Größe {1}"]);
    expect(blocks[1].attrs).toEqual({ textAlign: "center" });
    expect(runs(blocks[1])).toEqual([
      "bold[bold]", " and ",
      'red[textStyle{"fontFamily":"\\"Times New Roman\\", Georgia, \\"Times New Roman\\", \\"DejaVu Serif\\", serif","fontSize":"18pt","color":"#ff0000"}]',
      'site[underline,link{"href":"https://wired.example"}]',
    ]);
    expect(blocks[1].content!.some((n) => n.type === "hardBreak")).toBe(true);
    expect(blocks[2].type).toBe("orderedList");
    expect(blocks[2].content![1].content![1].type).toBe("bulletList");
    expect(runs(blocks[2])).toEqual(["One", "Two", "Nested"]);
    expect(blocks[3].type).toBe("table");
    expect(blocks[4].type).toBe("blockquote");
    expect(runs(blocks[5])).toEqual(["😀 end"]);
  });

  it("records style runs in NSAttributedString offsets", () => {
    const { styleRuns } = writeRTF(doc, { images: "rtfd" });
    // "Größe {1}\n" = 10 UTF-16 units.
    expect(styleRuns[0]).toEqual({ location: 0, length: 10, value: "heading2" });
    expect(styleRuns.find((r) => r.value === "quote")).toBeDefined();
  });
});
