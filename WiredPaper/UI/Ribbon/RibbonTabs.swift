import AppKit
import SwiftUI

/// A compact labelled button that opens a menu.
struct RibbonCompactMenuButton: View {
    let title: String
    let symbol: String
    var editor: EditorController?
    let menu: () -> NSMenu

    @State private var hovering = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            anchor.pop(menu(), editor: editor)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
                Text(title).font(.system(size: 11.5)).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .padding(.horizontal, 5)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonButtonStyle(hovering: hovering))
        .background(MenuAnchorView(anchor: anchor))
        .onHover { hovering = $0 }
        .help(title)
    }
}

@MainActor
private func send(_ selector: Selector, _ editor: EditorController, _ represented: Any? = nil, tag: Int = 0) {
    RibbonCommand.send(selector, editor, represented: represented, tag: tag)
}

// MARK: - Insert

struct InsertTab: View {
    @ObservedObject var editor: EditorController
    @State private var showingTableGrid = false

    var body: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Blank Page", symbol: "doc", help: "Insert a blank page", action: editor.insertBlankPage)
                RibbonLargeButton(title: "Page Break", symbol: "rectangle.split.1x2", help: "Start the next page (⌘↩)") {
                    send(#selector(DocumentViewController.insertPageBreakAction(_:)), editor)
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Table", symbol: "tablecells", help: "Insert a table", menu: nil) { showingTableGrid = true }
                    .popover(isPresented: $showingTableGrid, arrowEdge: .bottom) {
                        TableGridPicker(onPick: { rows, columns in
                            showingTableGrid = false
                            editor.focusTextView()
                            editor.insertTable(rows: rows, columns: columns)
                        }, onMore: {
                            showingTableGrid = false
                            send(#selector(DocumentViewController.showInsertTableSheet(_:)), editor)
                        })
                    }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Pictures", symbol: "photo", help: "Insert pictures from a file") {
                    send(#selector(DocumentViewController.insertImageFromFile(_:)), editor)
                }
                RibbonLargeButton(title: "Shapes", symbol: "square.on.circle", editor: editor, menu: { RibbonCommand.mainMenu(["Insert", "Shape"]) })
                RibbonLargeButton(title: "Icons", symbol: "star.square", help: "Insert an icon") { send(#selector(DocumentViewController.insertIcon(_:)), editor) }
                RibbonLargeButton(title: "Diagram", symbol: "rectangle.3.group", help: "Insert a SmartArt-style diagram", editor: editor,
                                  menu: { RibbonCommand.mainMenu(["Insert", "Diagram"]) })
                RibbonLargeButton(title: "Chart", symbol: "chart.bar.xaxis", editor: editor, menu: { RibbonCommand.mainMenu(["Insert", "Chart"]) })
                RibbonLargeButton(title: "Spreadsheet", symbol: "tablecells.badge.ellipsis", help: "Insert a calculating spreadsheet") {
                    send(#selector(DocumentViewController.insertSpreadsheet(_:)), editor)
                }
            }
            RibbonGroup {
                RibbonColumn {
                    RibbonCompactButton(title: "Link", symbol: "link", help: "Insert a link (⌘K)") { send(#selector(DocumentViewController.showLinkSheet(_:)), editor) }
                    RibbonCompactButton(title: "Bookmark", symbol: "bookmark") { send(#selector(DocumentViewController.showBookmarkSheet(_:)), editor) }
                    RibbonCompactButton(title: "Cross-reference", symbol: "arrow.triangle.turn.up.right.diamond") {
                        send(#selector(DocumentViewController.showCrossReferenceSheet(_:)), editor)
                    }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Comment", symbol: "text.bubble", help: "New comment (⌥⌘A)") { send(#selector(DocumentViewController.newComment(_:)), editor) }
            }
            RibbonGroup {
                RibbonColumn {
                    RibbonCompactButton(title: "Header", symbol: "rectangle.topthird.inset.filled") { send(#selector(DocumentViewController.showHeaderFooterSheet(_:)), editor) }
                    RibbonCompactButton(title: "Footer", symbol: "rectangle.bottomthird.inset.filled") { send(#selector(DocumentViewController.showHeaderFooterSheet(_:)), editor) }
                    RibbonCompactMenuButton(title: "Page Number", symbol: "number", editor: editor) { RibbonCommand.mainMenu(["Layout", "Page Numbers"]) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Text Box", symbol: "character.textbox") { send(#selector(DocumentViewController.insertTextBox(_:)), editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Decorative Text", symbol: "textformat") { send(#selector(DocumentViewController.insertWordArt(_:)), editor) }
                    RibbonCompactMenuButton(title: "Field", symbol: "curlybraces", editor: editor) { RibbonCommand.mainMenu(["Insert", "Field"]) }
                    RibbonCompactButton(title: "Date & Time", symbol: "calendar") { send(#selector(DocumentViewController.insertCurrentDate(_:)), editor) }
                }
                RibbonColumn {
                    RibbonCompactButton(title: "Signature Line", symbol: "signature") { send(#selector(DocumentViewController.insertSignatureLine(_:)), editor) }
                    RibbonCompactMenuButton(title: "Form Control", symbol: "checkmark.square", editor: editor) { RibbonCommand.mainMenu(["Insert", "Form Control"]) }
                    RibbonCompactButton(title: "Horizontal Line", symbol: "minus") { send(#selector(DocumentViewController.insertHorizontalRule(_:)), editor) }
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Equation", symbol: "function", help: "Insert an equation (⌃⌥=)") { send(#selector(DocumentViewController.insertEquation(_:)), editor) }
                RibbonLargeButton(title: "Symbol", symbol: "character.cursor.ibeam", help: "Emoji & Symbols") {
                    editor.focusTextView()
                    NSApp.orderFrontCharacterPalette(nil)
                }
            }
        }
    }
}

// MARK: - Draw

struct DrawTab: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Drawing Canvas", symbol: "scribble.variable", help: "Draw with pen or highlighter") {
                    send(#selector(DocumentViewController.insertDrawing(_:)), editor)
                }
                RibbonLargeButton(title: "Edit Drawing", symbol: "pencil.tip.crop.circle", help: "Edit the selected drawing or object",
                                  isEnabled: editor.selectedObject != nil) {
                    send(#selector(DocumentViewController.editSelectedObject(_:)), editor)
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Shapes", symbol: "square.on.circle", editor: editor, menu: { RibbonCommand.mainMenu(["Insert", "Shape"]) })
                RibbonLargeButton(title: "Text Box", symbol: "character.textbox") { send(#selector(DocumentViewController.insertTextBox(_:)), editor) }
                RibbonLargeButton(title: "Decorative Text", symbol: "textformat") { send(#selector(DocumentViewController.insertWordArt(_:)), editor) }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Ink to Math", symbol: "function", help: "Write an equation") { send(#selector(DocumentViewController.insertEquation(_:)), editor) }
                RibbonLargeButton(title: "Signature", symbol: "signature", help: "Insert a signature line") {
                    send(#selector(DocumentViewController.insertSignatureLine(_:)), editor)
                }
            }
        }
    }
}

// MARK: - Design

struct DesignTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: WiredPaperDocument

    var body: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(DocumentTheme.presets) { theme in
                            ThemeCard(theme: theme, isCurrent: document.styleSheet.theme.id == theme.id) {
                                send(#selector(DocumentViewController.applyThemeFromMenu(_:)), editor, theme.id)
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(width: 420, height: 72)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
            }
            RibbonGroup {
                RibbonLargeButton(title: "Paragraph Spacing", symbol: "text.line.first.and.arrowtriangle.forward", editor: editor, menu: {
                    let menu = NSMenu()
                    for preset in EditorController.SpacingPreset.allCases {
                        menu.add(preset.displayName) { editor.applySpacingPreset(preset) }
                    }
                    menu.addItem(.separator())
                    menu.add("Custom Paragraph Spacing…") { send(#selector(DocumentViewController.showStylesManager(_:)), editor) }
                    return menu
                })
                RibbonLargeButton(title: "Styles", symbol: "textformat.alt", help: "Edit and create styles") {
                    send(#selector(DocumentViewController.showStylesManager(_:)), editor)
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Watermark", symbol: "drop", help: "Add a watermark") { send(#selector(DocumentViewController.showWatermarkSheet(_:)), editor) }
                RibbonLargeButton(title: "Page Color", symbol: "paintbrush", editor: editor, menu: { RibbonCommand.mainMenu(["Layout", "Page Color"]) })
                RibbonLargeButton(title: "Page Borders", symbol: "square.dashed", help: "Add a border around pages") {
                    send(#selector(DocumentViewController.showPageBorderSheet(_:)), editor)
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: DocumentTheme
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Title").font(.custom(theme.headingFont, size: 15).weight(.semibold))
                    .foregroundStyle(Color(nsColor: NSColor(hex: theme.headingColorHex) ?? .black))
                Text("Body text").font(.custom(theme.bodyFont, size: 10))
                    .foregroundStyle(Color(nsColor: NSColor(hex: theme.textColorHex) ?? .black))
                HStack(spacing: 2) {
                    ForEach([theme.headingColorHex, theme.accentColorHex, theme.secondaryColorHex], id: \.self) { hex in
                        Rectangle().fill(Color(nsColor: NSColor(hex: hex) ?? .gray)).frame(width: 14, height: 5)
                    }
                }
                Text(theme.name).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(width: 76, height: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isCurrent ? Theme.accentColor : (hovering ? Color.primary.opacity(0.35) : Color.primary.opacity(0.1)),
                                                                 lineWidth: isCurrent ? 2 : 1))
            .environment(\.colorScheme, .light)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(theme.name): \(theme.headingFont) / \(theme.bodyFont)")
    }
}

// MARK: - Layout

struct LayoutTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: WiredPaperDocument

    var body: some View {
        let paragraph = editor.currentParagraphSettings()
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Margins", symbol: "rectangle.inset.filled", editor: editor, menu: { RibbonCommand.mainMenu(["Layout", "Margins"]) })
                RibbonLargeButton(title: "Orientation", symbol: "rectangle.portrait.rotate", editor: editor, menu: { RibbonCommand.mainMenu(["Layout", "Orientation"]) })
                RibbonLargeButton(title: "Size", symbol: "doc.plaintext", editor: editor, menu: { RibbonCommand.mainMenu(["Layout", "Size"]) })
                RibbonLargeButton(title: "Columns", symbol: "rectangle.split.3x1", editor: editor, menu: { RibbonCommand.mainMenu(["Layout", "Columns"]) })
                RibbonColumn {
                    RibbonCompactMenuButton(title: "Breaks", symbol: "rectangle.split.1x2", editor: editor) { RibbonCommand.mainMenu(["Layout", "Breaks"]) }
                    RibbonCompactMenuButton(title: "Line Numbers", symbol: "list.number", editor: editor) { RibbonCommand.mainMenu(["Layout", "Line Numbers"]) }
                    RibbonCompactButton(title: "Hyphenation", symbol: "textformat.characters.dottedunderline",
                                        isOn: document.metadata.decoration.hyphenation) {
                        send(#selector(DocumentViewController.toggleHyphenation(_:)), editor)
                    }
                }
            }
            RibbonGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Indent").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
                    RibbonMeasureField(title: "Left", symbol: "arrow.right.to.line", value: paragraph.leftIndent, step: 9) {
                        editor.setParagraphMetric(\.leftIndent, $0)
                    }
                    RibbonMeasureField(title: "Right", symbol: "arrow.left.to.line", value: paragraph.rightIndent, step: 9) {
                        editor.setParagraphMetric(\.rightIndent, $0)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spacing").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).fixedSize()
                    RibbonMeasureField(title: "Before", symbol: "arrow.up.to.line", value: paragraph.spacingBefore, step: 6) {
                        editor.setParagraphMetric(\.spacingBefore, $0)
                    }
                    RibbonMeasureField(title: "After", symbol: "arrow.down.to.line", value: paragraph.spacingAfter, step: 6) {
                        editor.setParagraphMetric(\.spacingAfter, $0)
                    }
                }
            }
            RibbonGroup {
                RibbonColumn {
                    RibbonCompactMenuButton(title: "Vertical Alignment", symbol: "align.vertical.center", editor: editor) {
                        RibbonCommand.mainMenu(["Layout", "Vertical Alignment"])
                    }
                    RibbonCompactButton(title: "Widow/Orphan Control", symbol: "text.append", isOn: document.metadata.decoration.widowControl) {
                        send(#selector(DocumentViewController.toggleWidowControl(_:)), editor)
                    }
                    RibbonCompactButton(title: "Page Setup…", symbol: "doc.badge.gearshape") { send(#selector(DocumentViewController.showDocumentSetup(_:)), editor) }
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Picture", symbol: "photo.on.rectangle", help: "Rotate, flip, crop and format the selected picture",
                                  editor: editor, menu: { RibbonCommand.mainMenu(["Format", "Picture"]) })
                RibbonLargeButton(title: "Edit Object", symbol: "slider.horizontal.below.rectangle", help: "Edit the selected chart, equation, shape or diagram",
                                  isEnabled: editor.selectedObject != nil || editor.selectedImage != nil) {
                    send(#selector(DocumentViewController.editSelectedObject(_:)), editor)
                }
            }
        }
    }
}

// MARK: - References

struct ReferencesTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Table of Contents", symbol: "list.bullet.rectangle", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Insert Table of Contents") { send(#selector(DocumentViewController.insertTableOfContents(_:)), editor) }
                    menu.add("Update Table") { send(#selector(DocumentViewController.updateTableOfContents(_:)), editor) }
                    return menu
                }) {
                    send(#selector(DocumentViewController.insertTableOfContents(_:)), editor)
                }
                RibbonColumn {
                    RibbonCompactMenuButton(title: "Add Text", symbol: "text.badge.plus", editor: editor) {
                        let menu = NSMenu()
                        menu.add("Do Not Show in Table of Contents") { editor.applyStyle(id: "normal") }
                        for level in 1...3 {
                            menu.add("Level \(level)") { editor.applyStyle(id: "heading\(level)") }
                        }
                        return menu
                    }
                    RibbonCompactButton(title: "Update Table", symbol: "arrow.clockwise") { send(#selector(DocumentViewController.updateTableOfContents(_:)), editor) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Insert Footnote", symbol: "note.text.badge.plus", help: "⌥⇧⌘F") { send(#selector(DocumentViewController.insertFootnote(_:)), editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Insert Endnote", symbol: "text.append") { send(#selector(DocumentViewController.insertEndnote(_:)), editor) }
                    RibbonCompactButton(title: "Show Notes", symbol: "note.text", isOn: sidebar.right == .notes) { sidebar.toggleRight(.notes) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Insert Citation", symbol: "quote.opening", help: "Cite a source") { sidebar.right = .references }
                RibbonColumn {
                    RibbonCompactButton(title: "Manage Sources", symbol: "books.vertical", isOn: sidebar.right == .references) { sidebar.toggleRight(.references) }
                    RibbonCompactMenuButton(title: "Style: \(editor.citationStyle.displayName)", symbol: "textformat.abc", editor: editor) {
                        RibbonCommand.mainMenu(["References", "Citation Style"])
                    }
                    RibbonCompactButton(title: "Bibliography", symbol: "text.book.closed") { send(#selector(DocumentViewController.insertBibliography(_:)), editor) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Insert Caption", symbol: "text.below.photo") { send(#selector(DocumentViewController.showCaptionSheet(_:)), editor) }
                RibbonColumn {
                    RibbonCompactMenuButton(title: "Table of Figures", symbol: "photo.stack", editor: editor) { RibbonCommand.mainMenu(["References", "Table of Figures"]) }
                    RibbonCompactButton(title: "Cross-reference", symbol: "arrow.triangle.turn.up.right.diamond") {
                        send(#selector(DocumentViewController.showCrossReferenceSheet(_:)), editor)
                    }
                    RibbonCompactButton(title: "Bookmark", symbol: "bookmark") { send(#selector(DocumentViewController.showBookmarkSheet(_:)), editor) }
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Mark Entry", symbol: "tag", help: "Mark an index entry (⌥⇧⌘X)") { send(#selector(DocumentViewController.showMarkIndexEntry(_:)), editor) }
                RibbonLargeButton(title: "Insert Index", symbol: "list.bullet.below.rectangle") { send(#selector(DocumentViewController.insertIndex(_:)), editor) }
            }
        }
    }
}

// MARK: - Mailings

struct MailingsTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: WiredPaperDocument

    var body: some View {
        let data = document.metadata.mailMerge ?? MailMergeData()
        let hasRecipients = !data.isEmpty
        let previewing = editor.mergePreviewIndex != nil
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Envelopes", symbol: "envelope") { send(#selector(DocumentViewController.showEnvelopes(_:)), editor) }
                RibbonLargeButton(title: "Labels", symbol: "tag.square") { send(#selector(DocumentViewController.showLabels(_:)), editor) }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Start Mail Merge", symbol: "doc.on.doc", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Letters", symbol: "doc.text") { editor.previewMergeRecord(nil) }
                    menu.add("Envelopes…", symbol: "envelope") { send(#selector(DocumentViewController.showEnvelopes(_:)), editor) }
                    menu.add("Labels…", symbol: "tag.square") { send(#selector(DocumentViewController.showLabels(_:)), editor) }
                    menu.addItem(.separator())
                    menu.add("Normal Document", enabled: hasRecipients) { send(#selector(DocumentViewController.clearMailMerge(_:)), editor) }
                    return menu
                })
                RibbonLargeButton(title: "Select Recipients", symbol: "person.2", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Use an Existing List…", symbol: "doc.badge.arrow.up") { send(#selector(DocumentViewController.selectRecipientsFromFile(_:)), editor) }
                    menu.add("Type a New List…", symbol: "square.and.pencil") { send(#selector(DocumentViewController.editRecipients(_:)), editor) }
                    return menu
                })
                RibbonLargeButton(title: "Edit Recipient List", symbol: "person.crop.rectangle.stack", isEnabled: hasRecipients) {
                    send(#selector(DocumentViewController.editRecipients(_:)), editor)
                }
            }
            RibbonGroup {
                RibbonColumn {
                    RibbonCompactButton(title: "Address Block", symbol: "person.text.rectangle", isEnabled: hasRecipients, action: editor.insertAddressBlock)
                    RibbonCompactButton(title: "Greeting Line", symbol: "hand.wave", isEnabled: hasRecipients, action: editor.insertGreetingLine)
                    RibbonCompactMenuButton(title: "Insert Merge Field", symbol: "curlybraces.square", editor: editor) {
                        let menu = NSMenu()
                        if data.headers.isEmpty {
                            menu.add("Select recipients first", enabled: false) {}
                        }
                        for header in data.headers { menu.add(header) { editor.insertMergeField(header) } }
                        return menu
                    }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Preview Results", symbol: "eye", isOn: previewing, isEnabled: hasRecipients && !data.records.isEmpty) {
                    editor.previewMergeRecord(previewing ? nil : 0)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        RibbonIconButton(symbol: "backward.end", help: "First Record", isEnabled: previewing) { editor.previewMergeRecord(0) }
                        RibbonIconButton(symbol: "chevron.left", help: "Previous Record", isEnabled: previewing) { editor.previewMergeRecord((editor.mergePreviewIndex ?? 0) - 1) }
                        Text(previewing ? "\((editor.mergePreviewIndex ?? 0) + 1) of \(data.records.count)" : "—")
                            .font(.system(size: 11.5).monospacedDigit())
                            .frame(minWidth: 54)
                        RibbonIconButton(symbol: "chevron.right", help: "Next Record", isEnabled: previewing) { editor.previewMergeRecord((editor.mergePreviewIndex ?? 0) + 1) }
                        RibbonIconButton(symbol: "forward.end", help: "Last Record", isEnabled: previewing) { editor.previewMergeRecord(data.records.count - 1) }
                    }
                    Text(hasRecipients ? "\(data.includedIndices.count) recipients · \(data.sourceName)" : "No recipients")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).frame(width: 190)
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Finish & Merge", symbol: "checkmark.rectangle.stack", isEnabled: hasRecipients, editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Edit Individual Documents…", symbol: "doc.on.doc") { send(#selector(DocumentViewController.finishMergeEditDocuments(_:)), editor) }
                    menu.add("Print Documents…", symbol: "printer") { send(#selector(DocumentViewController.finishMergePrint(_:)), editor) }
                    menu.add("Save as PDF…", symbol: "doc.richtext") { send(#selector(DocumentViewController.finishMergePDF(_:)), editor) }
                    return menu
                })
            }
        }
    }
}

// MARK: - Review

struct ReviewTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @ObservedObject var document: WiredPaperDocument

    var body: some View {
        let tracking = editor.isTrackingChanges
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Editor", symbol: "pencil.and.scribble", isOn: sidebar.right == .editor) { sidebar.toggleRight(.editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Spelling & Grammar", symbol: "textformat.abc.dottedunderline") { send(#selector(NSText.showGuessPanel(_:)), editor) }
                    RibbonCompactButton(title: "Word Count", symbol: "number") { send(#selector(DocumentViewController.showWordCount(_:)), editor) }
                    RibbonCompactButton(title: "Look Up", symbol: "character.book.closed") { send(#selector(DocumentViewController.lookUpSelection(_:)), editor) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Check Accessibility", symbol: "accessibility") { send(#selector(DocumentViewController.checkAccessibility(_:)), editor) }
                RibbonLargeButton(title: "Read Aloud", symbol: "speaker.wave.2", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Start Speaking", symbol: "play") { send(#selector(NSTextView.startSpeaking(_:)), editor) }
                    menu.add("Stop Speaking", symbol: "stop") { send(#selector(NSTextView.stopSpeaking(_:)), editor) }
                    return menu
                }) {
                    send(#selector(NSTextView.startSpeaking(_:)), editor)
                }
                RibbonLargeButton(title: "Language", symbol: "globe", editor: editor, menu: languageMenu)
            }
            RibbonGroup {
                RibbonLargeButton(title: "New Comment", symbol: "text.bubble") { send(#selector(DocumentViewController.newComment(_:)), editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Delete", symbol: "trash", isEnabled: editor.activeCommentID != nil) {
                        send(#selector(DocumentViewController.deleteCurrentComment(_:)), editor)
                    }
                    RibbonCompactButton(title: "Previous", symbol: "chevron.up") { send(#selector(DocumentViewController.previousComment(_:)), editor) }
                    RibbonCompactButton(title: "Next", symbol: "chevron.down") { send(#selector(DocumentViewController.nextComment(_:)), editor) }
                }
                RibbonLargeButton(title: "Show Comments", symbol: "bubble.left.and.bubble.right", isOn: sidebar.right == .comments) {
                    sidebar.toggleRight(.comments)
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Track Changes", symbol: "pencil.line", help: "Track Changes (⇧⌘E)", isOn: tracking) {
                    send(#selector(DocumentViewController.toggleTrackChanges(_:)), editor)
                }
                RibbonColumn {
                    RibbonCompactMenuButton(title: editor.markupMode.displayName, symbol: "eye", editor: editor) { RibbonCommand.mainMenu(["Review", "Markup"]) }
                    RibbonCompactButton(title: "Reviewing Pane", symbol: "sidebar.right", isOn: sidebar.right == .review) { sidebar.toggleRight(.review) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Accept", symbol: "checkmark.circle", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Accept This Change") { send(#selector(DocumentViewController.acceptChange(_:)), editor) }
                    menu.add("Accept All Changes") { send(#selector(DocumentViewController.acceptAllChanges(_:)), editor) }
                    return menu
                }) { send(#selector(DocumentViewController.acceptChange(_:)), editor) }
                RibbonLargeButton(title: "Reject", symbol: "xmark.circle", editor: editor, menu: {
                    let menu = NSMenu()
                    menu.add("Reject This Change") { send(#selector(DocumentViewController.rejectChange(_:)), editor) }
                    menu.add("Reject All Changes") { send(#selector(DocumentViewController.rejectAllChanges(_:)), editor) }
                    return menu
                }) { send(#selector(DocumentViewController.rejectChange(_:)), editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Previous", symbol: "arrow.up") { send(#selector(DocumentViewController.previousChange(_:)), editor) }
                    RibbonCompactButton(title: "Next", symbol: "arrow.down") { send(#selector(DocumentViewController.nextChange(_:)), editor) }
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Restrict Editing", symbol: "lock.doc") { send(#selector(DocumentViewController.showRestrictEditing(_:)), editor) }
                RibbonColumn {
                    RibbonCompactButton(title: "Mark as Final", symbol: "checkmark.seal", isOn: document.metadata.protection.markedFinal) {
                        send(#selector(DocumentViewController.markAsFinal(_:)), editor)
                    }
                    RibbonCompactButton(title: "Stop Protection", symbol: "lock.open", isEnabled: document.metadata.protection.restriction != EditingRestriction.none) {
                        send(#selector(DocumentViewController.stopProtection(_:)), editor)
                    }
                }
            }
        }
    }

    private func languageMenu() -> NSMenu {
        let menu = NSMenu()
        let checker = NSSpellChecker.shared
        menu.add("Automatic", checked: checker.automaticallyIdentifiesLanguages) { editor.setSpellingLanguage(nil) }
        menu.addItem(.separator())
        let current = checker.automaticallyIdentifiesLanguages ? nil : checker.language()
        let names = editor.spellingLanguages.map { code in
            (code, Locale.current.localizedString(forIdentifier: code) ?? code)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        for (code, name) in names {
            menu.add(name, checked: current == code) { editor.setSpellingLanguage(code) }
        }
        return menu
    }
}

// MARK: - View

struct ViewTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @ObservedObject var settings = AppSettings.shared
    let isFocusMode: Bool

    var body: some View {
        HStack(spacing: 0) {
            RibbonGroup {
                RibbonLargeButton(title: "Print Layout", symbol: "doc.text", help: "Pages as they print", isOn: true) {}
                RibbonLargeButton(title: "Focus", symbol: "viewfinder", help: "Hide everything but the page", isOn: isFocusMode) {
                    send(#selector(DocumentViewController.toggleFocusMode(_:)), editor)
                }
            }
            RibbonGroup {
                RibbonColumn {
                    RibbonCompactButton(title: "Ruler", symbol: "ruler", isOn: settings.showRuler) {
                        send(#selector(DocumentViewController.toggleRulerVisibility(_:)), editor)
                    }
                    RibbonCompactButton(title: "Navigation Pane", symbol: "sidebar.left", isOn: sidebar.left == .navigation) {
                        send(#selector(DocumentViewController.toggleNavigationPane(_:)), editor)
                    }
                    RibbonCompactButton(title: "Formatting Marks", symbol: "paragraphsign", isOn: editor.showsFormattingMarks, action: editor.toggleFormattingMarks)
                }
                RibbonColumn {
                    RibbonCompactButton(title: "Status Bar", symbol: "rectangle.bottomthird.inset.filled", isOn: settings.showStatusBar) {
                        send(#selector(DocumentViewController.toggleStatusBar(_:)), editor)
                    }
                    RibbonCompactButton(title: "Hidden Text", symbol: "eye.slash", isOn: editor.showsHiddenText) {
                        send(#selector(DocumentViewController.toggleShowHiddenText(_:)), editor)
                    }
                    RibbonCompactButton(title: "Notes", symbol: "note.text", isOn: sidebar.right == .notes) { sidebar.toggleRight(.notes) }
                }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Zoom", symbol: "plus.magnifyingglass", editor: editor, menu: {
                    let menu = NSMenu()
                    for preset: CGFloat in [0.5, 0.75, 1, 1.25, 1.5, 2, 3] {
                        menu.add("\(Int(preset * 100))%", checked: abs(editor.zoom - preset) < 0.001) { editor.setZoom(preset) }
                    }
                    return menu
                })
                RibbonLargeButton(title: "100%", symbol: "1.magnifyingglass", help: "Actual size (⌘0)") { editor.setZoom(1) }
                RibbonColumn {
                    RibbonCompactButton(title: "One Page", symbol: "doc", isOn: editor.pagesPerRow == 1) { editor.setPagesPerRow(1) }
                    RibbonCompactButton(title: "Multiple Pages", symbol: "doc.on.doc", isOn: editor.pagesPerRow > 1) { editor.setPagesPerRow(2) }
                    RibbonCompactButton(title: "Page Width", symbol: "arrow.left.and.right") { editor.zoomToPageWidth() }
                }
            }
            RibbonGroup(showsDivider: false) {
                RibbonLargeButton(title: "Arrange All", symbol: "rectangle.3.group", help: "Bring all document windows to the front") {
                    NSApp.arrangeInFront(nil)
                }
                RibbonLargeButton(title: "Switch Windows", symbol: "macwindow.on.rectangle", editor: editor, menu: {
                    let menu = NSMenu()
                    for document in NSDocumentController.shared.documents {
                        menu.add(document.displayName, checked: document === editor.document) {
                            document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
                        }
                    }
                    return menu
                })
            }
        }
    }
}
