import AppKit

/// Document-level editing features: styles and themes, format painter,
/// paragraph flow flags, breaks, fields, bookmarks and list upkeep.
extension EditorController {
    // MARK: Styles & themes

    /// Replaces the theme and style definitions and restyles the text to match,
    /// as one undoable step.
    func updateStyles(theme: DocumentTheme, styles: [StyleDefinition]) {
        guard let document else { return }
        document.undoManager?.beginUndoGrouping()
        document.updateMetadata("Styles") {
            $0.theme = theme
            $0.styles = styles
        }
        TextFormatter.restyleDocument(textStorage, sheet: document.styleSheet, in: textView, actionName: "Styles")
        document.undoManager?.endUndoGrouping()
        document.undoManager?.setActionName("Styles")
        refreshState()
    }

    // MARK: Hidden text

    func setShowHiddenText(_ show: Bool) {
        guard let engine else { return }
        showsHiddenText = show
        engine.policy.showHiddenText = show
        engine.invalidateAllGlyphs()
        refreshMarkup()
    }

    // MARK: Format painter

    /// Copies the formatting at the insertion point; the next selection receives it.
    func toggleFormatPainter() {
        if isFormatPainterActive {
            formatPainterSource = nil
            setFormatPainterActive(false)
            return
        }
        let textView = self.textView
        let selection = textView.selectedRange()
        let characterAttributes = selection.length > 0 && selection.location < textStorage.length
            ? textStorage.attributes(at: selection.location, effectiveRange: nil)
            : textView.typingAttributes
        var character = characterAttributes
        for key in [NSAttributedString.Key.attachment, .link, .wpObject, .wpComment, .wpRevision, .wpBookmark, .paragraphStyle] {
            character.removeValue(forKey: key)
        }
        formatPainterSource = (character, characterAttributes[.paragraphStyle] as? NSParagraphStyle)
        setFormatPainterActive(true)
    }

    private func setFormatPainterActive(_ active: Bool) {
        isFormatPainterActive = active
        (active ? NSCursor.iBeamCursorForVerticalLayout : NSCursor.iBeam).set()
    }

    func applyFormatPainterIfNeeded() {
        guard isFormatPainterActive, let source = formatPainterSource else { return }
        let textView = self.textView
        let selection = textView.selectedRange()
        // Apply once the drag selection finishes.
        guard selection.length > 0, NSEvent.pressedMouseButtons == 0 else { return }
        formatPainterSource = nil
        setFormatPainterActive(false)
        guard textView.shouldChangeText(in: selection, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.addAttributes(source.character, range: selection)
        for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .backgroundColor, .shadow, .strokeWidth, .kern, .superscript]
            where source.character[key] == nil {
            textStorage.removeAttribute(key, range: selection)
        }
        if let paragraph = source.paragraph {
            let paragraphRange = (textStorage.string as NSString).paragraphRange(for: selection)
            if (selection.length >= paragraphRange.length - 1) {
                textStorage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            }
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName("Format Painter")
    }

    // MARK: Paragraph flow

    func setParagraphFlag(_ token: String, on: Bool) {
        let textView = self.textView
        let ranges = (textView.rangesForUserParagraphAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) else { return }
        textStorage.beginEditing()
        for range in ranges {
            var tokens = FlagTokens.set(textStorage.attribute(.wpParaFlags, at: range.location, effectiveRange: nil))
            if on { tokens.insert(token) } else { tokens.remove(token) }
            if let value = FlagTokens.string(tokens) {
                textStorage.addAttribute(.wpParaFlags, value: value, range: range)
            } else {
                textStorage.removeAttribute(.wpParaFlags, range: range)
            }
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName("Line and Page Breaks")
        refreshState()
    }

    // MARK: Breaks

    func insertBreak(column: Bool) {
        let textView = self.textView
        var attributes = TextFormatter.baseAttributes(for: textView)
        if column { attributes[.wpBreakKind] = "column" }
        TextFormatter.replaceSelection(in: textView, with: NSAttributedString(string: "\u{0C}", attributes: attributes), actionName: column ? "Column Break" : "Page Break")
        focusTextView()
    }

    // MARK: Fields

    func insertField(_ spec: FieldSpec) {
        let textView = self.textView
        var spec = spec
        if (spec.kind == .date || spec.kind == .time), spec.fixedValue == nil, AppSettings.shared.fixDateFieldsOnInsert {
            spec.fixedValue = spec.kind == .date
                ? DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
                : DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        }
        let content = ObjectFactory.string(for: .field(spec), image: nil, attributes: TextFormatter.baseAttributes(for: textView))
        TextFormatter.replaceSelection(in: textView, with: content, actionName: "Insert Field")
        updateFields()
    }

    /// Recomputes every field, note and caption number.
    func updateFields() {
        let values = LiveValues.compute(for: textStorage, metadata: document?.metadata)
        values.apply(to: layoutManager)
        layoutManager.fieldValues = document?.fieldValues ?? layoutManager.fieldValues
        layoutManager.invalidateLiveObjects()
        pagesView?.refreshPages()
    }

    // MARK: Bookmarks

    var bookmarkNames: [String] {
        var names: [String] = []
        textStorage.enumerateAttribute(.wpBookmark, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            if let name = value as? String, !names.contains(name) { names.append(name) }
        }
        return names
    }

    func addBookmark(named name: String) {
        let textView = self.textView
        var range = textView.selectedRange()
        if range.length == 0 {
            range = (textStorage.string as NSString).rangeOfWord(at: range.location)
        }
        guard range.length > 0 else { NSSound.beep(); return }
        removeBookmark(named: name, actionName: nil)
        TextFormatter.setAttribute(.wpBookmark, to: name, in: textView, actionName: "Bookmark")
        updateFields()
    }

    func removeBookmark(named name: String, actionName: String? = "Delete Bookmark") {
        var ranges: [NSRange] = []
        textStorage.enumerateAttribute(.wpBookmark, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            if value as? String == name { ranges.append(range) }
        }
        guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) else { return }
        for range in ranges { textStorage.removeAttribute(.wpBookmark, range: range) }
        textView.didChangeText()
        if let actionName { textView.undoManager?.setActionName(actionName) }
    }

    func goToBookmark(named name: String) {
        var target: NSRange?
        textStorage.enumerateAttribute(.wpBookmark, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            if value as? String == name { target = range; stop.pointee = true }
        }
        if let target { reveal(target) }
    }

    // MARK: Lists

    /// Keeps numbered lists sequential after edits (e.g. deleting an item).
    func renumberListsIfNeeded() {
        guard !isRenumbering else { return }
        let selection = textView.selectedRange()
        let location = min(selection.location, max(textStorage.length - 1, 0))
        guard textStorage.length > 0 else { return }
        // Only lists near the edit can have changed.
        let paragraph = (textStorage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let nearby = NSUnionRange(paragraph, NSRange(location: max(paragraph.location - 1, 0), length: 0))
        var touchesList = false
        textStorage.enumerateAttribute(.paragraphStyle, in: NSIntersectionRange(nearby, NSRange(location: 0, length: textStorage.length))) { value, _, stop in
            if let style = value as? NSParagraphStyle, !style.textLists.isEmpty { touchesList = true; stop.pointee = true }
        }
        if !touchesList, NSMaxRange(paragraph) < textStorage.length,
           let next = textStorage.attribute(.paragraphStyle, at: NSMaxRange(paragraph), effectiveRange: nil) as? NSParagraphStyle,
           !next.textLists.isEmpty {
            touchesList = true
        }
        guard touchesList else { return }
        isRenumbering = true
        defer { isRenumbering = false }
        textView.breakUndoCoalescing()
        if ListFormatter.renumber(in: textView) {
            textView.setSelectedRange(selection)
        }
    }

    // MARK: Next style after Return

    /// After Return at the end of a heading, the new paragraph takes the style's "next" style.
    func applyNextStyleAfterNewline(previousStyleID: String) {
        guard let next = styleSheet.nextStyleID(for: previousStyleID), next != previousStyleID else { return }
        let textView = self.textView
        let location = textView.selectedRange().location
        let paragraph = (textStorage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let content = (textStorage.string as NSString).substring(with: paragraph).trimmingCharacters(in: .newlines)
        guard content.isEmpty else { return }
        applyStyle(id: next)
    }

    // MARK: Comments (selection tracking)

    func updateActiveCommentFromSelection() {
        let location = textView.selectedRange().location
        guard location < textStorage.length else {
            setActiveComment(nil)
            return
        }
        let ids = (textStorage.attribute(.wpComment, at: location, effectiveRange: nil) as? String)?.split(separator: " ").map(String.init)
        setActiveComment(ids?.first)
    }
}
