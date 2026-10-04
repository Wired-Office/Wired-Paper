import AppKit

/// One sheet of paper. Draws decorations (page color, watermark, header,
/// footer…) and hosts one transparent text view per column.
final class PageView: NSView {
    private(set) var index: Int
    private(set) var textViews: [PageTextView] = []
    private unowned let renderer: PageRenderer

    init(index: Int, geometry: PageGeometry, containers: [NSTextContainer], renderer: PageRenderer) {
        self.index = index
        self.renderer = renderer
        super.init(frame: NSRect(origin: .zero, size: geometry.paperSize))

        // Paper is always paper: keep page content in the light appearance so
        // selection, spelling and link colors read correctly in Dark Mode.
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 3.5
        layer?.shadowOffset = CGSize(width: 0, height: -1.5)

        for container in containers {
            let textView = PageTextView(frame: .zero, textContainer: container)
            textView.drawsBackground = false
            addSubview(textView)
            textViews.append(textView)
        }
        apply(geometry)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// The first column's text view.
    var textView: PageTextView { textViews[0] }

    func apply(_ geometry: PageGeometry, verticalOffset: CGFloat = 0) {
        setFrameSize(geometry.paperSize)
        let columns = geometry.columnRects()
        for (column, textView) in textViews.enumerated() {
            let rect = columns[min(column, columns.count - 1)]
            // Each text view covers its share of the sheet so clicks in the
            // margins and gutters land in the nearest column.
            let left = column == 0 ? 0 : (columns[column - 1].maxX + rect.minX) / 2
            let right = column == textViews.count - 1 ? bounds.width : (rect.maxX + columns[min(column + 1, columns.count - 1)].minX) / 2
            textView.frame = NSRect(x: left, y: 0, width: max(right - left, 1), height: bounds.height)
            textView.containerOffset = NSPoint(x: rect.minX - left, y: rect.minY + verticalOffset)
        }
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        renderer.drawBackground(page: index, in: bounds)
        renderer.drawForeground(page: index, in: bounds)
    }
}

/// The scrollable document: pages stacked vertically (or in a grid for the
/// multiple-page view) on a canvas. Pages come and go as the engine paginates.
final class PagesView: NSView {
    static let pageGap: CGFloat = 28
    static let verticalPadding: CGFloat = 36
    static let horizontalPadding: CGFloat = 40

    let engine: PaginationEngine
    let renderer: PageRenderer
    private(set) var pages: [PageView] = []

    /// Called for every new page's text views so the editor can configure them.
    var configureTextView: ((PageTextView) -> Void)?
    var onPageCountChange: ((Int) -> Void)?

    /// 1 for the normal layout; 2+ shows pages side by side.
    var pagesPerRow = 1 {
        didSet { if pagesPerRow != oldValue { layoutPages() } }
    }

    init(engine: PaginationEngine, renderer: PageRenderer) {
        self.engine = engine
        self.renderer = renderer
        super.init(frame: .zero)

        engine.onPageAdded = { [unowned self] index in pageAdded(index) }
        engine.onPageRemoved = { [unowned self] index in pageRemoved(index) }
        engine.onGeometryChanged = { [unowned self] in geometryChanged() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    var allTextViews: [PageTextView] { pages.flatMap(\.textViews) }

    func textView(for container: NSTextContainer) -> PageTextView? {
        guard let page = engine.page(of: container), page < pages.count else { return nil }
        return pages[page].textViews.first { $0.textContainer === container }
    }

    private func pageAdded(_ index: Int) {
        let page = PageView(index: index, geometry: engine.geometry, containers: engine.containers(onPage: index), renderer: renderer)
        page.textViews.forEach { configureTextView?($0) }
        pages.append(page)
        addSubview(page)
        layoutPages()
        onPageCountChange?(pages.count)
    }

    private func pageRemoved(_ index: Int) {
        guard index < pages.count else { return }
        let page = pages[index]
        if let window, let responder = window.firstResponder as? PageTextView, page.textViews.contains(responder) {
            let fallback = index > 0 ? pages[index - 1].textViews.last : pages.first(where: { $0 !== page })?.textView
            window.makeFirstResponder(fallback)
        }
        pages.remove(at: index)
        page.removeFromSuperview()
        layoutPages()
        onPageCountChange?(pages.count)
    }

    private func geometryChanged() {
        renderer.geometry = engine.geometry
        refreshPages()
        layoutPages()
    }

    /// Re-applies geometry and vertical offsets and redraws decorations.
    func refreshPages() {
        for page in pages {
            page.apply(engine.geometry, verticalOffset: engine.verticalOffsets[page.index] ?? 0)
        }
    }

    private func layoutPages() {
        let paper = engine.geometry.paperSize
        let perRow = max(pagesPerRow, 1)
        let rows = Int(ceil(Double(max(pages.count, 1)) / Double(perRow)))
        let columns = min(perRow, max(pages.count, 1))
        let width = Self.horizontalPadding * 2 + CGFloat(columns) * paper.width + CGFloat(columns - 1) * Self.pageGap
        let height = Self.verticalPadding * 2 + CGFloat(rows) * paper.height + CGFloat(max(rows - 1, 0)) * Self.pageGap
        setFrameSize(NSSize(width: width, height: height))
        for (index, page) in pages.enumerated() {
            let row = index / perRow
            let column = index % perRow
            page.setFrameOrigin(NSPoint(
                x: Self.horizontalPadding + CGFloat(column) * (paper.width + Self.pageGap),
                y: Self.verticalPadding + CGFloat(row) * (paper.height + Self.pageGap)
            ))
        }
    }

    func frameOfPage(_ index: Int) -> NSRect? {
        index < pages.count ? pages[index].frame : nil
    }
}
