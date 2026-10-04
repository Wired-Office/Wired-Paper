import "./styles.css";
import type { Editor } from "@tiptap/core";
import { EditorState } from "@tiptap/pm/state";
import { aiStatus, complete } from "./ai";
import { searchKey } from "./editor/extensions";
import { completionKey } from "./editor/inline-completion";
import { createEditor, imageNode } from "./editor/create";
import { FORMATS, formatForPath, load, save, type FormatID } from "./formats";
import { defaultPageSetup, emptyDoc } from "./formats/model";
import {
  askToSave, basename, chooseFileToOpen, chooseImage, chooseSaveLocation, initialFile, isDesktop,
  onWindowClose, openURL, readFile, setWindowTitle, showMessage, writeFile,
} from "./platform";
import { onSettingsChange, settings, updateSettings } from "./settings";
import {
  aboutDialog, insertTableDialog, linkDialog, pageSetupDialog, settingsDialog, showDialog, updateDialog,
} from "./ui/dialogs";
import { buildMenubar, type MenuEntry } from "./ui/menubar";
import { Toolbar } from "./ui/toolbar";
import { checkForUpdate, isCheckDue } from "./updates";
import { APP_VERSION, modKey, platformName } from "./version";

const PT = 4 / 3; // CSS pixels per point

/** The open document. One window edits one document. */
const state = {
  path: null as string | null,
  name: "Untitled",
  format: "paper" as FormatID,
  dirty: false,
  pageSetup: defaultPageSetup(),
  metadata: undefined as Record<string, unknown> | undefined,
  zoom: 1,
};

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

const editor: Editor = createEditor({
  element: $("editor"),
  completion: {
    complete: (before, after, signal) => complete(before, after, signal),
    isEnabled: () => settings().suggestions,
  },
  maxImageWidth: () => contentWidth() - 10,
  onUpdate: () => {
    setDirty(true);
    scheduleLayout();
  },
  onSelectionUpdate: () => {
    toolbar?.refresh();
    updateStatus();
  },
});

const toolbar = new Toolbar($("toolbar"), editor, {
  insertLink: () => editLink(),
  insertImage: () => insertImage(),
  insertTable: () => insertTable(),
  find: () => showFind(false),
});

// MARK: - Document state

function contentWidth() {
  const s = state.pageSetup;
  return s.paperSize[0] - s.margins.left - s.margins.right;
}

function setDirty(dirty: boolean) {
  if (state.dirty === dirty) return;
  state.dirty = dirty;
  (window as unknown as { __dirty?: boolean }).__dirty = dirty;
  updateTitle();
}

function updateTitle() {
  setWindowTitle(`${state.dirty ? "● " : ""}${state.name} — Wired Paper`);
}

function displayName(path: string) {
  return basename(path).replace(/\.[^.]+$/, "");
}

/** Replaces the editor contents without recording undo history. */
function setContent(content: { doc?: unknown; html?: string }) {
  if (content.html !== undefined) editor.commands.setContent(content.html, { emitUpdate: false });
  else editor.commands.setContent((content.doc ?? emptyDoc()) as never, { emitUpdate: false });
  // A fresh document starts with an empty undo stack.
  editor.view.updateState(EditorState.create({ doc: editor.state.doc, plugins: editor.state.plugins }));
  editor.commands.focus("start");
}

async function confirmDiscard(): Promise<boolean> {
  if (!state.dirty) return true;
  const answer = await askToSave(state.name);
  if (answer === "cancel") return false;
  if (answer === "save") return saveDocument();
  return true;
}

async function newDocument() {
  if (!(await confirmDiscard())) return;
  Object.assign(state, { path: null, name: "Untitled", format: "paper", pageSetup: defaultPageSetup(), metadata: undefined });
  setContent({ doc: emptyDoc() });
  applyPageSetup();
  setDirty(false);
  updateTitle();
}

async function openDocument(file?: { path: string | null; name: string; bytes: Uint8Array }) {
  if (!(await confirmDiscard())) return;
  const chosen = file ?? (await chooseFileToOpen());
  if (!chosen) return;
  const format = formatForPath(chosen.name);
  if (!format) {
    await showMessage(`Wired Paper can't open “${chosen.name}”. Supported formats: ${FORMATS.map((f) => "." + f.extensions[0]).join(", ")}.`, "error");
    return;
  }
  try {
    const loaded = await load(chosen.bytes, format.id);
    Object.assign(state, {
      // Lossy formats open as untitled copies so Save doesn't silently drop formatting.
      path: format.lossy ? null : chosen.path,
      name: displayName(chosen.name),
      format: format.lossy ? "paper" : format.id,
      pageSetup: loaded.pageSetup ?? defaultPageSetup(),
      metadata: loaded.metadata,
    });
    setContent(loaded);
    applyPageSetup();
    setDirty(false);
    updateTitle();
    if (chosen.path) addRecent(chosen.path);
    if (loaded.warnings.length) showBanner(loaded.warnings.join(" "), []);
    else hideBanner();
  } catch (error) {
    await showMessage(`“${chosen.name}” couldn't be opened.\n\n${(error as Error).message}`, "error");
  }
}

async function openPath(path: string) {
  try {
    await openDocument({ path, name: basename(path), bytes: await readFile(path) });
  } catch (error) {
    removeRecent(path);
    await showMessage(`“${basename(path)}” couldn't be opened.\n\n${(error as Error).message}`, "error");
  }
}

function saveInput() {
  return {
    doc: editor.getJSON() as never,
    html: editor.getHTML(),
    text: editor.getText({ blockSeparator: "\n" }),
    title: state.name,
    pageSetup: state.pageSetup,
    metadata: state.metadata,
  };
}

async function saveDocument(): Promise<boolean> {
  if (!state.path || !isDesktop) return saveDocumentAs();
  return writeDocument(state.path, state.format);
}

async function saveDocumentAs(): Promise<boolean> {
  const editable = FORMATS.filter((f) => !f.lossy).map((f) => f.id);
  const ordered: FormatID[] = [state.format, ...editable.filter((f) => f !== state.format)];
  const ext = FORMATS.find((f) => f.id === state.format)!.extensions[0];
  const path = await chooseSaveLocation(`${state.name}.${ext}`, ordered);
  if (!path) return false;
  const format = formatForPath(path)?.id ?? "paper";
  const finalPath = formatForPath(path) ? path : `${path}.paper`;
  const ok = await writeDocument(finalPath, format);
  if (ok) {
    Object.assign(state, { path: isDesktop ? finalPath : null, name: displayName(finalPath), format });
    if (isDesktop) addRecent(finalPath);
    updateTitle();
  }
  return ok;
}

async function writeDocument(path: string, format: FormatID): Promise<boolean> {
  try {
    await writeFile(path, await save(format, saveInput()));
    if (format === "paper") hideBanner();
    setDirty(false);
    return true;
  } catch (error) {
    await showMessage(`The document couldn't be saved.\n\n${(error as Error).message ?? error}`, "error");
    return false;
  }
}

async function exportAs(format: FormatID | "pdf") {
  if (format === "pdf") {
    await showMessage(`To create a PDF, choose “${platformName() === "Windows" ? "Microsoft Print to PDF" : "Print to File (PDF)"}” as the printer in the next window.`);
    printDocument();
    return;
  }
  const ext = FORMATS.find((f) => f.id === format)!.extensions[0];
  const path = await chooseSaveLocation(`${state.name}.${ext}`, [format]);
  if (!path) return;
  try {
    await writeFile(path, await save(format, saveInput()));
  } catch (error) {
    await showMessage(`The document couldn't be exported.\n\n${(error as Error).message}`, "error");
  }
}

function printDocument() {
  editor.view.dispatch(editor.state.tr.setMeta(completionKey, { set: null }));
  window.print();
}

// MARK: - Recent documents

const RECENT_KEY = "wiredpaper.recent";

function recentPaths(): string[] {
  try {
    return JSON.parse(localStorage.getItem(RECENT_KEY) ?? "[]");
  } catch {
    return [];
  }
}

function addRecent(path: string) {
  const list = [path, ...recentPaths().filter((p) => p !== path)].slice(0, 10);
  try { localStorage.setItem(RECENT_KEY, JSON.stringify(list)); } catch { /* not essential */ }
}

function removeRecent(path: string) {
  try { localStorage.setItem(RECENT_KEY, JSON.stringify(recentPaths().filter((p) => p !== path))); } catch { /* not essential */ }
}

// MARK: - Insert & format

async function editLink() {
  const current = (editor.getAttributes("link").href as string | undefined) ?? "";
  if (current) editor.chain().extendMarkRange("link").run();
  const result = await linkDialog(current, !editor.state.selection.empty);
  editor.commands.focus();
  if (!result) return;
  if (result === "remove") {
    editor.chain().focus().extendMarkRange("link").unsetLink().run();
  } else if (editor.state.selection.empty) {
    const text = result.text || result.url;
    editor.chain().focus().insertContent({ type: "text", text, marks: [{ type: "link", attrs: { href: result.url } }] }).run();
  } else {
    editor.chain().focus().extendMarkRange("link").setLink({ href: result.url }).run();
  }
}

async function insertImage() {
  const file = await chooseImage();
  if (!file) return;
  const ext = file.name.split(".").pop()?.toLowerCase();
  const mime = ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "gif" ? "image/gif" : ext === "webp" ? "image/webp" : ext === "bmp" ? "image/bmp" : "image/png";
  editor.chain().focus().insertContent(imageNode(file.bytes, mime, contentWidth() - 10)).run();
}

async function insertTable() {
  const options = await insertTableDialog();
  editor.commands.focus();
  if (options) editor.chain().focus().insertTable({ rows: options.rows, cols: options.cols, withHeaderRow: options.header }).run();
}

async function resizeImage(scale: number | null) {
  const { node } = editor.state.selection as unknown as { node?: { type: { name: string }; attrs: Record<string, unknown> } };
  if (node?.type.name !== "image") return;
  const width = Number(node.attrs.width) || 200;
  const height = Number(node.attrs.height) || 150;
  const max = contentWidth() - 10;
  let w = scale === null ? max : width * scale;
  w = Math.max(16, Math.min(w, max));
  editor.chain().focus().updateAttributes("image", { width: Math.round(w), height: Math.round((height * w) / width) }).run();
}

// MARK: - Page layout

function applyPageSetup() {
  const s = state.pageSetup;
  const sheet = $("sheet");
  sheet.style.width = `${s.paperSize[0] * PT}px`;
  sheet.style.padding = `${s.margins.top * PT}px ${s.margins.right * PT}px ${s.margins.bottom * PT}px ${s.margins.left * PT}px`;
  let style = document.getElementById("page-style");
  if (!style) {
    style = document.createElement("style");
    style.id = "page-style";
    document.head.append(style);
  }
  style.textContent = `@page { size: ${s.paperSize[0]}pt ${s.paperSize[1]}pt; margin: ${s.margins.top}pt ${s.margins.right}pt ${s.margins.bottom}pt ${s.margins.left}pt; }`;
  scheduleLayout();
}

let layoutPending = false;
let pageCount = 1;

function scheduleLayout() {
  if (layoutPending) return;
  layoutPending = true;
  requestAnimationFrame(() => {
    layoutPending = false;
    layoutPages();
  });
}

/**
 * Pages on screen: explicit page breaks grow to push what follows to the
 * next page, and dashed markers show where the printed pages end.
 */
function layoutPages() {
  const s = state.pageSetup;
  const pageContent = (s.paperSize[1] - s.margins.top - s.margins.bottom) * PT;
  const top = s.margins.top * PT;
  const editorEl = editor.view.dom as HTMLElement;

  const breaks = editorEl.querySelectorAll<HTMLElement>(".page-break");
  for (const el of breaks) el.style.height = "0px";
  for (const el of breaks) {
    // Grow the break so the next block starts just below the next page boundary
    // (offsets are within the editor; the break's bottom margin is 8px).
    const y = (el.getBoundingClientRect().top - editorEl.getBoundingClientRect().top) / state.zoom;
    const used = ((y % pageContent) + pageContent) % pageContent;
    el.style.height = `${Math.max(0, pageContent - used - 8 + 4)}px`;
  }

  const height = Math.max(editorEl.scrollHeight, 1);
  pageCount = Math.max(1, Math.ceil(height / pageContent));
  const sheet = $("sheet");
  sheet.style.minHeight = `${pageCount * pageContent + (s.margins.top + s.margins.bottom) * PT}px`;
  const markers = $("page-markers");
  markers.replaceChildren();
  for (let i = 1; i < pageCount; i++) {
    const marker = document.createElement("div");
    marker.className = "page-marker";
    marker.style.top = `${top + i * pageContent}px`;
    const label = document.createElement("span");
    label.textContent = `Page ${i + 1}`;
    marker.append(label);
    markers.append(marker);
  }
  applyZoom();
  updateStatus();
}

function applyZoom() {
  const sheet = $("sheet");
  const frame = $("sheet-frame");
  sheet.style.transform = state.zoom === 1 ? "" : `scale(${state.zoom})`;
  frame.style.width = `${sheet.offsetWidth * state.zoom}px`;
  frame.style.height = `${sheet.offsetHeight * state.zoom}px`;
  $<HTMLInputElement>("zoom").value = String(Math.round(state.zoom * 100));
  $("zoom-value").textContent = `${Math.round(state.zoom * 100)}%`;
}

function setZoom(zoom: number) {
  state.zoom = Math.min(2, Math.max(0.5, Math.round(zoom * 10) / 10));
  applyZoom();
}

function zoomToWidth() {
  const available = $("canvas").clientWidth - 48;
  setZoom(available / (state.pageSetup.paperSize[0] * PT));
}

// MARK: - Status bar

let statusPending = false;

function updateStatus() {
  if (statusPending) return;
  statusPending = true;
  requestAnimationFrame(() => {
    statusPending = false;
    const s = state.pageSetup;
    const pageContent = (s.paperSize[1] - s.margins.top - s.margins.bottom) * PT;
    let page = 1;
    try {
      const coords = editor.view.coordsAtPos(editor.state.selection.from);
      const editorTop = (editor.view.dom as HTMLElement).getBoundingClientRect().top;
      page = Math.min(pageCount, Math.floor((coords.top - editorTop) / state.zoom / pageContent) + 1);
    } catch { /* view not ready */ }
    $("status-page").textContent = `Page ${Math.max(page, 1)} of ${pageCount}`;
    const text = editor.state.selection.empty
      ? editor.getText({ blockSeparator: "\n" })
      : editor.state.doc.textBetween(editor.state.selection.from, editor.state.selection.to, "\n");
    const words = (text.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) ?? []).length;
    const label = editor.state.selection.empty ? "" : " selected";
    $("status-words").textContent = `${words.toLocaleString()} ${words === 1 ? "word" : "words"}${label} · ${text.replace(/\n/g, "").length.toLocaleString()} characters`;
  });
}

async function updateAIStatus() {
  const el = $("status-ai");
  if (!settings().suggestions) {
    el.className = "status-ai off";
    el.textContent = "";
    el.title = "";
    return;
  }
  const status = await aiStatus();
  el.className = `status-ai ${status.state === "ready" ? "ready" : ""}`;
  el.textContent = status.state === "ready" ? "Suggestions on" : "Suggestions off";
  el.title = status.state === "ready"
    ? `Writing suggestions from ${status.model} (Ollama, on this computer)`
    : status.state === "no-models" ? "Ollama has no models. Run: ollama pull llama3.2" : "Install Ollama to get writing suggestions. Click for details.";
}

// MARK: - Find & Replace

const findBar = $("findbar");
const findInput = $<HTMLInputElement>("find-input");
const replaceInput = $<HTMLInputElement>("replace-input");
const findCase = $<HTMLInputElement>("find-case");

function showFind(replace: boolean) {
  findBar.hidden = false;
  findBar.classList.toggle("replacing", replace || findBar.classList.contains("replacing"));
  const selected = editor.state.doc.textBetween(editor.state.selection.from, editor.state.selection.to, " ");
  if (selected && selected.length < 100 && !selected.includes("\n")) findInput.value = selected;
  findInput.focus();
  findInput.select();
  runSearch();
}

function hideFind() {
  findBar.hidden = true;
  findBar.classList.remove("replacing");
  editor.commands.setSearch("");
  editor.commands.focus();
}

function runSearch() {
  editor.commands.setSearch(findInput.value, findCase.checked);
  updateFindCount();
}

function updateFindCount() {
  const search = searchKey.getState(editor.state);
  const count = search?.matches.length ?? 0;
  $("find-count").textContent = !findInput.value ? "" : count ? `${(search!.current ?? 0) + 1} of ${count}` : "Not found";
}

findInput.addEventListener("input", runSearch);
findCase.addEventListener("change", runSearch);
findInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    editor.commands.findNext(event.shiftKey);
    updateFindCount();
  } else if (event.key === "Escape") {
    event.preventDefault();
    hideFind();
  }
});
replaceInput.addEventListener("keydown", (event) => {
  if (event.key === "Escape") hideFind();
});
findBar.addEventListener("click", (event) => {
  const action = (event.target as HTMLElement).closest("button")?.dataset.find;
  switch (action) {
    case "next": editor.commands.findNext(); break;
    case "prev": editor.commands.findNext(true); break;
    case "replace":
      if (!editor.commands.replaceCurrent(replaceInput.value)) editor.commands.findNext();
      else editor.commands.findNext();
      break;
    case "replace-all": {
      const count = searchKey.getState(editor.state)?.matches.length ?? 0;
      if (editor.commands.replaceAll(replaceInput.value)) $("find-count").textContent = `Replaced ${count}`;
      return;
    }
    case "close": hideFind(); return;
  }
  updateFindCount();
});

// MARK: - Banner (notices and updates)

function showBanner(message: string, buttons: { label: string; primary?: boolean; run: () => void }[]) {
  const banner = $("banner");
  banner.replaceChildren();
  const text = document.createElement("span");
  text.className = "message";
  text.textContent = message;
  banner.append(text);
  for (const b of buttons) {
    const button = document.createElement("button");
    button.textContent = b.label;
    if (b.primary) button.className = "primary";
    button.addEventListener("click", b.run);
    banner.append(button);
  }
  const close = document.createElement("button");
  close.className = "close";
  close.textContent = "×";
  close.setAttribute("aria-label", "Dismiss");
  close.addEventListener("click", hideBanner);
  banner.append(close);
  banner.hidden = false;
}

function hideBanner() {
  $("banner").hidden = true;
}

// MARK: - Updates

async function checkUpdates(userInitiated: boolean) {
  try {
    const offer = await checkForUpdate(userInitiated);
    if (!offer) {
      if (userInitiated) await showDialog("You're up to date", `Wired Paper ${APP_VERSION} is the newest version available.`, [{ label: "OK", value: "ok", primary: true }]);
      return;
    }
    const decide = async () => {
      const choice = await updateDialog(offer.version, offer.release.body ?? "");
      if (choice === "download") { hideBanner(); openURL(offer.url); }
      if (choice === "skip") { hideBanner(); updateSettings({ skippedVersion: offer.version }); }
    };
    if (userInitiated) await decide();
    else showBanner(`Wired Paper ${offer.version} is available.`, [
      { label: "What's New", run: decide },
      { label: "Download", primary: true, run: () => { hideBanner(); openURL(offer.url); } },
    ]);
  } catch (error) {
    if (userInitiated) await showMessage(`Couldn't check for updates.\n\n${(error as Error).message}`, "warning");
  }
}

// MARK: - Menus

const mod = modKey();
const isMac = mod === "⌘";
const key = (k: string) => (isMac ? `⌘${k}` : `Ctrl+${k}`);

buildMenubar($("menubar"), [
  {
    label: "File",
    items: (): MenuEntry[] => [
      { label: "New", shortcut: key("N"), action: newDocument },
      { label: "Open…", shortcut: key("O"), action: () => openDocument() },
      {
        label: "Open Recent",
        submenu: isDesktop ? recentPaths().map((path) => ({ label: basename(path), action: () => openPath(path) })) : [],
      },
      "-",
      { label: "Save", shortcut: key("S"), action: saveDocument },
      { label: "Save As…", shortcut: isMac ? "⇧⌘S" : "Ctrl+Shift+S", action: saveDocumentAs },
      {
        label: "Export",
        submenu: [
          { label: "PDF…", action: () => exportAs("pdf") },
          { label: "Word Document (.docx)…", action: () => exportAs("docx") },
          { label: "Rich Text (.rtf)…", action: () => exportAs("rtf") },
          { label: "Web Page (.html)…", action: () => exportAs("html") },
          { label: "Plain Text (.txt)…", action: () => exportAs("txt") },
        ],
      },
      "-",
      { label: "Page Setup…", action: async () => {
        const result = await pageSetupDialog(state.pageSetup);
        if (result) { state.pageSetup = result; applyPageSetup(); setDirty(true); }
      } },
      { label: "Print…", shortcut: key("P"), action: printDocument },
      ...(isDesktop ? ["-" as const, { label: "Quit", shortcut: isMac ? "⌘Q" : "Alt+F4", action: () => window.close() }] : []),
    ],
  },
  {
    label: "Edit",
    items: () => [
      { label: "Undo", shortcut: key("Z"), enabled: editor.can().undo(), action: () => editor.chain().focus().undo().run() },
      { label: "Redo", shortcut: isMac ? "⇧⌘Z" : "Ctrl+Y", enabled: editor.can().redo(), action: () => editor.chain().focus().redo().run() },
      "-",
      { label: "Cut", shortcut: key("X"), action: () => { editor.commands.focus(); document.execCommand("cut"); } },
      { label: "Copy", shortcut: key("C"), action: () => { editor.commands.focus(); document.execCommand("copy"); } },
      { label: "Paste", shortcut: key("V"), action: () => {
        navigator.clipboard.readText()
          .then((text) => editor.chain().focus().insertContent(text).run())
          .catch(() => showMessage(`Use ${key("V")} to paste.`));
      } },
      { label: "Select All", shortcut: key("A"), action: () => editor.chain().focus().selectAll().run() },
      "-",
      { label: "Find…", shortcut: key("F"), action: () => showFind(false) },
      { label: "Replace…", shortcut: isMac ? "⌥⌘F" : "Ctrl+H", action: () => showFind(true) },
      "-",
      { label: "Settings…", shortcut: key(","), action: openSettings },
    ],
  },
  {
    label: "Insert",
    items: () => [
      { label: "Picture…", action: insertImage },
      { label: "Table…", action: insertTable },
      { label: "Link…", shortcut: key("K"), action: editLink },
      "-",
      { label: "Page Break", shortcut: isMac ? "⌘↩" : "Ctrl+Enter", action: () => editor.chain().focus().setPageBreak().run() },
      { label: "Line Break", shortcut: "Shift+Enter", action: () => editor.chain().focus().setHardBreak().run() },
      { label: "Date", action: () => editor.chain().focus().insertContent(new Date().toLocaleDateString(undefined, { dateStyle: "long" })).run() },
    ],
  },
  {
    label: "Format",
    items: () => [
      { label: "Bold", shortcut: key("B"), checked: editor.isActive("bold"), action: () => editor.chain().focus().toggleBold().run() },
      { label: "Italic", shortcut: key("I"), checked: editor.isActive("italic"), action: () => editor.chain().focus().toggleItalic().run() },
      { label: "Underline", shortcut: key("U"), checked: editor.isActive("underline"), action: () => editor.chain().focus().toggleUnderline().run() },
      { label: "Strikethrough", checked: editor.isActive("strike"), action: () => editor.chain().focus().toggleStrike().run() },
      { label: "Superscript", checked: editor.isActive("superscript"), action: () => editor.chain().focus().toggleSuperscript().run() },
      { label: "Subscript", checked: editor.isActive("subscript"), action: () => editor.chain().focus().toggleSubscript().run() },
      { label: "Clear Formatting", action: () => editor.chain().focus().unsetAllMarks().clearNodes().run() },
      "-",
      {
        label: "Style",
        submenu: [
          ["normal", "Normal"], ["title", "Title"], ["subtitle", "Subtitle"], ["heading1", "Heading 1"], ["heading2", "Heading 2"],
          ["heading3", "Heading 3"], ["quote", "Quote"], ["code", "Code"], ["caption", "Caption"],
        ].map(([id, label]) => ({ label, action: () => editor.commands.setParagraphStyle(id) })),
      },
      {
        label: "Alignment",
        submenu: (["left", "center", "right", "justify"] as const).map((a) => ({
          label: a === "justify" ? "Justify" : a[0].toUpperCase() + a.slice(1),
          checked: editor.isActive({ textAlign: a }),
          action: () => editor.chain().focus().setTextAlign(a).run(),
        })),
      },
      {
        label: "Lists",
        submenu: [
          { label: "Bulleted List", checked: editor.isActive("bulletList"), action: () => editor.chain().focus().toggleBulletList().run() },
          { label: "Numbered List", checked: editor.isActive("orderedList"), action: () => editor.chain().focus().toggleOrderedList().run() },
          "-",
          { label: "Increase Level", shortcut: "Tab", enabled: editor.can().sinkListItem("listItem"), action: () => editor.chain().focus().sinkListItem("listItem").run() },
          { label: "Decrease Level", shortcut: "Shift+Tab", enabled: editor.can().liftListItem("listItem"), action: () => editor.chain().focus().liftListItem("listItem").run() },
        ],
      },
      {
        label: "Table",
        submenu: [
          { label: "Insert Row Above", enabled: editor.can().addRowBefore(), action: () => editor.chain().focus().addRowBefore().run() },
          { label: "Insert Row Below", enabled: editor.can().addRowAfter(), action: () => editor.chain().focus().addRowAfter().run() },
          { label: "Insert Column Left", enabled: editor.can().addColumnBefore(), action: () => editor.chain().focus().addColumnBefore().run() },
          { label: "Insert Column Right", enabled: editor.can().addColumnAfter(), action: () => editor.chain().focus().addColumnAfter().run() },
          "-",
          { label: "Delete Row", enabled: editor.can().deleteRow(), action: () => editor.chain().focus().deleteRow().run() },
          { label: "Delete Column", enabled: editor.can().deleteColumn(), action: () => editor.chain().focus().deleteColumn().run() },
          { label: "Delete Table", enabled: editor.can().deleteTable(), action: () => editor.chain().focus().deleteTable().run() },
          "-",
          { label: "Merge Cells", enabled: editor.can().mergeCells(), action: () => editor.chain().focus().mergeCells().run() },
          { label: "Split Cell", enabled: editor.can().splitCell(), action: () => editor.chain().focus().splitCell().run() },
          { label: "Header Row", enabled: editor.can().toggleHeaderRow(), action: () => editor.chain().focus().toggleHeaderRow().run() },
        ],
      },
      {
        label: "Picture Size",
        submenu: [
          { label: "Smaller", action: () => resizeImage(0.8) },
          { label: "Larger", action: () => resizeImage(1.25) },
          { label: "Fit Page Width", action: () => resizeImage(null) },
        ],
      },
    ],
  },
  {
    label: "View",
    items: () => [
      { label: "Zoom In", shortcut: key("+"), action: () => setZoom(state.zoom + 0.1) },
      { label: "Zoom Out", shortcut: key("−"), action: () => setZoom(state.zoom - 0.1) },
      { label: "Actual Size", shortcut: key("0"), action: () => setZoom(1) },
      { label: "Fit Page Width", action: zoomToWidth },
    ],
  },
  {
    label: "Help",
    items: () => [
      { label: "Writing Suggestions…", action: openSettings },
      { label: "Check for Updates…", action: () => checkUpdates(true) },
      { label: "Wired Paper on GitHub", action: () => openURL("https://github.com/Wired-Office/Wired-Paper") },
      "-",
      { label: "About Wired Paper", action: aboutDialog },
    ],
  },
], () => editor.commands.focus());

async function openSettings() {
  await settingsDialog(() => checkUpdates(true));
  editor.commands.focus();
}

// MARK: - Keyboard shortcuts (app-level; formatting shortcuts belong to the editor)

document.addEventListener("keydown", (event) => {
  const primary = isMac ? event.metaKey : event.ctrlKey;
  if (!primary || event.altKey && !isMac) return;
  const k = event.key.toLowerCase();
  const run = (action: () => unknown) => { event.preventDefault(); action(); };
  if (k === "n" && !event.shiftKey) run(newDocument);
  else if (k === "o") run(() => openDocument());
  else if (k === "s") run(event.shiftKey ? saveDocumentAs : saveDocument);
  else if (k === "p") run(printDocument);
  else if (k === "f" && (!isMac || !event.altKey)) run(() => showFind(false));
  else if ((k === "h" && !isMac) || (k === "f" && isMac && event.altKey)) run(() => showFind(true));
  else if (k === "k") run(editLink);
  else if (k === ",") run(openSettings);
  else if (k === "=" || k === "+") run(() => setZoom(state.zoom + 0.1));
  else if (k === "-") run(() => setZoom(state.zoom - 0.1));
  else if (k === "0") run(() => setZoom(1));
  else if (k === "y" && !isMac) run(() => editor.chain().focus().redo().run());
});

// Drop a document onto the window to open it.
window.addEventListener("dragover", (event) => {
  if (event.dataTransfer?.types.includes("Files")) event.preventDefault();
});
window.addEventListener("drop", (event) => {
  const file = event.dataTransfer?.files[0];
  if (!file || file.type.startsWith("image/") || !formatForPath(file.name)) return;
  event.preventDefault();
  file.arrayBuffer().then((buffer) => openDocument({ path: null, name: file.name, bytes: new Uint8Array(buffer) }));
});

// MARK: - Status bar controls

$("zoom").addEventListener("input", (e) => setZoom(Number((e.target as HTMLInputElement).value) / 100));
$("zoom-in").addEventListener("click", () => setZoom(state.zoom + 0.1));
$("zoom-out").addEventListener("click", () => setZoom(state.zoom - 0.1));
$("zoom-value").addEventListener("click", () => setZoom(1));
$("status-ai").addEventListener("click", openSettings);
new ResizeObserver(scheduleLayout).observe(editor.view.dom);

function applySettings() {
  editor.view.dom.setAttribute("spellcheck", String(settings().spellCheck));
  if (!settings().suggestions) editor.view.dispatch(editor.state.tr.setMeta(completionKey, { set: null }));
  updateAIStatus();
}
onSettingsChange(applySettings);

// MARK: - Start

async function start() {
  applyPageSetup();
  applySettings();
  updateTitle();
  toolbar.refresh();
  await onWindowClose(confirmDiscard);
  const path = await initialFile();
  if (path) await openPath(path);
  setInterval(updateAIStatus, 60_000);
  const scheduleUpdateCheck = () => { if (isCheckDue()) checkUpdates(false); };
  setTimeout(scheduleUpdateCheck, 5000);
  setInterval(scheduleUpdateCheck, 60 * 60 * 1000);
}

start();

// Handle for debugging in development builds only.
if (import.meta.env.DEV) (window as unknown as { __wp: unknown }).__wp = { editor, state };
