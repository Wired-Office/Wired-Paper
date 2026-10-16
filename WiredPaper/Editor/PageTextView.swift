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

    /// Picture selection: the frame the handles were last drawn around, the
    /// outline shown while resizing, and the drop caret shown while moving.
    fileprivate var imageHandlesFrame: NSRect?
    fileprivate var resizePreview: (rect: NSRect, image: NSImage)?
    fileprivate var dropCaret: NSRect? {
        didSet {
            if let oldValue { setNeedsDisplay(oldValue.insetBy(dx: -2, dy: -2)) }
            if let dropCaret { setNeedsDisplay(dropCaret.insetBy(dx: -2, dy: -2)) }
        }
    }

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
        drawImageSelection()
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

// MARK: - Pictures: select, resize and move with the mouse

extension PageTextView {
    private static let handleSize: CGFloat = 8
    private static let minimumImageSide: CGFloat = 16

    /// Which edges a handle moves.
    private struct Handle {
        var left = false, right = false, top = false, bottom = false
        var isCorner: Bool { (left || right) && (top || bottom) }
    }

    /// The frame of the picture character at `location` in view coordinates,
    /// or nil when it isn't a picture laid out in this column.
    private func imageFrame(at location: Int) -> NSRect? {
        guard let editor, editor.isImage(at: location),
              let layoutManager, let container = textContainer else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil) === container else { return nil }
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let position = layoutManager.location(forGlyphAt: glyph)
        let size = layoutManager.attachmentSize(forGlyphAt: glyph)
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = textContainerOrigin
        return NSRect(x: origin.x + line.minX + position.x,
                      y: origin.y + line.minY + position.y - size.height,
                      width: size.width, height: size.height)
    }

    /// The selected picture when it is laid out in this column.
    private var selectedImageFrame: (location: Int, frame: NSRect)? {
        let selection = selectedRange()
        guard selection.length == 1, let frame = imageFrame(at: selection.location) else { return nil }
        return (selection.location, frame)
    }

    /// The picture under `point` (view coordinates).
    private func image(at point: NSPoint) -> (location: Int, frame: NSRect)? {
        guard let layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let location = layoutManager.characterIndexForGlyph(at: glyph)
        guard let frame = imageFrame(at: location), frame.contains(point) else { return nil }
        return (location, frame)
    }

    private func handleRects(for frame: NSRect) -> [(Handle, NSRect)] {
        let size = Self.handleSize
        func rect(_ x: CGFloat, _ y: CGFloat) -> NSRect { NSRect(x: x - size / 2, y: y - size / 2, width: size, height: size) }
        var handles: [(Handle, NSRect)] = [
            (Handle(left: true, top: true), rect(frame.minX, frame.minY)),
            (Handle(right: true, top: true), rect(frame.maxX, frame.minY)),
            (Handle(left: true, bottom: true), rect(frame.minX, frame.maxY)),
            (Handle(right: true, bottom: true), rect(frame.maxX, frame.maxY)),
        ]
        // Edge handles only when there is room between the corners.
        if frame.width > size * 4 {
            handles.append((Handle(top: true), rect(frame.midX, frame.minY)))
            handles.append((Handle(bottom: true), rect(frame.midX, frame.maxY)))
        }
        if frame.height > size * 4 {
            handles.append((Handle(left: true), rect(frame.minX, frame.midY)))
            handles.append((Handle(right: true), rect(frame.maxX, frame.midY)))
        }
        return handles
    }

    private func handle(at point: NSPoint, frame: NSRect) -> Handle? {
        handleRects(for: frame).first { $0.1.insetBy(dx: -3, dy: -3).contains(point) }?.0
    }

    // MARK: Drawing

    private func drawImageSelection() {
        // NSTextView leaves the clip at the text container; handles reach into the margins.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).setClip()
        if let dropCaret {
            Theme.accent.setFill()
            dropCaret.fill()
        }
        if let preview = resizePreview {
            preview.image.draw(in: preview.rect, from: .zero, operation: .sourceOver, fraction: 0.55)
            let outline = NSBezierPath(rect: preview.rect.insetBy(dx: 0.5, dy: 0.5))
            outline.setLineDash([4, 3], count: 2, phase: 0)
            Theme.accent.setStroke()
            outline.stroke()
        }
        guard window?.firstResponder === self || window?.firstResponder is PageTextView,
              let (_, frame) = selectedImageFrame else { return }
        Theme.accent.setStroke()
        let border = NSBezierPath(rect: frame.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
        for (_, rect) in handleRects(for: frame) {
            NSColor.white.setFill()
            rect.fill()
            let edge = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
        }
    }

    /// Redraws the handles where they were and where they are now.
    func refreshImageHandles() {
        let new = selectedImageFrame?.frame
        guard new != imageHandlesFrame else { return }
        let margin = -(Self.handleSize + 2)
        if let old = imageHandlesFrame { setNeedsDisplay(old.insetBy(dx: margin, dy: margin)) }
        if let new { setNeedsDisplay(new.insetBy(dx: margin, dy: margin)) }
        imageHandlesFrame = new
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // After the current event, so layout isn't forced in the middle of an edit.
        DispatchQueue.main.async { [weak self] in
            self?.editor?.pagesView?.allTextViews.forEach { $0.refreshImageHandles() }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (location, frame) = selectedImageFrame, let grip = handle(at: point, frame: frame) {
            trackResize(of: location, frame: frame, handle: grip, from: event)
            return
        }
        if !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.command), let (location, frame) = image(at: point) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: location, length: 1))
            if event.clickCount >= 2 {
                NSApp.sendAction(#selector(DocumentViewController.editSelectedObject(_:)), to: nil, from: self)
            } else {
                trackMove(of: location, frame: frame, from: event)
            }
            return
        }
        super.mouseDown(with: event)
    }

    private func trackResize(of location: Int, frame: NSRect, handle: Handle, from event: NSEvent) {
        guard let editor, let attachment = textStorage?.attribute(.attachment, at: location, effectiveRange: nil) as? NSTextAttachment,
              let image = AttachmentNormalizer.sourceImage(for: attachment) else { return }
        let start = convert(event.locationInWindow, from: nil)
        let maxSize = editor.geometry.maxAttachmentSize
        let aspect = frame.width / max(frame.height, 1)
        let minSide = Self.minimumImageSide
        var result = frame

        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event else { return }
            let point = self.convert(event.locationInWindow, from: nil)
            let dx = point.x - start.x, dy = point.y - start.y
            var width = frame.width + (handle.right ? dx : handle.left ? -dx : 0)
            var height = frame.height + (handle.bottom ? dy : handle.top ? -dy : 0)
            width = min(max(width, minSide), maxSize.width)
            height = min(max(height, minSide), maxSize.height)
            // Corners keep the proportions unless Shift is held.
            if handle.isCorner && !event.modifierFlags.contains(.shift) {
                if width / aspect > height { height = width / aspect } else { width = height * aspect }
                if width > maxSize.width { width = maxSize.width; height = width / aspect }
                if height > maxSize.height { height = maxSize.height; width = height * aspect }
            }
            // The edges opposite the handle stay put.
            let x = handle.left ? frame.maxX - width : frame.minX
            let y = handle.top ? frame.maxY - height : frame.minY
            let old = self.resizePreview?.rect ?? frame
            result = NSRect(x: x, y: y, width: width, height: height)
            self.resizePreview = (result, image)
            self.setNeedsDisplay(old.union(result).insetBy(dx: -4, dy: -4))
            if event.type == .leftMouseUp {
                stop.pointee = true
                self.resizePreview = nil
                self.setNeedsDisplay(old.union(result).insetBy(dx: -4, dy: -4))
                if abs(result.width - frame.width) >= 1 || abs(result.height - frame.height) >= 1 {
                    editor.setImageSize(result.size, at: location)
                }
            }
        }
    }

    private func trackMove(of location: Int, frame: NSRect, from event: NSEvent) {
        guard let editor, let pagesView = editor.pagesView else { return }
        let start = event.locationInWindow
        var moving = false
        var target: (view: PageTextView, index: Int)?

        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event else { return }
            if !moving {
                moving = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4
                if moving { NSCursor.closedHand.push() }
            }
            if moving, event.type == .leftMouseDragged {
                self.autoscroll(with: event)
                target?.view.dropCaret = nil
                target = nil
                for view in pagesView.allTextViews {
                    let point = view.convert(event.locationInWindow, from: nil)
                    guard view.visibleRect.contains(point) else { continue }
                    let index = view.characterIndexForInsertion(at: point)
                    if let caret = view.caretRect(forInsertionAt: index) {
                        target = (view, index)
                        view.dropCaret = caret
                    }
                    break
                }
            }
            if event.type == .leftMouseUp {
                stop.pointee = true
                guard moving else { return }
                NSCursor.pop()
                target?.view.dropCaret = nil
                if let target { editor.moveImage(from: location, to: target.index) }
            }
        }
    }

    /// A thin caret where text inserted at `index` would go, in view coordinates.
    private func caretRect(forInsertionAt index: Int) -> NSRect? {
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return nil }
        let origin = textContainerOrigin
        if index >= storage.length, layoutManager.extraLineFragmentTextContainer === container {
            let line = layoutManager.extraLineFragmentRect
            return NSRect(x: origin.x + line.minX + container.lineFragmentPadding - 1, y: origin.y + line.minY, width: 2, height: line.height)
        }
        guard storage.length > 0 else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(index, storage.length - 1))
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil) === container else { return nil }
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let x = index >= storage.length
            ? layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).maxX
            : line.minX + layoutManager.location(forGlyphAt: glyph).x
        return NSRect(x: origin.x + x - 1, y: origin.y + line.minY, width: 2, height: line.height)
    }

    // MARK: Cursor

    private func imageCursor(at point: NSPoint) -> NSCursor? {
        if let (_, frame) = selectedImageFrame, let grip = handle(at: point, frame: frame) {
            if grip.isCorner {
                if #available(macOS 15.0, *) {
                    let position: NSCursor.FrameResizePosition = grip.top
                        ? (grip.left ? .topLeft : .topRight)
                        : (grip.left ? .bottomLeft : .bottomRight)
                    return .frameResize(position: position, directions: .all)
                }
                return .crosshair
            }
            return grip.left || grip.right ? .resizeLeftRight : .resizeUpDown
        }
        if image(at: point) != nil { return .openHand }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        if let cursor = imageCursor(at: convert(event.locationInWindow, from: nil)) {
            cursor.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        if let cursor = imageCursor(at: convert(event.locationInWindow, from: nil)) {
            cursor.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let editor, let menu, let (location, _) = image(at: point) else { return menu }
        setSelectedRange(NSRange(location: location, length: 1))
        let items: [NSMenuItem] = [
            NSMenuItem(title: "Format Picture…", action: #selector(DocumentViewController.showPictureFormatSheet(_:)), keyEquivalent: ""),
            ImageMenuItem(title: "Reset Picture Size") { editor.setImageSize(nil, at: location) },
            .separator(),
        ]
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }
}

/// A menu item that runs a closure.
private final class ImageMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
