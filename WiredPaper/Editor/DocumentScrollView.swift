import AppKit

/// Keeps the pages horizontally centered when the window is wider than the page.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let documentFrame = documentView.frame
        if rect.width > documentFrame.width {
            rect.origin.x = documentFrame.minX - (rect.width - documentFrame.width) / 2
        }
        return rect
    }
}

/// Ruler without AppKit's legacy formatting accessory (the format bar covers it),
/// measured from the left text margin like a conventional word processor.
final class DocumentRulerView: NSRulerView {
    override var accessoryView: NSView? {
        get { nil }
        set { }
    }

    override var reservedThicknessForAccessoryView: CGFloat {
        get { 0 }
        set { }
    }
}

/// The scroll view that hosts the pages, the ruler and the find bar.
final class DocumentScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clip = CenteringClipView()
        clip.drawsBackground = true
        contentView = clip

        backgroundColor = Theme.canvas
        drawsBackground = true
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay

        allowsMagnification = true
        minMagnification = EditorController.minZoom
        maxMagnification = EditorController.maxZoom

        Self.rulerViewClass = DocumentRulerView.self
        hasHorizontalRuler = true
        hasVerticalRuler = false
        findBarPosition = .aboveContent
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyRulerUnits(_ unit: MeasurementUnit) {
        horizontalRulerView?.measurementUnits = unit.rulerUnitName
    }
}
