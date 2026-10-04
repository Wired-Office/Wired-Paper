import AppKit

/// The text view for one column of a page. All pages share one NSLayoutManager
/// (and so one text storage, selection and undo stack); each column owns one
/// text container.
///
/// The view covers its column's share of the sheet so clicks in the margins
/// land in the text, while `textContainerOrigin` places the text in the column.
final class PageTextView: NSTextView {
    weak var editor: EditorController?

    /// Where this column's text starts within the view (margins, gutter,
    /// vertical page alignment).
    var containerOffset = NSPoint(x: 72, y: 72) {
        didSet {
            guard containerOffset != oldValue else { return }
            invalidateTextContainerOrigin()
            needsDisplay = true
        }
    }

    override var textContainerOrigin: NSPoint { containerOffset }

    // MARK: Protection & Track Changes

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let editor else { return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) }
        guard editor.allowsEdit(in: affectedCharRange) else { return false }
        if let replacement = replacementString, editor.isTrackingChanges, !editor.revisionTracker.isApplying {
            // Plain insertions proceed (and are marked afterwards); everything else is handled by the tracker.
            guard editor.revisionTracker.handleEdit(in: affectedCharRange, replacement: replacement, textView: self) else { return false }
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacement)
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard let editor else { return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) }
        for range in affectedRanges where !editor.allowsEdit(in: range.rangeValue) { return false }
        if let strings = replacementStrings, editor.isTrackingChanges, !editor.revisionTracker.isApplying {
            // Track each replacement separately, last first so ranges stay valid.
            for (range, string) in zip(affectedRanges, strings).reversed() {
                setSelectedRange(range.rangeValue)
                if editor.revisionTracker.handleEdit(in: range.rangeValue, replacement: string, textView: self),
                   super.shouldChangeText(in: range.rangeValue, replacementString: string) {
                    textStorage?.replaceCharacters(in: range.rangeValue, with: string)
                    didChangeText()
                }
            }
            return false
        }
        return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
    }

    // MARK: Pasteboard (keeps Wired Paper's own attributes)

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [PersistentAttributes.pasteboardType] + super.writablePasteboardTypes
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == PersistentAttributes.pasteboardType, let storage = textStorage {
            let pieces = selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
            guard !pieces.isEmpty else { return false }
            let combined = NSMutableAttributedString()
            for range in pieces { combined.append(storage.attributedSubstring(from: range)) }
            guard let data = PersistentAttributes.archive(combined) else { return false }
            return pboard.setData(data, forType: type)
        }
        return super.writeSelection(to: pboard, type: type)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [PersistentAttributes.pasteboardType] + super.readablePasteboardTypes
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == PersistentAttributes.pasteboardType,
           let data = pboard.data(forType: type),
           let text = PersistentAttributes.unarchive(data) {
            let pasted = NSMutableAttributedString(attributedString: text)
            // Comments and tracked changes don't travel with copied text.
            let full = NSRange(location: 0, length: pasted.length)
            pasted.removeAttribute(.wpComment, range: full)
            pasted.removeAttribute(.wpRevision, range: full)
            TextFormatter.replaceSelection(in: self, with: pasted, actionName: "Paste")
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.textViewDidBecomeActive(self) }
        return accepted
    }

    // MARK: Ruler

    /// Zero on the ruler sits at the page's left margin.
    override func updateRuler() {
        super.updateRuler()
        guard let scrollView = enclosingScrollView,
              let ruler = scrollView.horizontalRulerView,
              let documentView = scrollView.documentView
        else { return }
        ruler.originOffset = convert(textContainerOrigin, to: documentView).x
    }

    // MARK: Find — routed to the document-wide NSTextFinder

    override func performTextFinderAction(_ sender: Any?) {
        editor?.performFindAction(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performTextFinderAction(_:)) {
            return editor?.validateFindAction(item.tag) ?? false
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: Tables — Tab moves between cells

    override func insertTab(_ sender: Any?) {
        if editor?.inlineCompletion.accept(in: self) == true { return }
        if editor?.moveToAdjacentTableCell(forward: true) == true { return }
        if ListFormatter.isAtItemStart(in: self), ListFormatter.changeLevel(by: 1, in: self) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if editor?.moveToAdjacentTableCell(forward: false) == true { return }
        if ListFormatter.isAtItemStart(in: self), ListFormatter.changeLevel(by: -1, in: self) { return }
        super.insertBacktab(sender)
    }

    override func insertNewline(_ sender: Any?) {
        let location = selectedRange().location
        let styleID: String? = {
            guard let storage = textStorage, storage.length > 0 else { return nil }
            return storage.attribute(.wpParagraphStyle, at: min(max(location - 1, 0), storage.length - 1), effectiveRange: nil) as? String
        }()
        super.insertNewline(sender)
        if let styleID { editor?.applyNextStyleAfterNewline(previousStyleID: styleID) }
    }

    // MARK: Inline suggestions

    override func cancelOperation(_ sender: Any?) {
        if let completion = editor?.inlineCompletion, completion.suggestion != nil {
            completion.dismiss()
            return
        }
        super.cancelOperation(sender)
    }

    /// Option-Right Arrow accepts the next word of a suggestion.
    override func moveWordRight(_ sender: Any?) {
        if editor?.inlineCompletion.acceptWord(in: self) == true { return }
        super.moveWordRight(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let suggestion = editor?.inlineCompletion.suggestion { drawSuggestion(suggestion) }
    }

    /// Where the suggestion's text would be laid out, in view coordinates, or
    /// nil when its location isn't in this column.
    func suggestionRect(for suggestion: InlineCompletionController.Suggestion) -> NSRect? {
        guard let layout = suggestionLayout(for: suggestion) else { return nil }
        return layout.rect
    }

    private func drawSuggestion(_ suggestion: InlineCompletionController.Suggestion) {
        guard selectedRange() == NSRange(location: suggestion.location, length: 0),
              let layout = suggestionLayout(for: suggestion), layout.rect.intersects(visibleRect)
        else { return }
        let text = NSAttributedString(string: suggestion.text, attributes: layout.attributes)
        text.draw(with: layout.rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Lays the suggestion out like the paragraph it continues: the first line
    /// starts at the insertion point and wraps within the column. Unless the
    /// insertion point is at the end of the document, it is kept to one line so
    /// it doesn't cover the next paragraph.
    private func suggestionLayout(for suggestion: InlineCompletionController.Suggestion) -> (rect: NSRect, attributes: [NSAttributedString.Key: Any])? {
        guard let layoutManager, let container = textContainer, let storage = textStorage,
              suggestion.location <= storage.length else { return nil }
        let atEnd = suggestion.location == storage.length
        let lineRect: NSRect
        let caretX: CGFloat
        let baseline: CGFloat
        if atEnd, layoutManager.extraLineFragmentTextContainer === container {
            lineRect = layoutManager.extraLineFragmentRect
            caretX = lineRect.minX + container.lineFragmentPadding
            baseline = lineRect.height * 0.8
        } else {
            let charIndex = atEnd ? suggestion.location - 1 : suggestion.location
            guard charIndex >= 0 else { return nil }
            let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
            guard glyph < layoutManager.numberOfGlyphs,
                  layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil) === container else { return nil }
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let glyphLocation = layoutManager.location(forGlyphAt: glyph)
            caretX = atEnd
                ? layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).maxX
                : lineRect.minX + glyphLocation.x
            baseline = glyphLocation.y
        }

        var attributes = typingAttributes
        for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .backgroundColor, .link, .attachment] {
            attributes.removeValue(forKey: key)
        }
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        attributes[.foregroundColor] = Theme.suggestionInk
        let base = (attributes[.paragraphStyle] as? NSParagraphStyle) ?? defaultParagraphStyle ?? .default
        let style = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let padding = container.lineFragmentPadding
        style.firstLineHeadIndent = max(caretX - padding, 0)
        style.paragraphSpacingBefore = 0
        style.alignment = .natural
        style.textLists = []
        attributes[.paragraphStyle] = style

        let origin = textContainerOrigin
        let width = container.size.width - 2 * padding
        let oneLine = ceil(layoutManager.defaultLineHeight(for: font) * max(style.lineHeightMultiple, 1)) + style.lineSpacing + 1
        let height = atEnd ? max(bounds.maxY - origin.y - lineRect.minY, oneLine) : oneLine
        let rect = NSRect(x: origin.x + padding,
                          y: origin.y + lineRect.minY + baseline - font.ascender,
                          width: width, height: height)
        return (rect, attributes)
    }
}
