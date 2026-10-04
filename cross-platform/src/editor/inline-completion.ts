import { Extension } from "@tiptap/core";
import { Plugin, PluginKey, type EditorState, type Transaction } from "@tiptap/pm/state";
import { Decoration, DecorationSet, type EditorView } from "@tiptap/pm/view";
import { MAX_AFTER, MAX_BEFORE, cleanCompletion, shouldSuggest } from "./completion-text";

/**
 * Inline writing suggestions ("ghost text"). After a short pause at the end
 * of a paragraph, asks `complete` for a continuation and shows it in gray
 * after the cursor. Tab accepts it, Ctrl/Alt+Right accepts one word, Escape
 * dismisses it, and typing the suggested characters keeps the rest.
 */
export interface InlineCompletionOptions {
  /** Returns the raw continuation, or null when no model is available. */
  complete: (before: string, after: string, signal: AbortSignal) => Promise<string | null>;
  isEnabled: () => boolean;
  delay: number;
}

interface Suggestion {
  pos: number;
  text: string;
}

type Meta = { set: Suggestion | null };

export const completionKey = new PluginKey<Suggestion | null>("inlineCompletion");

export const InlineCompletion = Extension.create<InlineCompletionOptions>({
  name: "inlineCompletion",
  // Ahead of tables and lists, which also use Tab.
  priority: 1000,

  addOptions() {
    return { complete: async () => null, isEnabled: () => false, delay: 600 };
  },

  addKeyboardShortcuts() {
    const acceptWord = () => {
      const suggestion = completionKey.getState(this.editor.state);
      if (!suggestion || this.editor.state.selection.from !== suggestion.pos) return false;
      const match = /^\s*\S+/.exec(suggestion.text);
      if (!match) return false;
      this.editor.view.dispatch(this.editor.state.tr.insertText(match[0], suggestion.pos));
      return true;
    };
    return {
      Tab: () => {
        const suggestion = completionKey.getState(this.editor.state);
        if (!suggestion || this.editor.state.selection.from !== suggestion.pos) return false;
        const tr = this.editor.state.tr.insertText(suggestion.text, suggestion.pos).setMeta(completionKey, { set: null } satisfies Meta);
        this.editor.view.dispatch(tr);
        return true;
      },
      Escape: () => {
        if (!completionKey.getState(this.editor.state)) return false;
        this.editor.view.dispatch(this.editor.state.tr.setMeta(completionKey, { set: null } satisfies Meta));
        return true;
      },
      "Alt-ArrowRight": acceptWord,
      "Ctrl-ArrowRight": acceptWord,
    };
  },

  addProseMirrorPlugins() {
    const options = this.options;
    return [
      new Plugin<Suggestion | null>({
        key: completionKey,
        state: {
          init: () => null,
          apply(tr: Transaction, value: Suggestion | null, _old: EditorState, state: EditorState) {
            const meta = tr.getMeta(completionKey) as Meta | undefined;
            if (meta) return meta.set;
            if (!value) return null;
            if (tr.docChanged) {
              // Typing along with the suggestion keeps the rest of it.
              const { from, empty } = state.selection;
              if (empty && from > value.pos && from - value.pos < value.text.length) {
                const typed = state.doc.textBetween(value.pos, from, "\n");
                if (value.text.startsWith(typed) && tr.mapping.map(value.pos, -1) === value.pos) {
                  return { pos: from, text: value.text.slice(typed.length) };
                }
              }
              return null;
            }
            if (tr.selectionSet && (state.selection.from !== value.pos || !state.selection.empty)) return null;
            return value;
          },
        },
        props: {
          decorations(state) {
            const suggestion = completionKey.getState(state);
            if (!suggestion || state.selection.from !== suggestion.pos) return null;
            return DecorationSet.create(state.doc, [
              Decoration.widget(suggestion.pos, () => {
                const span = document.createElement("span");
                span.className = "ghost-suggestion";
                span.textContent = suggestion.text;
                span.setAttribute("aria-hidden", "true");
                return span;
              }, { side: 1, key: `ghost-${suggestion.pos}-${suggestion.text}` }),
            ]);
          },
        },
        view(view) {
          return new CompletionRequester(view, options);
        },
      }),
    ];
  },
});

class CompletionRequester {
  private timer: ReturnType<typeof setTimeout> | null = null;
  private controller: AbortController | null = null;

  constructor(private view: EditorView, private options: InlineCompletionOptions) {}

  update(view: EditorView, previous: EditorState) {
    this.view = view;
    const state = view.state;
    if (state.doc.eq(previous.doc)) {
      if (!state.selection.eq(previous.selection)) this.cancel();
      return;
    }
    this.cancel();
    if (completionKey.getState(state) || !this.options.isEnabled()) return;
    this.timer = setTimeout(() => this.request(), this.options.delay);
  }

  private async request() {
    const view = this.view;
    const state = view.state;
    const { selection } = state;
    if (!selection.empty || !view.hasFocus() || view.composing) return;
    const $pos = selection.$from;
    if (!$pos.parent.isTextblock || $pos.parent.type.name === "codeBlock") return;
    const paragraphText = $pos.parent.textBetween(0, $pos.parentOffset, "\n", " ");
    if (!shouldSuggest(paragraphText, $pos.parentOffset === $pos.parent.content.size)) return;

    const pos = selection.from;
    const before = state.doc.textBetween(Math.max(0, pos - MAX_BEFORE), pos, "\n", " ");
    const after = state.doc.textBetween(pos, Math.min(state.doc.content.size, pos + MAX_AFTER), "\n", " ");
    const controller = new AbortController();
    this.controller = controller;
    let raw: string | null = null;
    try {
      raw = await this.options.complete(before, after, controller.signal);
    } catch {
      return;
    }
    if (controller.signal.aborted || this.view.state.doc !== state.doc || this.view.state.selection.from !== pos || !raw) return;
    const text = cleanCompletion(raw, before);
    if (!text) return;
    this.view.dispatch(this.view.state.tr.setMeta(completionKey, { set: { pos, text } } satisfies Meta));
  }

  private cancel() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.controller?.abort();
    this.controller = null;
  }

  destroy() {
    this.cancel();
  }
}
