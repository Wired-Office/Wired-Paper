import { aiStatus, resetModelCache } from "../ai";
import { PAPER_PRESETS, matchPreset, type PageSetup, type PaperPreset } from "../formats/model";
import { openURL } from "../platform";
import { settings, updateSettings } from "../settings";
import { APP_VERSION, platformName } from "../version";

interface DialogButton {
  label: string;
  value: string;
  primary?: boolean;
  /** Placed on the left, away from the main actions. */
  left?: boolean;
}

const dialog = () => document.getElementById("dialog") as HTMLDialogElement;

/** Shows a modal dialog; resolves with the clicked button's value, or null when dismissed. */
export function showDialog(title: string, body: HTMLElement | string, buttons: DialogButton[], onOpen?: (root: HTMLElement) => void): Promise<string | null> {
  const el = dialog();
  el.replaceChildren();
  const content = document.createElement("form");
  content.method = "dialog";
  const main = document.createElement("div");
  main.className = "dialog-body";
  const heading = document.createElement("h2");
  heading.textContent = title;
  main.append(heading);
  if (typeof body === "string") {
    const p = document.createElement("p");
    p.textContent = body;
    main.append(p);
  } else {
    main.append(body);
  }
  const actions = document.createElement("div");
  actions.className = "dialog-actions";
  for (const b of buttons) {
    const button = document.createElement("button");
    button.textContent = b.label;
    button.value = b.value;
    if (b.primary) button.className = "primary";
    if (b.left) button.classList.add("left");
    actions.append(button);
  }
  content.append(main, actions);
  el.append(content);
  return new Promise((resolve) => {
    el.onclose = () => resolve(el.returnValue && el.returnValue !== "cancel" ? el.returnValue : null);
    el.returnValue = "";
    el.showModal();
    onOpen?.(main);
    // Enter submits with the primary button.
    content.addEventListener("submit", (event) => {
      const submitter = (event as SubmitEvent).submitter as HTMLButtonElement | null;
      if (!submitter) {
        event.preventDefault();
        el.close(buttons.find((b) => b.primary)?.value ?? "");
      }
    });
  });
}

const html = (markup: string) => {
  const div = document.createElement("div");
  div.innerHTML = markup;
  return div;
};

const escape = (text: string) => text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

// MARK: Link

export async function linkDialog(currentURL: string, hasSelection: boolean): Promise<{ url: string; text?: string } | null | "remove"> {
  const body = html(`
    <div class="field"><label for="link-url">Address</label><input id="link-url" type="url" placeholder="https://example.com" value="${escape(currentURL)}"></div>
    ${hasSelection ? "" : '<div class="field"><label for="link-text">Text to display</label><input id="link-text" type="text"></div>'}`);
  const buttons: DialogButton[] = [{ label: "Cancel", value: "cancel" }, { label: currentURL ? "Update" : "Insert", value: "ok", primary: true }];
  if (currentURL) buttons.unshift({ label: "Remove Link", value: "remove", left: true });
  const result = await showDialog(currentURL ? "Edit Link" : "Insert Link", body, buttons, (root) => root.querySelector<HTMLInputElement>("#link-url")?.focus());
  if (result === "remove") return "remove";
  if (result !== "ok") return null;
  let url = body.querySelector<HTMLInputElement>("#link-url")!.value.trim();
  if (!url) return null;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) url = url.includes("@") && !url.includes("/") ? `mailto:${url}` : `https://${url}`;
  return { url, text: body.querySelector<HTMLInputElement>("#link-text")?.value.trim() || undefined };
}

// MARK: Table

export async function insertTableDialog(): Promise<{ rows: number; cols: number; header: boolean } | null> {
  const body = html(`
    <div class="field"><label for="t-cols">Columns</label><input id="t-cols" type="number" min="1" max="20" value="3"></div>
    <div class="field"><label for="t-rows">Rows</label><input id="t-rows" type="number" min="1" max="100" value="3"></div>
    <label class="toggle"><input id="t-header" type="checkbox"> First row is a header</label>`);
  const result = await showDialog("Insert Table", body, [{ label: "Cancel", value: "cancel" }, { label: "Insert", value: "ok", primary: true }]);
  if (result !== "ok") return null;
  const n = (id: string, max: number) => Math.min(Math.max(parseInt(body.querySelector<HTMLInputElement>(id)!.value, 10) || 1, 1), max);
  return { cols: n("#t-cols", 20), rows: n("#t-rows", 100), header: body.querySelector<HTMLInputElement>("#t-header")!.checked };
}

// MARK: Page setup

const metric = () => !/^en-(US|CA)$/i.test(navigator.language);

export async function pageSetupDialog(setup: PageSetup): Promise<PageSetup | null> {
  const unit = metric() ? { name: "cm", per: 72 / 2.54, step: 0.1 } : { name: "in", per: 72, step: 0.05 };
  const preset = matchPreset(setup);
  const landscape = setup.paperSize[0] > setup.paperSize[1];
  const value = (points: number) => (points / unit.per).toFixed(2).replace(/\.?0+$/, "");
  const marginField = (id: string, label: string, points: number) =>
    `<div class="field"><label for="${id}">${label} (${unit.name})</label><input id="${id}" type="number" min="0" step="${unit.step}" value="${value(points)}"></div>`;
  const body = html(`
    <div class="field"><label for="ps-paper">Paper size</label><select id="ps-paper">
      ${Object.entries(PAPER_PRESETS).map(([key, p]) => `<option value="${key}" ${key === preset ? "selected" : ""}>${p.name}</option>`).join("")}
      ${preset ? "" : `<option value="custom" selected>Custom (${Math.round(setup.paperSize[0])} × ${Math.round(setup.paperSize[1])} pt)</option>`}
    </select></div>
    <div class="field"><label for="ps-orientation">Orientation</label><select id="ps-orientation">
      <option value="portrait" ${landscape ? "" : "selected"}>Portrait</option><option value="landscape" ${landscape ? "selected" : ""}>Landscape</option>
    </select></div>
    <div class="section-title">Margins</div>
    ${marginField("ps-top", "Top", setup.margins.top)}${marginField("ps-bottom", "Bottom", setup.margins.bottom)}
    ${marginField("ps-left", "Left", setup.margins.left)}${marginField("ps-right", "Right", setup.margins.right)}`);
  const result = await showDialog("Page Setup", body, [{ label: "Cancel", value: "cancel" }, { label: "OK", value: "ok", primary: true }]);
  if (result !== "ok") return null;
  const get = (id: string) => body.querySelector<HTMLInputElement | HTMLSelectElement>(id)!.value;
  const chosen = get("#ps-paper");
  let [w, h] = chosen === "custom" ? setup.paperSize : PAPER_PRESETS[chosen as PaperPreset].size;
  [w, h] = [Math.min(w, h), Math.max(w, h)];
  if (get("#ps-orientation") === "landscape") [w, h] = [h, w];
  const margin = (id: string) => Math.max(0, (parseFloat(get(id)) || 0) * unit.per);
  const margins = { top: margin("#ps-top"), bottom: margin("#ps-bottom"), left: margin("#ps-left"), right: margin("#ps-right") };
  if (w - margins.left - margins.right < 72 || h - margins.top - margins.bottom < 72) {
    await showDialog("Margins Too Large", "The margins leave less than one inch for text. Choose smaller margins.", [{ label: "OK", value: "ok", primary: true }]);
    return null;
  }
  return { paperSize: [w, h], margins };
}

// MARK: Settings

export async function settingsDialog(checkNow: () => void): Promise<void> {
  const s = settings();
  const body = html(`
    <div class="section-title">Writing Suggestions</div>
    <label class="toggle"><input id="s-ai" type="checkbox" ${s.suggestions ? "checked" : ""}>
      <span>Suggest how to continue sentences<br><span class="note">Gray text at the end of a paragraph. Tab accepts, Ctrl+→ accepts one word, Esc dismisses.</span></span></label>
    <p class="note" id="s-ai-status">Checking for a local model…</p>
    <div class="field"><label for="s-model">Model</label><select id="s-model"><option value="">Automatic</option></select></div>
    <div class="field"><label for="s-url">Ollama address</label><input id="s-url" type="url" value="${escape(s.ollamaURL)}"></div>
    <div class="section-title">Editing</div>
    <label class="toggle"><input id="s-spell" type="checkbox" ${s.spellCheck ? "checked" : ""}> Check spelling while typing</label>
    <div class="section-title">Updates</div>
    <label class="toggle"><input id="s-updates" type="checkbox" ${s.checkForUpdates ? "checked" : ""}> Check for new versions automatically</label>
    <p class="note">Wired Paper ${APP_VERSION} for ${platformName()} · <a href="#" id="s-check">Check now</a></p>`);

  const refreshStatus = async () => {
    const status = body.querySelector<HTMLElement>("#s-ai-status")!;
    const select = body.querySelector<HTMLSelectElement>("#s-model")!;
    resetModelCache();
    const result = await aiStatus();
    if (result.state === "ready") {
      status.innerHTML = `Using <b>${escape(result.model)}</b> through Ollama on this computer. Your text never leaves it.`;
      select.replaceChildren(new Option("Automatic", ""), ...result.models.map((m) => new Option(m, m)));
      select.value = settings().ollamaModel;
    } else if (result.state === "no-models") {
      status.innerHTML = 'Ollama is running but has no models. Download one with <code>ollama pull llama3.2</code>, then reopen Settings.';
    } else {
      status.innerHTML = 'Suggestions run on a local model through Ollama. <a href="#" id="s-get-ollama">Install Ollama</a>, then run <code>ollama pull llama3.2</code>.';
      body.querySelector("#s-get-ollama")?.addEventListener("click", (e) => { e.preventDefault(); openURL("https://ollama.com/download"); });
    }
  };
  body.querySelector("#s-check")!.addEventListener("click", (e) => { e.preventDefault(); checkNow(); });
  body.querySelector("#s-url")!.addEventListener("change", (e) => {
    updateSettings({ ollamaURL: (e.target as HTMLInputElement).value.trim().replace(/\/+$/, "") || "http://127.0.0.1:11434" });
    refreshStatus();
  });

  // Closing the dialog either way keeps the changes, like a preferences window.
  await showDialog("Settings", body, [{ label: "Done", value: "ok", primary: true }], () => { refreshStatus(); });
  const checked = (id: string) => body.querySelector<HTMLInputElement>(id)!.checked;
  updateSettings({
    suggestions: checked("#s-ai"),
    spellCheck: checked("#s-spell"),
    checkForUpdates: checked("#s-updates"),
    ollamaModel: body.querySelector<HTMLSelectElement>("#s-model")!.value,
    ollamaURL: body.querySelector<HTMLInputElement>("#s-url")!.value.trim().replace(/\/+$/, "") || "http://127.0.0.1:11434",
  });
  resetModelCache();
}

// MARK: About

export async function aboutDialog(): Promise<void> {
  const body = html(`
    <p>Version ${APP_VERSION} for ${platformName()}</p>
    <p>A calm, capable word processor. Documents are saved as <b>.paper</b> files that open in Wired Paper on Mac, Windows and Linux.</p>
    <p class="note"><a href="#" id="about-site">github.com/Wired-Office/Wired-Paper</a></p>`);
  body.querySelector("#about-site")!.addEventListener("click", (e) => { e.preventDefault(); openURL("https://github.com/Wired-Office/Wired-Paper"); });
  await showDialog("Wired Paper", body, [{ label: "OK", value: "ok", primary: true }]);
}

// MARK: Updates

/** Release notes as plain text: Markdown markers and the generator footer removed. */
export function plainNotes(body: string): string {
  return body
    .replace(/\r\n/g, "\n")
    .split("\n")
    .filter((line) => !line.includes("Generated with [Claude Code]"))
    .map((line) => line.replace(/^[#>]+\s*/, "").replace(/^[-*]\s+/, "• ").replace(/\*\*(.+?)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1"))
    .join("\n")
    .trim();
}

export async function updateDialog(version: string, notes: string): Promise<"download" | "later" | "skip"> {
  const body = html(`<p>You have version ${APP_VERSION}. Download the new version and run the installer to update.</p><div class="notes"></div>`);
  body.querySelector(".notes")!.textContent = plainNotes(notes);
  const result = await showDialog(`Wired Paper ${version} is available`, body, [
    { label: "Skip This Version", value: "skip", left: true },
    { label: "Remind Me Later", value: "later" },
    { label: "Download", value: "download", primary: true },
  ]);
  return (result as "download" | "skip") ?? "later";
}
