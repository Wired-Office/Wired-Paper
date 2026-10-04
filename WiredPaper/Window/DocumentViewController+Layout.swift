import AppKit
import SwiftUI

/// Styles, character effects, paragraph flow, page layout, headers/footers,
/// fields and document properties.
extension DocumentViewController {
    // MARK: Styles & themes

    @objc func showStylesManager(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            StylesManagerSheet(
                theme: document.styleSheet.theme,
                overrides: document.metadata.styles,
                currentParagraphStyleID: editor.formatting.styleID,
                onApply: { theme, styles in
                    dismiss()
                    editor.updateStyles(theme: theme, styles: styles)
                },
                onCancel: dismiss
            )
        }
    }

    @objc func applyThemeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let document,
              let theme = DocumentTheme.presets.first(where: { $0.id == id }) else { return }
        editor.updateStyles(theme: theme, styles: document.metadata.styles)
    }

    // MARK: Character effects

    @objc func toggleAllCaps(_ sender: Any?) {
        CharacterEffects.setFlag(CharacterFlags.allCaps, on: !editor.formatting.isAllCaps, in: editor.textView, actionName: "All Caps")
        editor.refreshState()
    }

    @objc func toggleSmallCaps(_ sender: Any?) {
        CharacterEffects.setFlag(CharacterFlags.smallCaps, on: !editor.formatting.isSmallCaps, in: editor.textView, actionName: "Small Caps")
        editor.refreshState()
    }

    @objc func toggleDoubleUnderline(_ sender: Any?) {
        let value: Int? = editor.formatting.isDoubleUnderline ? nil : NSUnderlineStyle.double.rawValue
        TextFormatter.setAttribute(.underlineStyle, to: value, in: editor.textView, actionName: "Double Underline")
        editor.refreshState()
    }

    @objc func toggleHiddenText(_ sender: Any?) {
        TextFormatter.setAttribute(.wpHidden, to: editor.formatting.isHidden ? nil : "1", in: editor.textView, actionName: "Hidden Text")
        editor.refreshState()
    }

    @objc func toggleShowHiddenText(_ sender: Any?) {
        editor.setShowHiddenText(!editor.showsHiddenText)
    }

    @objc func setTextEffectFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let effect = CharacterEffects.Effect(rawValue: raw) else { return }
        CharacterEffects.apply(effect, in: editor.textView)
    }

    @objc func changeCaseFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let change = CharacterEffects.CaseChange(rawValue: raw) else { return }
        CharacterEffects.changeCase(change, in: editor.textView)
    }

    @objc func setCharacterSpacingFromMenu(_ sender: NSMenuItem) {
        let points = CGFloat(sender.tag) / 10
        CharacterEffects.setSpacing(sender.tag == 0 ? nil : points, in: editor.textView)
    }

    @objc func toggleFormatPainter(_ sender: Any?) {
        editor.toggleFormatPainter()
    }

    // MARK: Lists

    @objc func applyListStyleFromMenu(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? String else { return }
        ListFormatter.applyMarkerFormat(format, in: editor.textView)
        editor.refreshState()
    }

    @objc func increaseListLevel(_ sender: Any?) {
        if !ListFormatter.changeLevel(by: 1, in: editor.textView) { editor.changeIndent(by: 36) }
    }

    @objc func decreaseListLevel(_ sender: Any?) {
        if !ListFormatter.changeLevel(by: -1, in: editor.textView) { editor.changeIndent(by: -36) }
    }

    @objc func restartNumbering(_ sender: Any?) {
        ListFormatter.restartNumbering(in: editor.textView)
    }

    @objc func continueNumbering(_ sender: Any?) {
        ListFormatter.continueNumbering(in: editor.textView)
    }

    @objc func setNumberingValue(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            NumberPromptSheet(title: "Set Numbering Value", label: "Start at", initial: 1, range: 0...9999, onApply: { value in
                dismiss()
                ListFormatter.restartNumbering(in: editor.textView, at: value)
            }, onCancel: dismiss)
        }
    }

    // MARK: Paragraph flow & borders

    @objc func toggleParagraphFlagFromMenu(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        editor.setParagraphFlag(token, on: !editor.formatting.paragraphFlags.contains(token))
    }

    @objc func showBordersAndShading(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            BordersShadingSheet(initial: ParagraphBorders.current(in: editor.textView), onApply: { settings in
                dismiss()
                ParagraphBorders.apply(settings, in: editor.textView)
            }, onCancel: dismiss)
        }
    }

    @objc func showTabsSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let unit = AppSettings.shared.measurementUnit
        SheetPresenter.present(in: window) { dismiss in
            TabsSheet(tabs: TabStops.current(in: editor.textView), unit: unit, onApply: { tabs, defaultInterval in
                dismiss()
                TabStops.apply(tabs, defaultInterval: defaultInterval, in: editor.textView)
            }, onCancel: dismiss)
        }
    }

    // MARK: Page layout

    @objc func setColumnsFromMenu(_ sender: NSMenuItem) {
        let count = sender.tag
        document?.updateMetadata("Columns") { $0.decoration.columns = min(max(count, 1), 6) }
    }

    @objc func showColumnsSheet(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let unit = AppSettings.shared.measurementUnit
        SheetPresenter.present(in: window) { dismiss in
            ColumnsSheet(decoration: document.metadata.decoration, unit: unit, onApply: { decoration in
                dismiss()
                document.updateMetadata("Columns") {
                    $0.decoration.columns = decoration.columns
                    $0.decoration.columnSpacing = decoration.columnSpacing
                    $0.decoration.columnSeparator = decoration.columnSeparator
                }
            }, onCancel: dismiss)
        }
    }

    @objc func insertColumnBreak(_ sender: Any?) {
        editor.insertBreak(column: true)
    }

    @objc func setPageColorFromMenu(_ sender: NSMenuItem) {
        let hex = (sender.representedObject as? NSColor)?.hexString
        document?.updateMetadata("Page Color") { $0.decoration.pageColorHex = hex }
    }

    @objc func showWatermarkSheet(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        SheetPresenter.present(in: window) { dismiss in
            WatermarkSheet(initial: document.metadata.decoration.watermark, onApply: { watermark in
                dismiss()
                document.updateMetadata("Watermark") { $0.decoration.watermark = watermark }
            }, onCancel: dismiss)
        }
    }

    @objc func showPageBorderSheet(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        SheetPresenter.present(in: window) { dismiss in
            PageBorderSheet(initial: document.metadata.decoration.border, onApply: { border in
                dismiss()
                document.updateMetadata("Page Borders") { $0.decoration.border = border }
            }, onCancel: dismiss)
        }
    }

    @objc func setLineNumbersFromMenu(_ sender: NSMenuItem) {
        document?.updateMetadata("Line Numbers") { metadata in
            switch sender.tag {
            case 0: metadata.decoration.lineNumbers = nil
            case 1: metadata.decoration.lineNumbers = { var s = LineNumberSettings(); s.restartEachPage = false; return s }()
            default: metadata.decoration.lineNumbers = LineNumberSettings()
            }
        }
    }

    @objc func toggleHyphenation(_ sender: Any?) {
        document?.updateMetadata("Hyphenation") { $0.decoration.hyphenation.toggle() }
    }

    @objc func toggleWidowControl(_ sender: Any?) {
        document?.updateMetadata("Widow/Orphan Control") { $0.decoration.widowControl.toggle() }
    }

    @objc func setVerticalAlignmentFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let alignment = VerticalPageAlignment(rawValue: raw) else { return }
        document?.updateMetadata("Vertical Alignment") { $0.decoration.verticalAlignment = alignment }
    }

    @objc func setMarginsFromMenu(_ sender: NSMenuItem) {
        guard let document else { return }
        var setup = document.pageSetup
        let inch: CGFloat = 72
        switch sender.tag {
        case 1: setup.margins = Margins(top: inch / 2, left: inch / 2, bottom: inch / 2, right: inch / 2)
        case 2: setup.margins = Margins(top: inch, left: inch * 0.75, bottom: inch, right: inch * 0.75)
        case 3: setup.margins = Margins(top: inch, left: inch * 2, bottom: inch, right: inch * 2)
        default: setup.margins = .oneInch
        }
        document.updatePageSetup(setup)
    }

    @objc func setOrientationFromMenu(_ sender: NSMenuItem) {
        guard let document else { return }
        document.updatePageSetup(document.pageSetup.oriented(sender.tag == 1 ? .landscape : .portrait))
    }

    @objc func setPaperFromMenu(_ sender: NSMenuItem) {
        guard let document, let raw = sender.representedObject as? String, let preset = PaperPreset(rawValue: raw) else { return }
        var setup = document.pageSetup
        setup.paperSize = preset.size
        document.updatePageSetup(setup.oriented(document.pageSetup.orientation))
    }

    // MARK: Headers, footers, fields, properties

    @objc func showHeaderFooterSheet(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        SheetPresenter.present(in: window) { dismiss in
            HeaderFooterSheet(initial: document.metadata.headerFooter, onApply: { settings in
                dismiss()
                document.updateMetadata("Header & Footer") { $0.headerFooter = settings }
            }, onCancel: dismiss)
        }
    }

    @objc func insertPageNumbers(_ sender: NSMenuItem) {
        document?.updateMetadata("Page Numbers") { metadata in
            let token = sender.tag == 1 ? "Page {PAGE} of {PAGES}" : "{PAGE}"
            if sender.representedObject as? String == "header" {
                metadata.headerFooter.header.right = token
            } else {
                metadata.headerFooter.footer.center = token
            }
        }
    }

    @objc func insertFieldFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = FieldKind(rawValue: raw) else { return }
        editor.insertField(FieldSpec(kind: kind))
    }

    @objc func showInsertFieldSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let bookmarks = editor.bookmarkNames
        SheetPresenter.present(in: window) { dismiss in
            InsertFieldSheet(bookmarks: bookmarks, onInsert: { spec in
                dismiss()
                editor.insertField(spec)
            }, onCancel: dismiss)
        }
    }

    @objc func updateFields(_ sender: Any?) {
        editor.updateFields()
    }

    @objc func showDocumentProperties(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let statistics = editor.statistics
        let pages = editor.pageCount
        SheetPresenter.present(in: window) { dismiss in
            DocumentPropertiesSheet(
                properties: document.metadata.properties,
                statistics: statistics,
                pages: pages,
                created: document.metadata.created,
                modified: document.fileModificationDate,
                location: document.fileURL,
                onApply: { properties in
                    dismiss()
                    document.updateMetadata("Properties") { $0.properties = properties }
                },
                onCancel: dismiss
            )
        }
    }
}

extension DocumentViewController {
    /// Check marks and titles for the style, layout and page menus.
    func validateDocumentMenuItem(_ item: NSMenuItem) -> Bool {
        if let result = validateObjectMenuItem(item) { return result }
        let state = editor.formatting
        let decoration = document?.metadata.decoration ?? PageDecoration()
        func check(_ on: Bool) { item.state = on ? .on : .off }

        switch item.action {
        case #selector(toggleAllCaps(_:)): check(state.isAllCaps)
        case #selector(toggleSmallCaps(_:)): check(state.isSmallCaps)
        case #selector(toggleDoubleUnderline(_:)): check(state.isDoubleUnderline)
        case #selector(toggleHiddenText(_:)): check(state.isHidden)
        case #selector(toggleShowHiddenText(_:)):
            item.title = editor.showsHiddenText ? "Hide Hidden Text" : "Show Hidden Text"
        case #selector(toggleFormatPainter(_:)): check(editor.isFormatPainterActive)
        case #selector(toggleParagraphFlagFromMenu(_:)):
            check((item.representedObject as? String).map { state.paragraphFlags.contains($0) } ?? false)
        case #selector(setColumnsFromMenu(_:)): check(decoration.columns == item.tag)
        case #selector(toggleHyphenation(_:)): check(decoration.hyphenation)
        case #selector(toggleWidowControl(_:)): check(decoration.widowControl)
        case #selector(setLineNumbersFromMenu(_:)):
            let numbers = decoration.lineNumbers
            switch item.tag {
            case 0: check(numbers == nil)
            case 1: check(numbers.map { !$0.restartEachPage } ?? false)
            default: check(numbers?.restartEachPage ?? false)
            }
        case #selector(setVerticalAlignmentFromMenu(_:)):
            check(decoration.verticalAlignment.rawValue == item.representedObject as? String)
        case #selector(setOrientationFromMenu(_:)):
            check((document?.pageSetup.orientation == .landscape) == (item.tag == 1))
        case #selector(setPaperFromMenu(_:)):
            check(PaperPreset.matching(document?.pageSetup.paperSize ?? .zero)?.rawValue == item.representedObject as? String)
        case #selector(applyThemeFromMenu(_:)):
            check(document?.styleSheet.theme.id == item.representedObject as? String)
        case #selector(setPageColorFromMenu(_:)):
            check((item.representedObject as? NSColor)?.hexString == decoration.pageColorHex)
        case #selector(restartNumbering(_:)), #selector(continueNumbering(_:)), #selector(setNumberingValue(_:)):
            return state.listKind != nil
        case #selector(toggleTrackChanges(_:)): check(editor.isTrackingChanges)
        case #selector(setMarkupModeFromMenu(_:)): check(editor.markupMode.rawValue == item.representedObject as? String)
        case #selector(markAsFinal(_:)): check(document?.metadata.protection.markedFinal == true)
        case #selector(stopProtection(_:)): return document?.metadata.protection.restriction != EditingRestriction.none
        case #selector(setCitationStyleFromMenu(_:)): check(editor.citationStyle.rawValue == item.representedObject as? String)
        case #selector(toggleNavigationPane(_:)): check(editor.sidebar.left == .navigation)
        case #selector(showCommentsPane(_:)): check(editor.sidebar.right == .comments)
        case #selector(showReviewPane(_:)): check(editor.sidebar.right == .review)
        case #selector(showNotesPane(_:)): check(editor.sidebar.right == .notes)
        case #selector(showCitationsPane(_:)): check(editor.sidebar.right == .references)
        case #selector(deleteCurrentComment(_:)): return editor.activeCommentID != nil
        default:
            break
        }
        return true
    }
}
