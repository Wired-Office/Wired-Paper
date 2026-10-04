import { COMPLETION_INSTRUCTIONS, completionPrompt } from "./editor/completion-text";
import { ollamaGenerate, ollamaModels } from "./platform";
import { settings } from "./settings";

/**
 * Writing suggestions from a local model served by Ollama
 * (https://ollama.com). Nothing leaves the computer: the desktop backend only
 * talks to Ollama on this machine.
 */

/** Smaller instruction-tuned models first: they answer fastest. */
const PREFERRED = ["llama3.2", "qwen2.5", "gemma3", "gemma2", "phi4-mini", "phi3", "mistral", "llama3.1", "llama3"];

let cachedModel: { url: string; model: string | null; at: number } | null = null;

export type AIStatus =
  | { state: "ready"; model: string; models: string[] }
  | { state: "no-models" }
  | { state: "not-running" };

export async function aiStatus(): Promise<AIStatus> {
  try {
    const models = await ollamaModels(settings().ollamaURL);
    if (!models.length) return { state: "no-models" };
    return { state: "ready", model: pickModel(models), models };
  } catch {
    return { state: "not-running" };
  }
}

function pickModel(models: string[]): string {
  const chosen = settings().ollamaModel;
  if (chosen && models.includes(chosen)) return chosen;
  const generative = models.filter((m) => !/embed|bge|minilm|nomic/i.test(m));
  for (const prefix of PREFERRED) {
    const match = generative.find((m) => m.startsWith(prefix));
    if (match) return match;
  }
  return generative[0] ?? models[0];
}

async function currentModel(): Promise<string | null> {
  const url = settings().ollamaURL;
  // Re-check every minute so a model pulled while the app runs is found.
  if (cachedModel && cachedModel.url === url && Date.now() - cachedModel.at < 60_000 && !settings().ollamaModel) return cachedModel.model;
  const status = await aiStatus();
  const model = status.state === "ready" ? status.model : null;
  cachedModel = { url, model, at: Date.now() };
  return model;
}

export async function complete(before: string, after: string, signal: AbortSignal): Promise<string | null> {
  const model = await currentModel();
  if (!model || signal.aborted) return null;
  return ollamaGenerate(settings().ollamaURL, model, COMPLETION_INSTRUCTIONS, completionPrompt(before, after));
}

export function resetModelCache() {
  cachedModel = null;
}
