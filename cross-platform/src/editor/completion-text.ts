/**
 * Pure text helpers for inline completions, a port of the Mac app's
 * `CompletionText` so suggestions behave the same on every platform.
 */
export const MAX_BEFORE = 2000;
export const MAX_AFTER = 400;
export const MAX_LENGTH = 140;

/**
 * Whether the insertion point is a good place to suggest: at the end of a
 * paragraph (`paragraphText` is the paragraph up to the cursor), after a few
 * real words, and not right after a finished sentence.
 */
export function shouldSuggest(paragraphText: string, atParagraphEnd: boolean): boolean {
  if (!atParagraphEnd || !paragraphText) return false;
  const words = paragraphText.split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 1);
  if (words.length < 3) return false;
  const last = paragraphText[paragraphText.length - 1];
  return /\p{L}/u.test(last) || last === " " || last === ",";
}

/** Turns raw model output into text that can be inserted after `before`, or null. */
export function cleanCompletion(raw: string, before: string): string | null {
  let text = raw.replace(/\r/g, "");
  const newline = text.indexOf("\n");
  if (newline >= 0) {
    const firstLine = text.slice(0, newline);
    text = firstLine.trim() ? firstLine : text.slice(newline).replace(/^\n+/, "").split("\n")[0];
  }
  for (const marker of ["<<<", ">>>", "Continuation:"]) text = text.split(marker).join("");

  // Strip quotes the model sometimes wraps its answer in.
  const trimmed = text.trim();
  for (const [open, close] of [['"', '"'], ["“", "”"], ["„", "“"], ["'", "'"]]) {
    if (trimmed.length > 2 && trimmed.startsWith(open) && trimmed.endsWith(close)) {
      text = (/^\s/.test(raw) ? " " : "") + trimmed.slice(open.length, -close.length);
      break;
    }
  }

  // Drop an echo of the text that is already there.
  const tail = before.slice(-80);
  const core = text.trim();
  if (core) {
    for (let length = Math.min(tail.length, core.length); length >= 12; length--) {
      if (core.startsWith(tail.slice(-length))) {
        text = core.slice(length);
        break;
      }
    }
  }

  // Spacing at the join.
  const endsWithSpace = before.length === 0 || /\s$/.test(before);
  if (endsWithSpace) text = text.replace(/^[ \t]+/, "");
  else if (/^\s/.test(text)) text = " " + text.replace(/^[ \t]+/, "");

  // Keep it short: stop after the first sentence, then at a word boundary.
  const end = text.search(/[.!?…]/);
  if (end >= 0) text = text.slice(0, end + 1);
  if (text.length > MAX_LENGTH) {
    const prefix = text.slice(0, MAX_LENGTH);
    const space = prefix.lastIndexOf(" ");
    text = space > 0 ? prefix.slice(0, space) : prefix;
  }
  text = text.replace(/ +$/, "");
  return /[\p{L}\p{N}]/u.test(text) ? text : null;
}

export const COMPLETION_INSTRUCTIONS =
  "You are an autocomplete engine inside a word processor. Continue the user's text " +
  "with the next few words they are most likely to write, matching their language, " +
  "tone, tense and point of view. Reply with the continuation only: no quotes, no " +
  "explanations, no repetition of the existing text. If the text ends in the middle " +
  "of a word, finish that word first. Stop at the end of the current sentence and " +
  "never write more than about 15 words.";

export function completionPrompt(before: string, after: string): string {
  let prompt = `Text before the cursor:\n<<<${before}>>>`;
  if (after) prompt += `\n\nText after the cursor (do not repeat it):\n<<<${after}>>>`;
  return prompt + "\n\nContinuation:";
}
