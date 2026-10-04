import { describe, expect, it } from "vitest";
import { cleanCompletion, shouldSuggest } from "../src/editor/completion-text";
import { compareVersions, downloadURL, parseVersion, updateFrom, type Release } from "../src/updates";
import { plainNotes } from "../src/ui/dialogs";

describe("completion text (same rules as the Mac app)", () => {
  it("cleans model output", () => {
    expect(cleanCompletion(" brown fox jumps.", "The quick ")).toBe("brown fox jumps.");
    expect(cleanCompletion(" brown fox", "The quick")).toBe(" brown fox");
    expect(cleanCompletion("ick brown fox", "The qu")).toBe("ick brown fox");
    expect(cleanCompletion("over the dog. Then it ran.\nMore", "It jumped ")).toBe("over the dog.");
    expect(cleanCompletion('"the meeting starts at noon"', "Remember that ")).toBe("the meeting starts at noon");
    expect(cleanCompletion("Remember that the meeting starts", "Please note: Remember that ")).toBe("the meeting starts");
    expect(cleanCompletion("  \n ", "Hello ")).toBeNull();
    expect(cleanCompletion("...", "Hello ")).toBeNull();
    const long = cleanCompletion("word ".repeat(60), "Some ")!;
    expect(long.length).toBeLessThanOrEqual(140);
    expect(long.endsWith("word")).toBe(true);
  });

  it("suggests only at the end of a paragraph with a few words", () => {
    expect(shouldSuggest("We went to the market", true)).toBe(true);
    expect(shouldSuggest("We went to the market", false)).toBe(false);
    expect(shouldSuggest("Next", true)).toBe(false);
    expect(shouldSuggest("This is the end.", true)).toBe(false);
    expect(shouldSuggest("Wir gingen über die Brücke ", true)).toBe(true);
  });
});

describe("updates", () => {
  const release = (tag: string, extra: Partial<Release> = {}): Release => ({
    tag_name: tag, html_url: `https://github.com/x/releases/tag/${tag}`, draft: false, prerelease: false,
    assets: [
      { name: "Wired-Paper-1.4.dmg", browser_download_url: "https://dl/mac.dmg" },
      { name: "Wired-Paper-1.4-windows-x64-setup.exe", browser_download_url: "https://dl/win.exe" },
      { name: "Wired-Paper-1.4-linux-x86_64.AppImage", browser_download_url: "https://dl/app.AppImage" },
      { name: "Wired-Paper-1.4-linux-amd64.deb", browser_download_url: "https://dl/app.deb" },
    ],
    ...extra,
  });

  it("compares versions", () => {
    expect(parseVersion("v1.10.0-beta")).toEqual([1, 10, 0]);
    expect(parseVersion("latest")).toBeNull();
    expect(compareVersions([1, 9], [1, 10])).toBe(-1);
    expect(compareVersions([1, 1], [1, 1, 0])).toBe(0);
  });

  it("offers only newer published releases and respects skipped versions", () => {
    expect(updateFrom(release("v1.4"), "1.3", "", false)).not.toBeNull();
    expect(updateFrom(release("v1.3"), "1.3", "", true)).toBeNull();
    expect(updateFrom(release("v1.4", { prerelease: true }), "1.3", "", true)).toBeNull();
    expect(updateFrom(release("v1.4"), "1.3", "1.4", false)).toBeNull();
    expect(updateFrom(release("v1.4"), "1.3", "1.4", true)).not.toBeNull();
  });

  it("picks the installer for this kind of installation", () => {
    expect(downloadURL(release("v1.4"), "windows")).toBe("https://dl/win.exe");
    expect(downloadURL(release("v1.4"), "appimage")).toBe("https://dl/app.AppImage");
    expect(downloadURL(release("v1.4"), "deb")).toBe("https://dl/app.deb");
    expect(downloadURL(release("v1.4", { assets: [] }), "windows")).toContain("/releases/tag/v1.4");
  });

  it("turns release notes into plain text", () => {
    expect(plainNotes("## What's new\n- **Tab** accepts `code`\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"))
      .toBe("What's new\n• Tab accepts code");
  });
});
