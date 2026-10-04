import AppKit

/// Connects AppKit's native find bar (NSTextFinder) to the whole document.
///
/// Because the document is split across one text view per page, a single text
/// view can't be the finder's client. This client exposes the shared text
/// storage and maps character ranges back to the page views that display them,
/// so match highlighting, incremental search and Replace All work across pages.
final class DocumentFindClient: NSObject, NSTextFinderClient {
    private unowned let editor: EditorController

    init(editor: EditorController) {
        self.editor = editor
        super.init()
    }

    private var layoutManager: NSLayoutManager { editor.layoutManager }

    // MARK: Content

    var string: String { editor.textStorage.string }
    var isSelectable: Bool { true }
    var isEditable: Bool { true }
    var allowsMultipleSelection: Bool { false }

    // MARK: Selection

    var firstSelectedRange: NSRange { editor.textView.selectedRange() }

    var selectedRanges: [NSValue] {
        get { editor.textView.selectedRanges }
        set { editor.textView.selectedRanges = newValue }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        editor.scrollRangeToVisible(range)
    }

    // MARK: Replacing

    func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
        editor.textView.shouldChangeText(inRanges: ranges, replacementStrings: strings)
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        editor.textStorage.replaceCharacters(in: range, with: string)
    }

    func didReplaceCharacters() {
        editor.textView.didChangeText()
    }

    // MARK: Geometry

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        let (textView, characters) = editor.textView(containingCharacterAt: index)
        outRange.pointee = characters
        return textView
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0,
              let container = layoutManager.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil),
              let textView = container.textView
        else { return nil }

        let origin = textView.textContainerOrigin
        var rects: [NSValue] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphs,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in
            rects.append(NSValue(rect: rect.offsetBy(dx: origin.x, dy: origin.y)))
        }
        return rects
    }

    var visibleCharacterRanges: [NSValue] {
        guard let pagesView = editor.pagesView else { return [] }
        var ranges: [NSValue] = []
        for textView in pagesView.allTextViews {
            let visible = textView.visibleRect
            guard !visible.isEmpty, let container = textView.textContainer else { continue }
            let origin = textView.textContainerOrigin
            let containerRect = visible.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
            guard glyphs.length > 0 else { continue }
            ranges.append(NSValue(range: layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)))
        }
        return ranges
    }

    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let textView = view as? NSTextView else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: textView.textContainerOrigin)
    }
}
