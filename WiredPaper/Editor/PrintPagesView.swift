import AppKit

/// Everything needed to paginate and draw a document off screen.
struct PrintConfiguration {
    var text: NSAttributedString
    var geometry: PageGeometry
    var decoration = PageDecoration()
    var headerFooter = HeaderFooterSettings()
    var fields = FieldValues()
    var markupMode: MarkupMode = .none
    var showHiddenText = false
    var printBackgrounds = true
    var verticalAlignment: VerticalPageAlignment = .top
    /// Revision id → author, for colored markup.
    var revisionAuthors: [String: String] = [:]
    /// Supplies footnote reserve heights and drawing for a laid-out copy.
    var footnotes: FootnoteLayout?
    /// Note numbers, caption numbers and other live field values.
    var liveValues = LiveValues()

    init(text: NSAttributedString, pageSetup: PageSetup) {
        self.text = text
        self.geometry = PageGeometry(setup: pageSetup)
    }
}

/// An off-screen, paginated rendering of a document used for printing, PDF
/// export, page images and template thumbnails. It lays out its own copy of
/// the text with the same engine and renderer as the on-screen pages.
final class PrintPagesView: NSView {
    private(set) var configuration: PrintConfiguration
    private let maxPages: Int
    private var storage = NSTextStorage()
    private var layoutManager = WPLayoutManager()
    private var engine: PaginationEngine
    private var renderer: PageRenderer

    var pageCount: Int { engine.pageCount }

    convenience init(text: NSAttributedString, pageSetup: PageSetup, maxPages: Int = 5000) {
        self.init(configuration: PrintConfiguration(text: text, pageSetup: pageSetup), maxPages: maxPages)
    }

    init(configuration: PrintConfiguration, maxPages: Int = 5000) {
        self.configuration = configuration
        self.maxPages = maxPages
        let manager = WPLayoutManager()
        layoutManager = manager
        engine = PaginationEngine(layoutManager: manager, geometry: configuration.geometry)
        renderer = PageRenderer(geometry: configuration.geometry)
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        build()
    }

    /// Re-paginates with new options (used by the print panel's live preview).
    func reconfigure(_ configuration: PrintConfiguration) {
        self.configuration = configuration
        build()
        needsDisplay = true
    }

    private func build() {
        storage = NSTextStorage(attributedString: configuration.text)
        layoutManager = WPLayoutManager()
        engine = PaginationEngine(layoutManager: layoutManager, geometry: configuration.geometry)
        renderer = PageRenderer(geometry: configuration.geometry)

        layoutManager.allowsNonContiguousLayout = false
        layoutManager.usesDefaultHyphenation = configuration.decoration.hyphenation
        layoutManager.fieldValues = configuration.fields
        configuration.liveValues.apply(to: layoutManager)
        storage.addLayoutManager(layoutManager)
        AttachmentNormalizer.normalize(storage, maxSize: configuration.geometry.maxAttachmentSize)
        if configuration.markupMode == .all {
            RevisionMarkup.applyPrintMarkup(to: storage, mode: configuration.markupMode, authors: configuration.revisionAuthors)
        }

        engine.autoPaginate = false
        engine.policy.markupMode = configuration.markupMode
        engine.policy.showHiddenText = configuration.showHiddenText
        engine.widowControl = configuration.decoration.widowControl
        engine.verticalAlignment = configuration.verticalAlignment
        if let footnotes = configuration.footnotes {
            footnotes.attach(to: engine)
            engine.reserveProvider = { [weak engine] page in
                guard let engine else { return 0 }
                return footnotes.reserve(forPage: page, engine: engine)
            }
        }
        engine.paginateAll(maxPages: maxPages)

        renderer.engine = engine
        renderer.decoration = configuration.decoration
        renderer.headerFooter = configuration.headerFooter
        renderer.fields = configuration.fields
        renderer.markupMode = configuration.markupMode
        renderer.showChangeBars = configuration.markupMode == .simple
        renderer.drawsPageColor = configuration.printBackgrounds
        if let footnotes = configuration.footnotes {
            renderer.footnoteHeight = { [weak engine] page in
                guard let engine else { return 0 }
                return footnotes.reserve(forPage: page, engine: engine)
            }
            renderer.footnoteDrawer = { [weak engine] page, rect in
                guard let engine else { return }
                footnotes.draw(page: page, in: rect, engine: engine)
            }
        }

        let paper = configuration.geometry.paperSize
        setFrameSize(NSSize(width: paper.width, height: paper.height * CGFloat(max(pageCount, 1))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    // MARK: Pagination for NSPrintOperation

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(pageCount, 1))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let paper = configuration.geometry.paperSize
        return NSRect(x: 0, y: CGFloat(page - 1) * paper.height, width: paper.width, height: paper.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<pageCount {
            let pageRect = rectForPage(index + 1)
            guard pageRect.intersects(dirtyRect) else { continue }
            drawPage(at: index, in: pageRect)
        }
    }

    private func drawPage(at index: Int, in pageRect: NSRect) {
        if !configuration.printBackgrounds && NSGraphicsContext.currentContextDrawingToScreen() {
            NSColor.white.setFill()
            pageRect.fill()
        }
        renderer.drawBackground(page: index, in: pageRect)
        let columns = configuration.geometry.columnRects()
        let offset = engine.verticalOffsets[index] ?? 0
        for (column, container) in engine.containers(onPage: index).enumerated() {
            let glyphs = layoutManager.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            let rect = columns[min(column, columns.count - 1)]
            let origin = NSPoint(x: pageRect.minX + rect.minX, y: pageRect.minY + rect.minY + offset)
            layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        }
        renderer.drawForeground(page: index, in: pageRect)
    }

    /// Renders one page to an image `width` points wide.
    func pageImage(_ index: Int = 0, width: CGFloat, scale: CGFloat = 1) -> NSImage {
        let paper = configuration.geometry.paperSize
        let factor = width / paper.width
        let size = NSSize(width: width, height: (paper.height * factor).rounded())
        return NSImage(size: size, flipped: true) { [self] rect in
            NSColor.white.setFill()
            rect.fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: factor, y: factor)
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                drawPage(at: index, in: NSRect(origin: .zero, size: paper))
            }
            context.restoreGState()
            return true
        }
    }

    func firstPageImage(width: CGFloat) -> NSImage {
        pageImage(0, width: width)
    }
}
