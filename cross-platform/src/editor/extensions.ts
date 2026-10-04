import { Extension, Node, mergeAttributes } from "@tiptap/core";
import Image from "@tiptap/extension-image";
import { Plugin, PluginKey, TextSelection, type EditorState } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

/** A hard page break (Insert ▸ Page Break). */
export const PageBreak = Node.create({
  name: "pageBreak",
  group: "block",
  atom: true,
  selectable: true,
  parseHTML() {
    return [
      { tag: "div.page-break" },
      { tag: "hr.page-break" },
      { tag: "br[style*='page-break']" },
    ];
  },
  renderHTML({ HTMLAttributes }) {
    return ["div", mergeAttributes(HTMLAttributes, { class: "page-break", "data-label": "Page Break" })];
  },
  addCommands() {
    return {
      setPageBreak: () => ({ chain }) => chain().insertContent([{ type: this.name }, { type: "paragraph" }]).run(),
    };
  },
  addKeyboardShortcuts() {
    return { "Mod-Enter": () => this.editor.commands.setPageBreak() };
  },
});

declare module "@tiptap/core" {
  interface Commands<ReturnType> {
    pageBreak: { setPageBreak: () => ReturnType };
    paragraphStyle: { setParagraphStyle: (style: string) => ReturnType };
    search: {
      setSearch: (query: string, caseSensitive?: boolean) => ReturnType;
      findNext: (backwards?: boolean) => ReturnType;
      replaceCurrent: (replacement: string) => ReturnType;
      replaceAll: (replacement: string) => ReturnType;
    };
  }
}

/**
 * The Mac app's named paragraph styles that have no Tiptap node of their own
 * (title, subtitle, caption, no spacing, headings 7–9) ride along as a
 * `wpStyle` attribute so they survive a round trip.
 */
export const ParagraphStyle = Extension.create({
  name: "paragraphStyle",
  addGlobalAttributes() {
    return [{
      types: ["paragraph", "heading"],
      attributes: {
        wpStyle: {
          default: null,
          parseHTML: (element) => element.getAttribute("data-style"),
          renderHTML: (attributes) => (attributes.wpStyle ? { "data-style": attributes.wpStyle } : {}),
        },
      },
    }];
  },
  addCommands() {
    return {
      setParagraphStyle: (style: string) => ({ chain }) => {
        const c = chain().focus();
        switch (style) {
          case "normal": return c.setParagraph().updateAttributes("paragraph", { wpStyle: null }).run();
          case "title": return c.setHeading({ level: 1 }).updateAttributes("heading", { wpStyle: "title" }).run();
          case "subtitle": case "caption": case "noSpacing":
            return c.setParagraph().updateAttributes("paragraph", { wpStyle: style }).run();
          case "quote": return c.setParagraph().toggleBlockquote().run();
          case "code": return c.toggleCodeBlock().run();
          default: {
            const level = Number(/^heading(\d)$/.exec(style)?.[1] ?? 1) as 1 | 2 | 3 | 4 | 5 | 6;
            return c.setHeading({ level }).updateAttributes("heading", { wpStyle: null }).run();
          }
        }
      },
    };
  },
});

/**
 * Images keep an explicit size in points, like the Mac app, rendered as CSS
 * points so they scale with the text.
 */
export const SizedImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (el) => cssPoints(el.style.width) ?? pixelsAsPoints(el.getAttribute("width")),
        renderHTML: () => ({}),
      },
      height: {
        default: null,
        parseHTML: (el) => cssPoints(el.style.height) ?? pixelsAsPoints(el.getAttribute("height")),
        renderHTML: () => ({}),
      },
    };
  },
  renderHTML({ node, HTMLAttributes }) {
    const { width } = node.attrs;
    const style = width ? `width: ${Math.round(width)}pt; height: auto;` : "";
    return ["img", mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, style ? { style } : {})];
  },
}).configure({ inline: true, allowBase64: true });

function cssPoints(value: string): number | null {
  const match = /^([\d.]+)(pt|px)$/.exec(value.trim());
  if (!match) return null;
  const n = parseFloat(match[1]);
  return match[2] === "px" ? n * 0.75 : n;
}

function pixelsAsPoints(value: string | null): number | null {
  const n = value ? parseFloat(value) : NaN;
  return Number.isFinite(n) && n > 0 ? n * 0.75 : null;
}

// MARK: - Find & Replace

interface SearchState {
  query: string;
  caseSensitive: boolean;
  matches: { from: number; to: number }[];
  current: number;
}

export const searchKey = new PluginKey<SearchState>("search");

function findMatches(state: EditorState, query: string, caseSensitive: boolean) {
  const matches: { from: number; to: number }[] = [];
  if (!query) return matches;
  const needle = caseSensitive ? query : query.toLowerCase();
  state.doc.descendants((node, pos) => {
    if (!node.isTextblock) return true;
    // Map text offsets in the block back to document positions.
    let text = "";
    const positions: number[] = [];
    node.forEach((child, offset) => {
      if (child.isText) {
        for (let i = 0; i < child.text!.length; i++) positions.push(pos + 1 + offset + i);
        text += child.text;
      } else {
        positions.push(pos + 1 + offset);
        text += "￼";
      }
    });
    const haystack = caseSensitive ? text : text.toLowerCase();
    let index = haystack.indexOf(needle);
    while (index >= 0) {
      matches.push({ from: positions[index], to: positions[index + needle.length - 1] + 1 });
      index = haystack.indexOf(needle, index + Math.max(needle.length, 1));
    }
    return false;
  });
  return matches;
}

export const Search = Extension.create({
  name: "search",
  addProseMirrorPlugins() {
    return [
      new Plugin<SearchState>({
        key: searchKey,
        state: {
          init: () => ({ query: "", caseSensitive: false, matches: [], current: -1 }),
          apply(tr, value, _old, state) {
            const meta = tr.getMeta(searchKey) as Partial<SearchState> | undefined;
            if (!meta && !tr.docChanged) return value;
            const next = { ...value, ...meta };
            next.matches = findMatches(state, next.query, next.caseSensitive);
            if (meta?.current === undefined) {
              // Keep pointing at the match at or after the selection.
              const from = state.selection.from;
              const index = next.matches.findIndex((m) => m.from >= from);
              next.current = next.matches.length ? (index >= 0 ? index : 0) : -1;
            }
            return next;
          },
        },
        props: {
          decorations(state) {
            const search = searchKey.getState(state);
            if (!search?.query || !search.matches.length) return null;
            return DecorationSet.create(state.doc, search.matches.map((m, i) =>
              Decoration.inline(m.from, m.to, { class: i === search.current ? "search-match current" : "search-match" })));
          },
        },
      }),
    ];
  },
  addCommands() {
    const select = (state: EditorState, index: number) => {
      const search = searchKey.getState(state)!;
      const match = search.matches[index];
      return match ? TextSelection.create(state.doc, match.from, match.to) : null;
    };
    return {
      setSearch: (query: string, caseSensitive = false) => ({ tr, dispatch }) => {
        if (dispatch) tr.setMeta(searchKey, { query, caseSensitive });
        return true;
      },
      findNext: (backwards = false) => ({ state, tr, dispatch }) => {
        const search = searchKey.getState(state);
        if (!search?.matches.length) return false;
        const count = search.matches.length;
        const from = state.selection.from;
        let index: number;
        if (backwards) {
          index = search.matches.map((m) => m.from < from).lastIndexOf(true);
          if (index < 0) index = count - 1;
        } else {
          index = search.matches.findIndex((m) => m.from > from || (m.from === from && state.selection.empty));
          if (index < 0) index = 0;
        }
        const selection = select(state, index);
        if (!selection) return false;
        if (dispatch) tr.setSelection(selection).setMeta(searchKey, { current: index }).scrollIntoView();
        return true;
      },
      /** Replaces the selected match; call findNext afterwards to move on. */
      replaceCurrent: (replacement: string) => ({ state, tr, dispatch }) => {
        const search = searchKey.getState(state);
        const match = search?.matches.find((m) => m.from === state.selection.from && m.to === state.selection.to);
        if (!match) return false;
        if (dispatch) tr.insertText(replacement, match.from, match.to);
        return true;
      },
      replaceAll: (replacement: string) => ({ state, tr, dispatch }) => {
        const search = searchKey.getState(state);
        if (!search?.matches.length) return false;
        if (dispatch) {
          for (const match of [...search.matches].reverse()) tr.insertText(replacement, match.from, match.to);
        }
        return true;
      },
    };
  },
});
