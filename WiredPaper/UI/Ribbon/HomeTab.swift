import AppKit
import SwiftUI

/// Home: clipboard, font, paragraph, styles, dictation, sensitivity, add-ins, Editor.
struct HomeTab: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    /// Ribbon width; the styles gallery grows and shrinks with it, like Word's.
    var availableWidth: CGFloat = 1600
    @State private var lastBorder = EditorController.BorderPreset.bottom
    @State private var lastShading = ColorPalettes.hex(0xD9D9D9)
    @State private var lastUnderline = EditorController.UnderlineKind.single
    @State private var showingAddIns = false

    private var state: FormattingState { editor.formatting }

    var body: some View {
        HStack(spacing: 0) {
            clipboard
            font
            paragraph
            RibbonGroup {
                StyleGallery(editor: editor, width: min(max(availableWidth - 1210, 170), 700))
                RibbonLargeButton(title: "Styles Pane", symbol: "sidebar.squares.right", help: "Show all styles",
                                  isOn: sidebar.right == .styles) { sidebar.toggleRight(.styles) }
            }
            RibbonGroup {
                RibbonLargeButton(title: "Dictate", symbol: "mic", help: "Dictate (uses macOS Dictation)") {
                    editor.focusTextView()
                    NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
                }
                RibbonLargeButton(title: "Sensitivity", symbol: "lock.shield", help: "Classify this document",
                                  tint: editor.sensitivity == .none ? nil : Color(nsColor: editor.sensitivity.color),
                                  editor: editor, menu: sensitivityMenu)
                RibbonLargeButton(title: "Add-ins", symbol: "puzzlepiece.extension", help: "Add-ins") { showingAddIns = true }
                    .popover(isPresented: $showingAddIns, arrowEdge: .bottom) { AddInsPopover() }
                RibbonLargeButton(title: "Editor", symbol: "pencil.and.scribble", help: "Spelling, grammar and readability",
                                  isOn: sidebar.right == .editor) { sidebar.toggleRight(.editor) }
            }
        }
    }

    // MARK: Clipboard

    private var clipboard: some View {
        RibbonGroup {
            RibbonLargeButton(title: "Paste", symbol: "doc.on.clipboard", help: "Paste (⌘V)", editor: editor, menu: {
                let menu = NSMenu()
                menu.add("Keep Source Formatting", symbol: "doc.richtext") { RibbonCommand.send(#selector(NSText.paste(_:)), editor) }
                menu.add("Keep Text Only", symbol: "doc.plaintext") { RibbonCommand.send(#selector(NSTextView.pasteAsPlainText(_:)), editor) }
                menu.addItem(.separator())
                menu.add("Paste Style", symbol: "paintbrush") { RibbonCommand.send(#selector(NSTextView.pasteFont(_:)), editor) }
                return menu
            }) {
                RibbonCommand.send(#selector(NSText.paste(_:)), editor)
            }
            RibbonColumn {
                RibbonCompactButton(title: "Cut", symbol: "scissors", help: "Cut (⌘X)") { RibbonCommand.send(#selector(NSText.cut(_:)), editor) }
                RibbonCompactButton(title: "Copy", symbol: "doc.on.doc", help: "Copy (⌘C)") { RibbonCommand.send(#selector(NSText.copy(_:)), editor) }
                RibbonCompactButton(title: "Format Painter", symbol: "paintbrush.pointed", help: "Copy formatting to other text",
                                    isOn: editor.isFormatPainterActive) {
                    RibbonCommand.send(#selector(DocumentViewController.toggleFormatPainter(_:)), editor)
                }
            }
        }
    }

    // MARK: Font

    private var font: some View {
        RibbonGroup {
            RibbonRows {
                FontFamilyPicker(family: state.fontFamily, onSelect: editor.setFontFamily)
                    .frame(width: 150)
                FontSizeField(size: state.fontSize, onCommit: editor.setFontSize)
                    .frame(width: 56)
                RibbonIconButton(symbol: "textformat.size.larger", help: "Increase Font Size (⌘>)") { editor.adjustFontSize(larger: true) }
                RibbonIconButton(symbol: "textformat.size.smaller", help: "Decrease Font Size (⌘<)") { editor.adjustFontSize(larger: false) }
                RibbonMenuButton(symbol: "textformat", help: "Change Case", editor: editor) {
                    RibbonCommand.mainMenu(["Format", "Font", "Change Case"])
                }
                RibbonIconButton(symbol: "eraser", help: "Clear All Formatting", action: editor.clearFormatting)
            } bottom: {
                RibbonIconButton(symbol: "bold", help: "Bold (⌘B)", isOn: state.isBold, action: editor.toggleBold)
                RibbonIconButton(symbol: "italic", help: "Italic (⌘I)", isOn: state.isItalic, action: editor.toggleItalic)
                RibbonSplitButton(symbol: "underline", help: "Underline (⌘U)", isOn: state.isUnderlined, editor: editor, action: {
                    if state.isUnderlined { editor.setUnderline(nil) } else { editor.setUnderline(lastUnderline) }
                }, menu: underlineMenu)
                RibbonIconButton(symbol: "strikethrough", help: "Strikethrough (⇧⌘X)", isOn: state.isStruckThrough, action: editor.toggleStrikethrough)
                RibbonIconButton(symbol: "textformat.subscript", help: "Subscript (⌃⌘=)", isOn: state.isSubscript, action: editor.toggleSubscript)
                RibbonIconButton(symbol: "textformat.superscript", help: "Superscript (⇧⌘=)", isOn: state.isSuperscript, action: editor.toggleSuperscript)
                RibbonMenuButton(symbol: "a.circle", help: "Text Effects and Typography", editor: editor, menu: textEffectsMenu)
                ColorSplitButton(symbol: "highlighter", help: "Text Highlight Color", color: editor.lastHighlightColor, kind: .highlight,
                                 onApply: editor.setHighlight, onMore: { HighlightColorRelay.shared.begin(for: editor) })
                ColorSplitButton(symbol: "character", help: "Font Color", color: editor.lastTextColor, kind: .text,
                                 onApply: editor.setTextColor, onMore: { HighlightColorRelay.beginTextColor(for: editor) })
            }
        }
    }

    private func underlineMenu() -> NSMenu {
        let menu = NSMenu()
        for kind in EditorController.UnderlineKind.allCases {
            menu.add(kind.displayName, checked: false) {
                lastUnderline = kind
                editor.setUnderline(kind)
            }
        }
        menu.add("No Underline") { editor.setUnderline(nil) }
        menu.addItem(.separator())
        let colors = NSMenu(title: "Underline Color")
        colors.add("Automatic") { editor.setUnderlineColor(nil) }
        colors.addItem(.separator())
        for swatch in ColorPalettes.namedTextColors {
            let item = colors.add(swatch.name) { editor.setUnderlineColor(swatch.color) }
            item.image = Self.swatch(swatch.color)
        }
        menu.addSubmenu(colors)
        return menu
    }

    private func textEffectsMenu() -> NSMenu {
        let menu = RibbonCommand.mainMenu(["Format", "Font", "Text Effects"])
        menu.addItem(.separator())
        menu.add("Small Caps", checked: state.isSmallCaps) { RibbonCommand.send(#selector(DocumentViewController.toggleSmallCaps(_:)), editor) }
        menu.add("All Caps", checked: state.isAllCaps) { RibbonCommand.send(#selector(DocumentViewController.toggleAllCaps(_:)), editor) }
        menu.add("Hidden", checked: state.isHidden) { RibbonCommand.send(#selector(DocumentViewController.toggleHiddenText(_:)), editor) }
        menu.addItem(.separator())
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Font", "Character Spacing"]), title: "Character Spacing")
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Font", "Kerning"]), title: "Kerning")
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Font", "Ligatures"]), title: "Ligatures")
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Font", "Baseline"]), title: "Baseline")
        menu.addItem(.separator())
        menu.add("Font Panel…", symbol: "textformat.alt") {
            editor.focusTextView()
            NSFontManager.shared.orderFrontFontPanel(nil)
        }
        return menu
    }

    // MARK: Paragraph

    private var paragraph: some View {
        RibbonGroup {
            RibbonRows {
                RibbonSplitButton(symbol: "list.bullet", help: "Bullets (⇧⌘L)", isOn: state.listKind == .bullet, editor: editor,
                                  action: { editor.toggleList(.bullet) },
                                  menu: { RibbonCommand.mainMenu(["Format", "Lists", "Bullet Style"]) })
                RibbonSplitButton(symbol: "list.number", help: "Numbering (⌥⌘L)", isOn: state.listKind == .numbered, editor: editor,
                                  action: { editor.toggleList(.numbered) },
                                  menu: { RibbonCommand.mainMenu(["Format", "Lists", "Numbering Style"]) })
                RibbonMenuButton(symbol: "list.bullet.indent", help: "Multilevel List", editor: editor, menu: multilevelMenu)
                RibbonIconButton(symbol: "decrease.indent", help: "Decrease Indent (⌘[)") {
                    if state.listKind != nil { RibbonCommand.send(#selector(DocumentViewController.decreaseListLevel(_:)), editor) } else { editor.changeIndent(by: -36) }
                }
                RibbonIconButton(symbol: "increase.indent", help: "Increase Indent (⌘])") {
                    if state.listKind != nil { RibbonCommand.send(#selector(DocumentViewController.increaseListLevel(_:)), editor) } else { editor.changeIndent(by: 36) }
                }
                RibbonMenuButton(symbol: "arrow.up.arrow.down", help: "Sort", editor: editor) {
                    let menu = NSMenu()
                    menu.add("Sort Paragraphs A → Z", symbol: "arrow.up") { editor.sortParagraphs(ascending: true) }
                    menu.add("Sort Paragraphs Z → A", symbol: "arrow.down") { editor.sortParagraphs(ascending: false) }
                    if editor.isInTable {
                        menu.addItem(.separator())
                        menu.add("Sort Table Ascending") { editor.sortTable(ascending: true) }
                        menu.add("Sort Table Descending") { editor.sortTable(ascending: false) }
                    }
                    return menu
                }
                RibbonIconButton(symbol: "paragraphsign", help: "Show/Hide Formatting Marks (⌘8)", isOn: editor.showsFormattingMarks,
                                 action: editor.toggleFormattingMarks)
            } bottom: {
                RibbonIconButton(symbol: "text.alignleft", help: "Align Left (⌘{)", isOn: state.effectiveAlignment == .left) { editor.setAlignment(.left) }
                RibbonIconButton(symbol: "text.aligncenter", help: "Center (⌘|)", isOn: state.effectiveAlignment == .center) { editor.setAlignment(.center) }
                RibbonIconButton(symbol: "text.alignright", help: "Align Right (⌘})", isOn: state.effectiveAlignment == .right) { editor.setAlignment(.right) }
                RibbonIconButton(symbol: "text.justify", help: "Justify", isOn: state.effectiveAlignment == .justified) { editor.setAlignment(.justified) }
                RibbonMenuButton(symbol: "arrow.up.and.down.text.horizontal", help: "Line and Paragraph Spacing", editor: editor, menu: spacingMenu)
                RibbonSplitButton(symbol: "drop.halffull", help: "Shading", editor: editor, action: {
                    editor.setParagraphShading(lastShading)
                }, menu: shadingMenu)
                RibbonSplitButton(symbol: lastBorder.symbol, help: lastBorder.displayName, editor: editor, action: {
                    editor.applyBorderPreset(lastBorder)
                }, menu: bordersMenu)
            }
        }
    }

    private func multilevelMenu() -> NSMenu {
        let menu = NSMenu()
        menu.add("Increase List Level", symbol: "increase.indent") { RibbonCommand.send(#selector(DocumentViewController.increaseListLevel(_:)), editor) }
        menu.add("Decrease List Level", symbol: "decrease.indent") { RibbonCommand.send(#selector(DocumentViewController.decreaseListLevel(_:)), editor) }
        menu.addItem(.separator())
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Lists", "Bullet Style"]), title: "Bullet Style")
        menu.addSubmenu(RibbonCommand.mainMenu(["Format", "Lists", "Numbering Style"]), title: "Numbering Style")
        menu.addItem(.separator())
        let isList = state.listKind != nil
        menu.add("Restart Numbering", enabled: isList) { RibbonCommand.send(#selector(DocumentViewController.restartNumbering(_:)), editor) }
        menu.add("Continue Numbering", enabled: isList) { RibbonCommand.send(#selector(DocumentViewController.continueNumbering(_:)), editor) }
        menu.add("Set Numbering Value…", enabled: isList) { RibbonCommand.send(#selector(DocumentViewController.setNumberingValue(_:)), editor) }
        return menu
    }

    private func spacingMenu() -> NSMenu {
        let menu = NSMenu()
        for option in LineSpacingOption.all {
            menu.add(option.title, checked: abs(state.lineHeightMultiple - option.multiple) < 0.01) { editor.setLineSpacing(option.multiple) }
        }
        menu.addItem(.separator())
        let settings = editor.currentParagraphSettings()
        if settings.spacingBefore > 0 {
            menu.add("Remove Space Before Paragraph") { editor.adjustParagraphSpacing(before: true, add: false) }
        } else {
            menu.add("Add Space Before Paragraph") { editor.adjustParagraphSpacing(before: true, add: true) }
        }
        if settings.spacingAfter > 0 {
            menu.add("Remove Space After Paragraph") { editor.adjustParagraphSpacing(before: false, add: false) }
        } else {
            menu.add("Add Space After Paragraph") { editor.adjustParagraphSpacing(before: false, add: true) }
        }
        menu.addItem(.separator())
        menu.add("Line Spacing Options…") { RibbonCommand.send(#selector(DocumentViewController.showParagraphOptions(_:)), editor) }
        return menu
    }

    private func shadingMenu() -> NSMenu {
        let menu = NSMenu()
        menu.add("No Color") { editor.setParagraphShading(nil) }
        menu.addItem(.separator())
        let shades: [(String, UInt32)] = [("Light Gray", 0xD9D9D9), ("Gray", 0xBFBFBF), ("Yellow", 0xFFF4C2), ("Green", 0xDDF2DA),
                                           ("Teal", 0xD7ECEF), ("Blue", 0xDCE8FA), ("Rose", 0xF8DDE1), ("Lavender", 0xE9E3F7)]
        for (name, hex) in shades {
            let color = ColorPalettes.hex(hex)
            let item = menu.add(name) {
                lastShading = color
                editor.setParagraphShading(color)
            }
            item.image = Self.swatch(color)
        }
        menu.addItem(.separator())
        menu.add("Borders and Shading…") { RibbonCommand.send(#selector(DocumentViewController.showBordersAndShading(_:)), editor) }
        return menu
    }

    private func bordersMenu() -> NSMenu {
        let menu = NSMenu()
        let current = editor.currentBorders
        for preset in EditorController.BorderPreset.allCases {
            let checked: Bool
            switch preset {
            case .bottom: checked = current.bottom
            case .top: checked = current.top
            case .left: checked = current.left
            case .right: checked = current.right
            case .none: checked = !current.hasBorder
            case .all, .outside: checked = current.top && current.bottom && current.left && current.right
            }
            menu.add(preset.displayName, symbol: preset.symbol, checked: checked) {
                lastBorder = preset
                editor.applyBorderPreset(preset)
            }
        }
        menu.addItem(.separator())
        menu.add("Horizontal Line", symbol: "minus") { RibbonCommand.send(#selector(DocumentViewController.insertHorizontalRule(_:)), editor) }
        menu.add("Borders and Shading…") { RibbonCommand.send(#selector(DocumentViewController.showBordersAndShading(_:)), editor) }
        return menu
    }

    private func sensitivityMenu() -> NSMenu {
        let menu = NSMenu()
        for label in SensitivityLabel.allCases {
            let item = menu.add(label.displayName, checked: editor.sensitivity == label) { editor.setSensitivity(label) }
            if label != .none { item.image = Self.swatch(label.color) }
        }
        return menu
    }

    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.stroke()
            return true
        }
    }
}

// MARK: - Styles gallery

/// Live previews of the document's styles, like Word's Styles gallery.
struct StyleGallery: View {
    @ObservedObject var editor: EditorController
    var width: CGFloat = 430
    @State private var anchor = MenuAnchor()

    private var styles: [StyleDefinition] {
        let preferred = ["normal", "noSpacing", "heading1", "heading2", "heading3", "title", "subtitle", "quote", "caption", "code"]
        let all = editor.styleSheet.allStyles
        let picked = preferred.compactMap { id in all.first { $0.id == id } }
        return picked + all.filter { style in !preferred.contains(style.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(styles) { style in
                        StyleCard(editor: editor, style: style, isCurrent: editor.formatting.styleID == style.id)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
            }
            .frame(width: width, height: 70)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
            Button {
                anchor.pop(allStylesMenu(), editor: editor)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 70)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MenuAnchorView(anchor: anchor))
            .help("More Styles")
        }
    }

    private func allStylesMenu() -> NSMenu {
        let menu = NSMenu()
        for style in editor.styleSheet.allStyles {
            menu.add(style.name, checked: editor.formatting.styleID == style.id) { editor.applyStyle(id: style.id) }
        }
        menu.addItem(.separator())
        menu.add("Create a Style…", symbol: "plus") { RibbonCommand.send(#selector(DocumentViewController.showStylesManager(_:)), editor) }
        menu.add("Clear Formatting", symbol: "eraser") { editor.clearFormatting() }
        menu.add("Manage Styles…", symbol: "slider.horizontal.3") { RibbonCommand.send(#selector(DocumentViewController.showStylesManager(_:)), editor) }
        return menu
    }
}

private struct StyleCard: View {
    @ObservedObject var editor: EditorController
    let style: StyleDefinition
    let isCurrent: Bool
    @State private var hovering = false

    var body: some View {
        let resolved = editor.styleSheet.resolve(style.id)
        Button {
            editor.applyStyle(id: style.id)
            editor.focusTextView()
        } label: {
            VStack(spacing: 3) {
                Text("AaBbCcDdE")
                    .font(Font(resolved.font.withSize(min(max(resolved.font.pointSize, 10), 17))))
                    .foregroundStyle(Color(nsColor: resolved.color))
                    .lineLimit(1)
                    .frame(width: 72, height: 30, alignment: .leading)
                    .clipped()
                Text(style.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isCurrent ? Theme.accentColor : (hovering ? Color.primary.opacity(0.35) : Color.primary.opacity(0.1)),
                                  lineWidth: isCurrent ? 2 : 1)
            )
            .environment(\.colorScheme, .light)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(style.name)
    }
}

// MARK: - Add-ins

private struct AddInsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add-ins", systemImage: "puzzlepiece.extension").font(.headline)
            Text("No add-ins are installed.")
                .foregroundStyle(.secondary)
            Text("Add-ins will extend Wired Paper with scripts and new commands. Put add-ins in the Add-ins folder; Wired Paper loads them on launch once add-in support is enabled.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Add-ins Folder") {
                let url = AddInsFolder.url
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

enum AddInsFolder {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Wired Paper/Add-ins", isDirectory: true)
    }
}
