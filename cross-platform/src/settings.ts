/** App preferences, stored per machine. */
export interface Settings {
  suggestions: boolean;
  ollamaURL: string;
  /** Empty: pick the best installed model automatically. */
  ollamaModel: string;
  checkForUpdates: boolean;
  spellCheck: boolean;
  lastUpdateCheck: number;
  skippedVersion: string;
}

const KEY = "wiredpaper.settings";

const defaults: Settings = {
  suggestions: true,
  ollamaURL: "http://127.0.0.1:11434",
  ollamaModel: "",
  checkForUpdates: true,
  spellCheck: true,
  lastUpdateCheck: 0,
  skippedVersion: "",
};

let current: Settings = load();
const listeners = new Set<(settings: Settings) => void>();

function load(): Settings {
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem(KEY) ?? "{}") };
  } catch {
    return { ...defaults };
  }
}

export function settings(): Settings {
  return current;
}

export function updateSettings(change: Partial<Settings>) {
  current = { ...current, ...change };
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
  } catch {
    // Settings still apply for this session.
  }
  listeners.forEach((listener) => listener(current));
}

export function onSettingsChange(listener: (settings: Settings) => void) {
  listeners.add(listener);
}
