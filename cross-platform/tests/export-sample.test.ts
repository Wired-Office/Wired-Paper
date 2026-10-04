import { writeFileSync, readFileSync } from "node:fs";
import { it } from "vitest";
import { writePaper } from "../src/formats/paper";
import { bytesToDataURL } from "../src/formats/model";

it.runIf(process.env.EXPORT_SAMPLE)("writes a sample .paper for the Mac compatibility test", () => {
  const png = new Uint8Array(readFileSync(`${process.cwd()}/tests/fixtures/cocoa-sample.rtfd/pic.png`));
  const doc = { type: "doc", content: [
    { type: "heading", attrs: { level: 1 }, content: [{ type: "text", text: "Größe € Title" }] },
    { type: "paragraph", attrs: { textAlign: "center" }, content: [
      { type: "text", text: "bold", marks: [{ type: "bold" }] }, { type: "text", text: " plain " },
      { type: "text", text: "red18", marks: [{ type: "textStyle", attrs: { color: "#ff0000", fontSize: "18pt", fontFamily: '"Times New Roman", serif' } }] },
      { type: "hardBreak" }, { type: "text", text: "link", marks: [{ type: "link", attrs: { href: "https://wired.example" } }] },
      { type: "image", attrs: { src: bytesToDataURL(png, "image/png"), width: 40, height: 20 } },
    ] },
    { type: "bulletList", content: [
      { type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "Bullet A" }] }] },
      { type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "Bullet B" }] }] } ] },
    { type: "orderedList", content: [{ type: "listItem", content: [{ type: "paragraph", content: [{ type: "text", text: "Number 1" }] }] }] },
    { type: "table", content: [{ type: "tableRow", content: [
      { type: "tableCell", content: [{ type: "paragraph", content: [{ type: "text", text: "c1" }] }] },
      { type: "tableCell", content: [{ type: "paragraph", content: [{ type: "text", text: "c2" }] }] } ] }] },
    { type: "blockquote", content: [{ type: "paragraph", content: [{ type: "text", text: "Quote 😀" }] }] },
    { type: "paragraph", content: [{ type: "text", text: "End" }] },
  ] };
  writeFileSync(process.env.EXPORT_SAMPLE!, writePaper(doc, { paperSize: [595.28, 841.89], margins: { top: 72, left: 72, bottom: 72, right: 72 } }));
});
