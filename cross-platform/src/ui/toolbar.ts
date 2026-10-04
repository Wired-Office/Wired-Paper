import type { Editor } from "@tiptap/core";
import { DEFAULT_FONT, DEFAULT_SIZE, fontStack, primaryFamily } from "../formats/model";
import { modKey } from "../version";

/** SVG paths for toolbar icons (16×16, stroked). */
const ICONS: Record<string, string> = {
  undo: '<path d="M4 6h6a3.5 3.5 0 0 1 0 7H7"/><path d="M6.5 3.5 4 6l2.5 2.5"/>',
  redo: '<path d="M12 6H6a3.5 3.5 0 0 0 0 7h3"/><path d="M9.5 3.5 12 6 9.5 8.5"/>',
  left: '<path d="M2.5 4h11M2.5 7h7M2.5 10h11M2.5 13h7"/>',
  center: '<path d="M2.5 4h11M4.5 7h7M2.5 10h11M4.5 13h7"/>',
  right: '<path d="M2.5 4h11M6.5 7h7M2.5 10h11M6.5 13h7"/>',
  justify: '<path d="M2.5 4h11M2.5 7h11M2.5 10h11M2.5 13h11"/>',
  bullets: '<circle cx="3" cy="4.5" r=".9"/><circle cx="3" cy="8" r=".9"/><circle cx="3" cy="11.5" r=".9"/><path d="M6 4.5h7.5M6 8h7.5M6 11.5h7.5"/>',
  numbers: '<path d="M2.2 3.5h1v3M2 6.5h2.2M2 9.6a1 1 0 1 1 1.6.9L2 12.5h2.2"/><path d="M6.5 4.5h7M6.5 8h7M6.5 11.5h7"/>',
  link: '<path d="M7 9a3 3 0 0 0 4.2.2l2-2a3 3 0 0 0-4.2-4.2l-1 1"/><path d="M9 7a3 3 0 0 0-4.2-.2l-2 2a3 3 0 0 0 4.2 4.2l1-1"/>',
  image: '<rect x="2" y="3" width="12" height="10" rx="1.5"/><circle cx="5.8" cy="6.5" r="1.2"/><path d="m2.5 12 3.5-3.5 2.5 2.5 2-2 3 3"/>',
  table: '<rect x="2" y="3" width="12" height="10" rx="1"/><path d="M2 6.5h12M2 10h12M6 3v10M10 3v10"/>',
  find: '<circle cx="7" cy="7" r="4"/><path d="m10 10 3.5 3.5"/>',
  clear: '<path d="M4 13h5M9.5 3 5 13M7 3h6"/><path d="m11 10 3 3m0-3-3 3"/>',
};

const icon = (name: string) => `<svg viewBox="0 0 16 16" aria-hidden="true">${ICONS[name]}</svg>`;

export const STYLE_OPTIONS: [string, string][] = [
  ["normal", "Normal"], ["title", "Title"], ["subtitle", "Subtitle"],
  ["heading1", "Heading 1"], ["heading2", "Heading 2"], ["heading3", "Heading 3"], ["heading4", "Heading 4"],
  ["quote", "Quote"], ["code", "Code"], ["caption", "Caption"], ["noSpacing", "No Spacing"],
];

const FONT_CANDIDATES = [
  DEFAULT_FONT, "Arial", "Calibri", "Cambria", "Candara", "Courier New", "Garamond", "Georgia", "Helvetica",
  "Segoe UI", "Tahoma", "Times New Roman", "Trebuchet MS", "Verdana", "Consolas", "Menlo",
  "Liberation Sans", "Liberation Serif", "DejaVu Sans", "DejaVu Serif", "Noto Sans", "Noto Serif", "Ubuntu", "Cantarell",
];

const SIZES = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72];

const TEXT_COLORS = [
  "#000000", "#434343", "#666666", "#999999", "#c0392b", "#d35400", "#b7950b", "#1e8449",
  "#117a65", "#124a59", "#1f618d", "#2e4053", "#6c3483", "#a93226", "#7e5109", "#0066cc",
];
const HIGHLIGHTS = [
  "#fff59d", "#ffe082", "#ffcc80", "#ffab91", "#f8bbd0", "#e1bee7", "#c5cae9", "#bbdefb",
  "#b2ebf2", "#b2dfdb", "#c8e6c9", "#dcedc8", "#f0f4c3", "#eeeeee", "#d7ccc8", "#cfd8dc",
];

/** Fonts installed on this computer (measured, since document.fonts.check is unreliable). */
function availableFonts(): string[] {
  const canvas = document.createElement("canvas").getContext("2d");
  if (!canvas) return FONT_CANDIDATES;
  const sample = "mmmmmmmmmmlli1WQ@#";
  const width = (font: string) => { canvas.font = `32px ${font}`; return canvas.measureText(sample).width; };
  const bases = ["monospace", "serif", "sans-serif"].map((b) => [b, width(b)] as const);
  return FONT_CANDIDATES.filter((name) => name === DEFAULT_FONT || bases.some(([base, w]) => width(`"${name}", ${base}`) !== w));
}

export interface ToolbarActions {
  insertLink: () => void;
  insertImage: () => void;
  insertTable: () => void;
  find: () => void;
}

export class Toolbar {
  private buttons = new Map<string, HTMLButtonElement>();
  private style!: HTMLSelectElement;
  private font!: HTMLSelectElement;
  private size!: HTMLSelectElement;
  private colorSwatch!: HTMLElement;
  private highlightSwatch!: HTMLElement;
  private lastColor = "#c0392b";
  private lastHighlight = "#fff59d";
  private fonts = availableFonts();

  constructor(private root: HTMLElement, private editor: Editor, private actions: ToolbarActions) {
    this.build();
  }

  private group(...children: HTMLElement[]) {
    const group = document.createElement("div");
    group.className = "tb-group";
    group.append(...children);
    this.root.append(group);
  }

  private button(id: string, label: string, content: string, run: () => void, shortcut?: string) {
    const button = document.createElement("button");
    button.className = "tb";
    button.innerHTML = content;
    button.title = shortcut ? `${label} (${shortcut})` : label;
    button.setAttribute("aria-label", label);
    button.addEventListener("mousedown", (e) => e.preventDefault());
    button.addEventListener("click", run);
    this.buttons.set(id, button);
    return button;
  }

  private select(id: string, label: string, options: [string, string][], onChange: (value: string) => void) {
    const select = document.createElement("select");
    select.className = "tb-select";
    select.id = id;
    select.title = label;
    select.setAttribute("aria-label", label);
    for (const [value, text] of options) select.add(new Option(text, value));
    select.addEventListener("change", () => onChange(select.value));
    return select;
  }

  private build() {
    const e = this.editor;
    const mod = modKey();
    const chain = () => e.chain().focus();

    this.group(
      this.button("undo", "Undo", icon("undo"), () => chain().undo().run(), `${mod}Z`),
      this.button("redo", "Redo", icon("redo"), () => chain().redo().run(), mod === "⌘" ? "⇧⌘Z" : "Ctrl+Y"),
    );

    this.style = this.select("tb-style", "Paragraph style", STYLE_OPTIONS, (v) => e.commands.setParagraphStyle(v));
    this.font = this.select("tb-font", "Font", this.fonts.map((f) => [f, f]), (v) => {
      if (v === DEFAULT_FONT) chain().unsetFontFamily().run();
      else chain().setFontFamily(fontStack(v)).run();
    });
    for (const option of Array.from(this.font.options)) option.style.fontFamily = fontStack(option.value);
    this.size = this.select("tb-size", "Font size", SIZES.map((s) => [String(s), String(s)]), (v) => {
      if (Number(v) === DEFAULT_SIZE) chain().unsetFontSize().run();
      else chain().setFontSize(`${v}pt`).run();
    });
    this.group(this.style, this.font, this.size);

    const color = this.button("color", "Text color", '<b style="font-family:Georgia,serif">A</b><span class="swatch"></span>', () => this.palette("color"));
    this.colorSwatch = color.querySelector(".swatch")!;
    const highlight = this.button("highlight", "Highlight", '<span style="font-weight:600;padding:0 1px">ab</span><span class="swatch"></span>', () => this.palette("highlight"));
    this.highlightSwatch = highlight.querySelector(".swatch")!;
    this.group(
      this.button("bold", "Bold", "<b>B</b>", () => chain().toggleBold().run(), `${mod}B`),
      this.button("italic", "Italic", '<i style="font-family:Georgia,serif">I</i>', () => chain().toggleItalic().run(), `${mod}I`),
      this.button("underline", "Underline", "<u>U</u>", () => chain().toggleUnderline().run(), `${mod}U`),
      this.button("strike", "Strikethrough", "<s>S</s>", () => chain().toggleStrike().run()),
      this.button("superscript", "Superscript", "x<sup>2</sup>", () => chain().toggleSuperscript().run()),
      this.button("subscript", "Subscript", "x<sub>2</sub>", () => chain().toggleSubscript().run()),
      color, highlight,
      this.button("clear", "Clear formatting", icon("clear"), () => chain().unsetAllMarks().run()),
    );
    this.setSwatches();

    this.group(
      this.button("left", "Align left", icon("left"), () => chain().setTextAlign("left").run()),
      this.button("center", "Center", icon("center"), () => chain().setTextAlign("center").run()),
      this.button("right", "Align right", icon("right"), () => chain().setTextAlign("right").run()),
      this.button("justify", "Justify", icon("justify"), () => chain().setTextAlign("justify").run()),
    );
    this.group(
      this.button("bulletList", "Bulleted list", icon("bullets"), () => chain().toggleBulletList().run(), mod === "⌘" ? "⇧⌘8" : "Ctrl+Shift+8"),
      this.button("orderedList", "Numbered list", icon("numbers"), () => chain().toggleOrderedList().run(), mod === "⌘" ? "⇧⌘7" : "Ctrl+Shift+7"),
    );
    this.group(
      this.button("link", "Link", icon("link"), this.actions.insertLink, `${mod}K`),
      this.button("image", "Picture", icon("image"), this.actions.insertImage),
      this.button("table", "Table", icon("table"), this.actions.insertTable),
      this.button("find", "Find", icon("find"), this.actions.find, `${mod}F`),
    );
  }

  private setSwatches() {
    this.colorSwatch.style.background = this.lastColor;
    this.highlightSwatch.style.background = this.lastHighlight;
  }

  private palette(kind: "color" | "highlight") {
    document.querySelector(".palette")?.remove();
    const anchor = this.buttons.get(kind)!;
    const palette = document.createElement("div");
    palette.className = "palette";
    const rect = anchor.getBoundingClientRect();
    palette.style.left = `${rect.left}px`;
    palette.style.top = `${rect.bottom + 4}px`;
    const apply = (value: string | null) => {
      palette.remove();
      const chain = this.editor.chain().focus();
      if (kind === "color") {
        if (value) { this.lastColor = value; chain.setColor(value).run(); } else chain.unsetColor().run();
      } else {
        if (value) { this.lastHighlight = value; chain.setBackgroundColor(value).run(); } else chain.unsetBackgroundColor().run();
      }
      this.setSwatches();
    };
    for (const value of kind === "color" ? TEXT_COLORS : HIGHLIGHTS) {
      const swatch = document.createElement("button");
      swatch.style.background = value;
      swatch.title = value;
      swatch.addEventListener("mousedown", (e) => e.preventDefault());
      swatch.addEventListener("click", () => apply(value));
      palette.append(swatch);
    }
    const none = document.createElement("button");
    none.className = "wide";
    none.textContent = kind === "color" ? "Automatic" : "No Highlight";
    none.addEventListener("mousedown", (e) => e.preventDefault());
    none.addEventListener("click", () => apply(null));
    palette.append(none);
    document.body.append(palette);
    const dismiss = (event: MouseEvent) => {
      if (!palette.contains(event.target as Node) && event.target !== anchor) {
        palette.remove();
        document.removeEventListener("mousedown", dismiss);
      }
    };
    setTimeout(() => document.addEventListener("mousedown", dismiss));
  }

  /** Reflects the formatting at the selection. */
  refresh() {
    const e = this.editor;
    for (const mark of ["bold", "italic", "underline", "strike", "superscript", "subscript", "bulletList", "orderedList", "link"]) {
      this.buttons.get(mark)?.classList.toggle("active", e.isActive(mark));
    }
    for (const align of ["left", "center", "right", "justify"]) {
      const active = align === "left"
        ? !["center", "right", "justify"].some((a) => e.isActive({ textAlign: a }))
        : e.isActive({ textAlign: align });
      this.buttons.get(align)?.classList.toggle("active", active);
    }
    this.buttons.get("undo")!.disabled = !e.can().undo();
    this.buttons.get("redo")!.disabled = !e.can().redo();

    this.style.value = currentStyle(e);
    const style = e.getAttributes("textStyle");
    const family = primaryFamily(style.fontFamily) ?? DEFAULT_FONT;
    if (![...this.font.options].some((o) => o.value === family)) this.font.add(new Option(family, family));
    this.font.value = family;
    const size = /^([\d.]+)pt$/.exec(String(style.fontSize ?? ""))?.[1] ?? String(DEFAULT_SIZE);
    if (![...this.size.options].some((o) => o.value === size)) this.size.add(new Option(size, size));
    this.size.value = size;
  }
}

export function currentStyle(e: Editor): string {
  if (e.isActive("codeBlock")) return "code";
  if (e.isActive("blockquote")) return "quote";
  for (let level = 1; level <= 6; level++) {
    if (e.isActive("heading", { level })) {
      return e.getAttributes("heading").wpStyle === "title" ? "title" : `heading${Math.min(level, 4)}`;
    }
  }
  return (e.getAttributes("paragraph").wpStyle as string) || "normal";
}
