# Wired Paper

A native macOS word processor with a familiar document workflow, written in Swift with AppKit/TextKit for the editor and SwiftUI for the surrounding interface. No third-party dependencies.

## Building

Open `WiredPaper.xcodeproj` in Xcode (26 or later) and run the **WiredPaper** scheme. It requires macOS 14 or later.

From the command line:

```bash
xcodebuild -project WiredPaper.xcodeproj -scheme WiredPaper build
xcodebuild -project WiredPaper.xcodeproj -scheme WiredPaper test
```

The project uses file-system-synchronized groups, so new source files placed under `WiredPaper/` are picked up automatically.

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
WiredPaperTests/ Codec round-trips, lists, tables, pagination, PDF, statistics
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
