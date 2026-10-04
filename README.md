# Wired Paper

A word processor with a familiar document workflow for **macOS, Windows and Linux**.

- **macOS:** a native app written in Swift, with AppKit/TextKit for the editor and SwiftUI for the surrounding interface. No third-party dependencies.
- **Windows and Linux:** a desktop app built with [Tauri](https://tauri.app) (Rust plus a web-based editor) in [`cross-platform/`](cross-platform/).

Both read and write the same **`.paper`** files, so documents move freely between computers.

## Download

Get the latest version from [Releases](https://github.com/Wired-Office/Wired-Paper/releases/latest):

| Platform | File |
| --- | --- |
| macOS 14+ (Apple silicon and Intel) | `Wired-Paper-<version>.dmg` |
| Windows 10/11 (x64) | `Wired-Paper-<version>-windows-x64-setup.exe` |
| Linux (x86_64), any distribution | `Wired-Paper-<version>-linux-x86_64.AppImage` |
| Debian, Ubuntu, Mint… | `Wired-Paper-<version>-linux-amd64.deb` |

The builds aren't signed by Apple or Microsoft yet, so on first launch macOS asks you to confirm (right-click ▸ Open), and Windows SmartScreen asks you to confirm (More info ▸ Run anyway). For the AppImage, make the file executable (`chmod +x`) and run it.

## Building the Mac app

Open `WiredPaper.xcodeproj` in Xcode (26 or later) and run the **WiredPaper** scheme. It requires macOS 14 or later.

From the command line:

```bash
xcodebuild -project WiredPaper.xcodeproj -scheme WiredPaper build
xcodebuild -project WiredPaper.xcodeproj -scheme WiredPaper test
```

The project uses file-system-synchronized groups, so new source files placed under `WiredPaper/` are picked up automatically.

## Building the Windows and Linux app

Needs Node.js 20+ and Rust (stable). On Linux, also install the WebKitGTK development packages ([Tauri prerequisites](https://tauri.app/start/prerequisites/)).

```bash
cd cross-platform
npm install
npm test            # format and editor tests
npm run tauri dev   # run the desktop app
npm run dev         # or just the editor, in a browser at http://localhost:1420
npm run tauri build # installers in src-tauri/target/release/bundle
```

Release installers are built by GitHub Actions ([`windows-linux.yml`](.github/workflows/windows-linux.yml)): create the release, then run the workflow with the release tag and it attaches the `.exe`, `.AppImage` and `.deb`. Build the Mac `.dmg` with `Scripts/make-dmg.sh`.

### What the Windows and Linux app does

Paginated page view, fonts, sizes, bold/italic/underline/strikethrough, super- and subscript, text color and highlight, alignment, bulleted and numbered lists, named styles (Title, Headings, Quote, Code…), links, pictures (insert, paste, drag in, resize), tables (rows, columns, merging, header row), page breaks, Find & Replace, page setup, printing and PDF (through the system's print-to-PDF printer), word count and zoom. It opens and saves `.paper`, DOCX, RTF, HTML and plain text. It also shows update notifications and writing suggestions (see below).

Comments, tracked changes, footnotes and the other Mac-only features in a `.paper` file are shown as plain text and removed if the document is saved on Windows or Linux; the app says so when it opens such a file.

**Writing suggestions** use a local model through [Ollama](https://ollama.com): install Ollama, run `ollama pull llama3.2`, and suggestions appear while you write (Tab accepts, Ctrl+→ accepts one word, Esc dismisses). The app only connects to Ollama on the same computer, so your text never leaves it. Choose the model in Settings.

## Features

- **Real paginated editing.** One `NSLayoutManager` flows the text through one text container per page. Pages are added and removed as text flows, and page breaks move text to the next page.
- **Formatting.** Fonts, sizes, bold/italic/underline/strikethrough, text color, highlight, alignment, indentation, line and paragraph spacing, bulleted and numbered lists, named styles (Title, Headings, Quote…), links, superscript/subscript and clear formatting.
- **Inserts.** Images (scaled to fit the page), tables (Tab/Shift-Tab move between cells; Tab in the last cell adds a row; Format ▸ Table ▸ Table Properties for borders and merging), page breaks, horizontal lines and the date.
- **Ruler.** Left, right and first-line indents plus tab stops for the current paragraph. Zero sits at the left margin.
- **Writing suggestions.** After a short pause at the end of a paragraph, Apple's on-device language model (macOS 26+, Apple Intelligence) suggests how to continue the sentence in gray. Tab accepts, Option-Right Arrow accepts one word, Escape dismisses; typing the suggested letters keeps the rest. Text never leaves the Mac. Toggle in Settings ▸ Editing.
- **Update notifications.** At launch and once a day, the app checks the latest GitHub release and, if it is newer, shows its release notes with a Download button (Remind Me Later / Skip This Version). Wired Paper ▸ Check for Updates… checks on demand; turn automatic checks off in Settings ▸ General.
- **Find & Replace.** The native macOS find bar spans all pages, with incremental highlighting, case and whole-word options, Replace and Replace All.
- **Documents.** Built on NSDocument, which provides autosave, versions, crash recovery, Open Recent, the edited indicator, Duplicate/Rename/Move and Revert.
- **Formats.** `.paper` (native, default), `.wiredpaper` (native package), RTF, RTFD, DOCX, ODT, HTML and plain text for open and save; PDF export and printing match on-screen pagination.
- **Templates.** Blank, Letter, Report, Resume and Notes, in a chooser with live previews and a recent-documents list.
- **Chrome.** Toolbar, format bar, status bar (page, words, characters, zoom slider), light and dark mode (pages stay paper-white), and Settings.

## Architecture

```
WiredPaper/
  App/          Entry point, app delegate, document controller, main menu
  Document/     WiredPaperDocument (NSDocument), PageSetup, metadata & errors
  Persistence/  DocumentFormat, DocumentCodec protocol + registry, codecs, Export
  Editor/       EditorController, paginated views, formatting, lists, tables,
                inline AI completion (Completion/),
                attachments, statistics, print/PDF rendering, style catalog
  Find/         NSTextFinderClient spanning all page views
  Window/       Window controller, toolbar, view controller (menu actions), sheets
  UI/           SwiftUI format bar, status bar, color palettes, sheets, theme
  Templates/    Template model, content library, chooser window
  Settings/     AppSettings (UserDefaults) and the Settings window
WiredPaperTests/ Codec round-trips, lists, tables, pagination, PDF, statistics,
                cross-platform .paper compatibility
cross-platform/ Windows & Linux app (Tauri): src/ editor & formats, src-tauri/ Rust backend
Scripts/        generate-icon.swift (app icon), make-dmg.sh (release disk image)
```

### Key decisions

- **TextKit 1 with one container per page.** This is the architecture TextEdit uses for page layout. It gives exact page boundaries, and it is required for `NSTextTable` tables and `NSTextList` lists. All pages share selection, undo and typing attributes.
- **All edits go through `shouldChangeText` / `didChangeText`,** so every formatting command is undoable and named in Edit ▸ Undo.
- **Native format = `.paper`.** A `.paper` file is a single ZIP file (a `mimetype` entry, then `Document.json` and `Content.rtfd/…`), so it survives email, cloud drives and other operating systems. File ▸ Export… turns it into DOCX, PDF or any other supported format. The older `.wiredpaper` format stores the same contents as a package: a folder containing `Content.rtfd` (standard RTFD, readable without this app) and `Document.json`. The JSON holds page setup, named paragraph styles and a format version; it is decoded tolerantly so files move safely between app versions.
- **Pluggable codecs.** Every format implements `DocumentCodec`. DOCX currently uses AppKit's built-in converter, which handles text, basic formatting, lists and simple tables. A dedicated OOXML codec with higher fidelity (styles, headers and footers, footnotes, comments) can replace it by changing one line in `DocumentCodecRegistry`.
- **Printing and PDF** go through `PrintPagesView`, which paginates a copy of the text with the same page geometry used on screen.

## Known limitations / next steps

- Headers, footers, footnotes, section breaks, columns and tracked changes are not implemented.
- Headings don't yet "keep with next", so a heading can end up alone at the bottom of a page.
- DOCX fidelity is limited by AppKit's converter (see above).
- The app is not sandboxed. A Mac App Store build needs the App Sandbox entitlement plus security-scoped bookmarks for the recent-documents list.
