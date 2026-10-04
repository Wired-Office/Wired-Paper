import AppKit

/// Draws everything on a sheet that isn't body text: page color, watermark,
/// border, headers and footers with fields, column separators, line numbers,
/// change bars and footnotes. Shared by the on-screen pages and printing so
/// both look the same.
final class PageRenderer {
    var geometry: PageGeometry
    var decoration = PageDecoration()
    var headerFooter = HeaderFooterSettings()
    var fields = FieldValues()
    var markupMode: MarkupMode = .all
    var showChangeBars = false
    var drawsPageColor = true
    weak var engine: PaginationEngine?
    /// Draws the footnotes for a page into the given rect (bottom of the text area).
    var footnoteDrawer: ((Int, CGRect) -> Void)?
    /// Height of footnotes on a page (so the drawer gets the right rect).
    var footnoteHeight: ((Int) -> CGFloat)?

    private var lineCountCache: (generation: Int, starts: [Int: Int])?

    init(geometry: PageGeometry) {
        self.geometry = geometry
    }

    var pageCount: Int { max(engine?.pageCount ?? 1, 1) }

    // MARK: Behind the text

    func drawBackground(page: Int, in pageRect: CGRect) {
        if drawsPageColor {
            decoration.pageColor.setFill()
            pageRect.fill()
        }
        if let watermark = decoration.watermark, !watermark.text.isEmpty {
            drawWatermark(watermark, in: pageRect)
        }
        if let border = decoration.border {
            drawBorder(border, in: pageRect)
        }
    }

    private func drawWatermark(_ watermark: WatermarkSettings, in pageRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let diagonal = hypot(pageRect.width, pageRect.height)
        let span = watermark.diagonal ? diagonal * 0.7 : pageRect.width * 0.75
        let color = (NSColor(hex: watermark.colorHex) ?? .gray).withAlphaComponent(watermark.opacity)
        var fontSize: CGFloat = 200
        var attributes: [NSAttributedString.Key: Any] = [:]
        var size = CGSize.zero
        repeat {
            attributes = [.font: FontResolver.font(family: watermark.fontFamily, size: fontSize, bold: true), .foregroundColor: color]
            size = (watermark.text as NSString).size(withAttributes: attributes)
            fontSize -= 6
        } while size.width > span && fontSize > 12

        context.saveGState()
        context.translateBy(x: pageRect.midX, y: pageRect.midY)
        if watermark.diagonal {
            // Flipped coordinates: a negative angle rises to the right.
            context.rotate(by: -atan2(pageRect.height, pageRect.width))
        }
        (watermark.text as NSString).draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
        context.restoreGState()
    }

    private func drawBorder(_ border: PageBorderSettings, in pageRect: CGRect) {
        let rect = pageRect.insetBy(dx: border.inset, dy: border.inset)
        let color = NSColor(hex: border.colorHex) ?? .darkGray
        color.setStroke()
        func stroke(_ r: CGRect, width: CGFloat, dash: [CGFloat]? = nil) {
            let path = NSBezierPath(rect: r)
            path.lineWidth = width
            if let dash { path.setLineDash(dash, count: dash.count, phase: 0) }
            path.stroke()
        }
        switch border.style {
        case .single: stroke(rect, width: border.width)
        case .thick: stroke(rect, width: max(border.width * 3, 3))
        case .double:
            stroke(rect, width: border.width)
            stroke(rect.insetBy(dx: border.width * 3, dy: border.width * 3), width: border.width)
        case .dashed: stroke(rect, width: border.width, dash: [6, 4])
        case .dotted: stroke(rect, width: border.width, dash: [1, 3])
        }
    }

    // MARK: Around the text

    func drawForeground(page: Int, in pageRect: CGRect) {
        drawHeaderFooter(page: page, in: pageRect)
        if decoration.columnSeparator && geometry.columns > 1 {
            drawColumnSeparators(in: pageRect)
        }
        if let lineNumbers = decoration.lineNumbers {
            drawLineNumbers(lineNumbers, page: page, in: pageRect)
        }
        if showChangeBars {
            drawChangeBars(page: page, in: pageRect)
        }
        if let footnoteDrawer, let height = footnoteHeight?(page), height > 0 {
            let area = geometry.textArea.offsetBy(dx: pageRect.minX, dy: pageRect.minY)
            footnoteDrawer(page, CGRect(x: area.minX, y: area.maxY - height, width: area.width, height: height))
        }
    }

    private func headerAttributes(alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: FontResolver.font(family: fields.bodyFontFamily, size: headerFooter.fontSize),
            .foregroundColor: NSColor(hex: headerFooter.colorHex) ?? .darkGray,
            .paragraphStyle: paragraph,
        ]
    }

    private func drawHeaderFooter(page: Int, in pageRect: CGRect) {
        guard !headerFooter.isEmpty else { return }
        var values = fields
        values.startingPageNumber = headerFooter.startingPageNumber
        values.numberFormat = headerFooter.numberFormat
        let area = geometry.textArea
        let lineHeight = headerFooter.fontSize * 1.4

        for isHeader in [true, false] {
            let content = headerFooter.content(forPage: page, header: isHeader)
            guard !content.isEmpty else { continue }
            let y = isHeader
                ? pageRect.minY + headerFooter.headerDistance
                : pageRect.maxY - headerFooter.footerDistance - lineHeight
            let rect = CGRect(x: pageRect.minX + area.minX, y: y, width: area.width, height: lineHeight)
            let slots: [(String, NSTextAlignment)] = [(content.left, .left), (content.center, .center), (content.right, .right)]
            for (template, alignment) in slots where !template.isEmpty {
                let text = values.expand(template, pageIndex: page, pageCount: pageCount)
                (text as NSString).draw(in: rect, withAttributes: headerAttributes(alignment: alignment))
            }
            if headerFooter.showSeparators {
                (NSColor(hex: headerFooter.colorHex) ?? .gray).withAlphaComponent(0.5).setFill()
                let lineY = isHeader ? rect.maxY + 3 : rect.minY - 4
                CGRect(x: rect.minX, y: lineY, width: rect.width, height: 0.5).fill()
            }
        }
    }

    private func drawColumnSeparators(in pageRect: CGRect) {
        let columns = geometry.columnRects()
        NSColor(white: 0.55, alpha: 1).setFill()
        for index in 1..<columns.count {
            let x = pageRect.minX + (columns[index - 1].maxX + columns[index].minX) / 2
            CGRect(x: x, y: pageRect.minY + columns[index].minY, width: 0.5, height: columns[index].height).fill()
        }
    }

    // MARK: Line numbers

    private func drawLineNumbers(_ settings: LineNumberSettings, page: Int, in pageRect: CGRect) {
        guard let engine else { return }
        let layoutManager = engine.layoutManager
        var number = settings.restartEachPage ? 1 : lineNumberStart(for: page)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: NSColor(white: 0.45, alpha: 1),
        ]
        let columnRects = geometry.columnRects()
        for (column, container) in engine.containers(onPage: page).enumerated() {
            let glyphs = layoutManager.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            let columnRect = columnRects[min(column, columnRects.count - 1)]
            let offset = engine.verticalOffsets[page] ?? 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                defer { number += 1 }
                guard number % settings.countBy == 0 else { return }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                let point = NSPoint(
                    x: pageRect.minX + columnRect.minX - settings.distance - size.width,
                    y: pageRect.minY + columnRect.minY + offset + rect.minY + (rect.height - size.height) / 2
                )
                label.draw(at: point, withAttributes: attributes)
            }
        }
    }

    private func lineNumberStart(for page: Int) -> Int {
        guard let engine else { return 1 }
        if let cache = lineCountCache, cache.generation == engine.layoutGeneration, let start = cache.starts[page] {
            return start
        }
        var starts: [Int: Int] = [:]
        var running = 1
        for index in 0..<engine.pageCount {
            starts[index] = running
            for container in engine.containers(onPage: index) {
                let glyphs = engine.layoutManager.glyphRange(for: container)
                guard glyphs.length > 0 else { continue }
                engine.layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in running += 1 }
            }
        }
        lineCountCache = (engine.layoutGeneration, starts)
        return starts[page] ?? 1
    }

    // MARK: Change bars (Simple Markup)

    private func drawChangeBars(page: Int, in pageRect: CGRect) {
        guard let engine, let storage = engine.layoutManager.textStorage else { return }
        let layoutManager = engine.layoutManager
        let range = engine.characterRange(onPage: page)
        guard range.length > 0 else { return }
        NSColor.systemRed.withAlphaComponent(0.8).setFill()
        let columnRects = geometry.columnRects()
        storage.enumerateAttribute(.wpRevision, in: range) { value, run, _ in
            guard value != nil else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            var glyph = glyphs.location
            while glyph < NSMaxRange(glyphs) {
                var lineRange = NSRange()
                let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
                if let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil),
                   let column = engine.containers(onPage: page).firstIndex(where: { $0 === container }) {
                    let columnRect = columnRects[min(column, columnRects.count - 1)]
                    CGRect(x: pageRect.minX + columnRect.minX - 10, y: pageRect.minY + columnRect.minY + line.minY, width: 2, height: line.height).fill()
                }
                glyph = max(NSMaxRange(lineRange), glyph + 1)
            }
        }
    }
}
