import { Editor } from "@tiptap/core";
import Subscript from "@tiptap/extension-subscript";
import Superscript from "@tiptap/extension-superscript";
import { TableKit } from "@tiptap/extension-table";
import TextAlign from "@tiptap/extension-text-align";
import { TextStyleKit } from "@tiptap/extension-text-style";
import { Placeholder } from "@tiptap/extensions";
import StarterKit from "@tiptap/starter-kit";
import { bytesToDataURL, imageSize } from "../formats/model";
import { InlineCompletion, type InlineCompletionOptions } from "./inline-completion";
import { PageBreak, ParagraphStyle, Search, SizedImage } from "./extensions";

export interface EditorSetup {
  element: HTMLElement;
  completion: Omit<InlineCompletionOptions, "delay">;
  /** Widest an inserted image may be, in points. */
  maxImageWidth: () => number;
  onUpdate: () => void;
  onSelectionUpdate: () => void;
}

export function createEditor(setup: EditorSetup): Editor {
  const insertImageFiles = (editor: Editor, files: File[], pos?: number) => {
    const images = files.filter((f) => f.type.startsWith("image/"));
    if (!images.length) return false;
    for (const file of images) {
      file.arrayBuffer().then((buffer) => {
        const bytes = new Uint8Array(buffer);
        editor.chain().focus().insertContentAt(pos ?? editor.state.selection.from, imageNode(bytes, file.type, setup.maxImageWidth())).run();
      });
    }
    return true;
  };

  const editor: Editor = new Editor({
    element: setup.element,
    extensions: [
      StarterKit.configure({
        horizontalRule: false,
        link: { openOnClick: false, autolink: true, defaultProtocol: "https" },
        heading: { levels: [1, 2, 3, 4, 5, 6] },
      }),
      TextStyleKit.configure({ lineHeight: false }),
      TextAlign.configure({ types: ["heading", "paragraph"] }),
      Subscript,
      Superscript,
      SizedImage,
      TableKit.configure({ table: { resizable: true } }),
      Placeholder.configure({ placeholder: "Start writing…" }),
      PageBreak,
      ParagraphStyle,
      Search,
      InlineCompletion.configure({ ...setup.completion, delay: 600 }),
    ],
    content: { type: "doc", content: [{ type: "paragraph" }] },
    autofocus: "start",
    editorProps: {
      attributes: { spellcheck: "true", "aria-label": "Document" },
      handlePaste: (_view, event) => insertImageFiles(editor, Array.from(event.clipboardData?.files ?? [])),
      handleDrop: (view, event) => {
        const files = Array.from(event.dataTransfer?.files ?? []);
        if (!files.some((f) => f.type.startsWith("image/"))) return false;
        event.preventDefault();
        const pos = view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos;
        return insertImageFiles(editor, files, pos);
      },
    },
    onUpdate: setup.onUpdate,
    onSelectionUpdate: setup.onSelectionUpdate,
    onTransaction: ({ transaction }) => {
      if (!transaction.docChanged) setup.onSelectionUpdate();
    },
  });
  return editor;
}

/** An image node sized to fit the page (sizes in points, as in .paper files). */
export function imageNode(bytes: Uint8Array, mime: string, maxWidth: number) {
  const natural = imageSize(bytes);
  let width = natural?.width ?? null;
  let height = natural?.height ?? null;
  if (width && height && width > maxWidth) {
    height = Math.round((height * maxWidth) / width);
    width = Math.round(maxWidth);
  }
  return { type: "image", attrs: { src: bytesToDataURL(bytes, mime || "image/png"), width, height } };
}
