import AppKit

/// Renders embedded objects to images. The image is stored as the attachment's
/// file (so other apps show it) and displayed by TextKit; the object's JSON
/// keeps it editable.
enum ObjectRenderer {
    static func image(for object: DocumentObject) -> NSImage? {
        switch object.kind {
        case .chart: object.chart.map(ChartRenderer.image)
        case .equation: object.equation.map(MathRenderer.image)
        case .shape, .wordArt: object.shape.map(ShapeRenderer.image)
        case .diagram: object.diagram.map(DiagramRenderer.image)
        case .spreadsheet: object.sheet.map(SpreadsheetRenderer.image)
        case .drawing: object.drawing.map(DrawingRenderer.image)
        case .signature: object.signature.map(SignatureRenderer.image)
        default: nil
        }
    }

    /// Draws with a flipped (top-left origin) context at 2× for crisp output.
    static func draw(size: CGSize, _ body: @escaping (CGContext) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                body(context)
            }
            return true
        }
        // Rasterize now so the stored PNG matches what's shown.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}

// MARK: - Shapes, text boxes, WordArt, icons

enum ShapeRenderer {
    static func path(for kind: ShapeKind, in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let midX = rect.midX, midY = rect.midY
        func polygon(_ points: [CGPoint]) {
            path.addLines(between: points)
            path.closeSubpath()
        }
        func regular(_ sides: Int, rotation: CGFloat = -.pi / 2) {
            let radius = min(rect.width, rect.height) / 2
            polygon((0..<sides).map { i in
                let angle = rotation + CGFloat(i) * 2 * .pi / CGFloat(sides)
                return CGPoint(x: midX + cos(angle) * rect.width / 2 * (rect.width / 2 > 0 ? 1 : 0) * (radius > 0 ? 1 : 0), y: midY + sin(angle) * rect.height / 2)
            })
        }
        switch kind {
        case .rectangle, .textBox, .wordArt, .icon:
            path.addRect(rect)
        case .roundedRectangle:
            path.addRoundedRect(in: rect, cornerWidth: min(cornerRadius, rect.width / 2), cornerHeight: min(cornerRadius, rect.height / 2))
        case .ellipse:
            path.addEllipse(in: rect)
        case .triangle:
            polygon([CGPoint(x: midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        case .diamond:
            polygon([CGPoint(x: midX, y: rect.minY), CGPoint(x: rect.maxX, y: midY), CGPoint(x: midX, y: rect.maxY), CGPoint(x: rect.minX, y: midY)])
        case .pentagon:
            regular(5)
        case .hexagon:
            regular(6, rotation: 0)
        case .star:
            let points = (0..<10).map { i -> CGPoint in
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let scale: CGFloat = i % 2 == 0 ? 1 : 0.42
                return CGPoint(x: midX + cos(angle) * rect.width / 2 * scale, y: midY + sin(angle) * rect.height / 2 * scale)
            }
            polygon(points)
        case .arrowRight, .arrowLeft, .arrowUp, .arrowDown:
            // Build a right arrow and rotate it for the other directions.
            let w = (kind == .arrowUp || kind == .arrowDown) ? rect.height : rect.width
            let h = (kind == .arrowUp || kind == .arrowDown) ? rect.width : rect.height
            let head = min(w * 0.4, h)
            let shaft = h * 0.4
            let arrow = CGMutablePath()
            arrow.addLines(between: [
                CGPoint(x: -w / 2, y: -shaft / 2), CGPoint(x: w / 2 - head, y: -shaft / 2), CGPoint(x: w / 2 - head, y: -h / 2),
                CGPoint(x: w / 2, y: 0), CGPoint(x: w / 2 - head, y: h / 2), CGPoint(x: w / 2 - head, y: shaft / 2), CGPoint(x: -w / 2, y: shaft / 2),
            ])
            arrow.closeSubpath()
            let angle: CGFloat = kind == .arrowRight ? 0 : kind == .arrowLeft ? .pi : kind == .arrowDown ? .pi / 2 : -.pi / 2
            var transform = CGAffineTransform(translationX: midX, y: midY).rotated(by: angle)
            path.addPath(arrow, transform: transform)
            transform = .identity
        case .line:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .arrowLine:
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: midY))
            path.move(to: CGPoint(x: rect.maxX - 14, y: midY - 8))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX - 14, y: midY + 8))
        case .callout:
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.78)
            path.addRoundedRect(in: body, cornerWidth: 10, cornerHeight: 10)
            polygon([CGPoint(x: rect.minX + rect.width * 0.2, y: body.maxY - 1), CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY), CGPoint(x: rect.minX + rect.width * 0.38, y: body.maxY - 1)])
        }
        return path
    }

    static func image(_ spec: ShapeSpec) -> NSImage {
        let margin: CGFloat = spec.shadow ? 10 : 3
        let rotation = spec.rotation * .pi / 180
        // Canvas large enough for the rotated shape.
        let w = spec.width, h = spec.height
        let rotatedWidth = abs(w * cos(rotation)) + abs(h * sin(rotation))
        let rotatedHeight = abs(w * sin(rotation)) + abs(h * cos(rotation))
        let size = CGSize(width: ceil(rotatedWidth + margin * 2), height: ceil(rotatedHeight + margin * 2))

        return ObjectRenderer.draw(size: size) { context in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: rotation)
            context.scaleBy(x: spec.flipHorizontal ? -1 : 1, y: spec.flipVertical ? -1 : 1)
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

            if spec.kind == .wordArt {
                drawWordArt(spec, in: rect, context: context)
                return
            }
            if spec.kind == .icon {
                drawIcon(spec, in: rect)
                return
            }

            let shape = path(for: spec.kind, in: rect.insetBy(dx: spec.strokeWidth / 2, dy: spec.strokeWidth / 2), cornerRadius: spec.cornerRadius)
            if spec.shadow {
                context.setShadow(offset: CGSize(width: 2, height: 3), blur: 6, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            }
            let isLine = spec.kind == .line || spec.kind == .arrowLine
            if !isLine, let fill = spec.fillHex.flatMap(NSColor.init(hex:)) {
                context.addPath(shape)
                context.setFillColor(fill.cgColor)
                context.fillPath()
            }
            context.setShadow(offset: .zero, blur: 0, color: nil)
            if let stroke = spec.strokeHex.flatMap(NSColor.init(hex:)), spec.strokeWidth > 0 {
                context.addPath(shape)
                context.setStrokeColor(stroke.cgColor)
                context.setLineWidth(spec.strokeWidth)
                context.setLineJoin(.round)
                context.setLineCap(.round)
                context.strokePath()
            }
            if !spec.text.isEmpty && !isLine {
                // Undo the flip for legible text.
                context.saveGState()
                context.scaleBy(x: spec.flipHorizontal ? -1 : 1, y: spec.flipVertical ? -1 : 1)
                drawText(spec, in: rect.insetBy(dx: 10, dy: 8), alignment: spec.kind == .textBox ? .left : .center, vertical: spec.kind != .textBox)
                context.restoreGState()
            }
        }
    }

    private static func textAttributes(_ spec: ShapeSpec, alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        return [
            .font: FontResolver.font(family: spec.fontFamily, size: spec.fontSize, bold: spec.bold),
            .foregroundColor: NSColor(hex: spec.textColorHex) ?? .black,
            .paragraphStyle: paragraph,
        ]
    }

    private static func drawText(_ spec: ShapeSpec, in rect: CGRect, alignment: NSTextAlignment, vertical: Bool) {
        let text = NSAttributedString(string: spec.text, attributes: textAttributes(spec, alignment: alignment))
        let bounds = text.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let y = vertical ? rect.midY - bounds.height / 2 : rect.minY
        text.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: min(bounds.height, rect.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func drawIcon(_ spec: ShapeSpec, in rect: CGRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: min(rect.width, rect.height) * 0.8, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: spec.symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let tint = spec.fillHex.flatMap(NSColor.init(hex:)) ?? Theme.headingInk
        let tinted = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            tint.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        let scale = min(rect.width / tinted.size.width, rect.height / tinted.size.height)
        let size = CGSize(width: tinted.size.width * scale, height: tinted.size.height * scale)
        tinted.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func drawWordArt(_ spec: ShapeSpec, in rect: CGRect, context: CGContext) {
        let text = spec.text.isEmpty ? "Your Text" : spec.text
        var fontSize = spec.fontSize
        var attributes: [NSAttributedString.Key: Any] = [:]
        var size = CGSize.zero
        repeat {
            attributes = [.font: FontResolver.font(family: spec.fontFamily, size: fontSize, bold: true)]
            size = (text as NSString).size(withAttributes: attributes)
            fontSize -= 2
        } while (size.width > rect.width || size.height > rect.height) && fontSize > 8
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        let base = NSColor(hex: spec.textColorHex) ?? .black
        let accent = spec.fillHex.flatMap(NSColor.init(hex:)) ?? Theme.headingInk

        switch spec.wordArtStyle {
        case .gradient:
            // Clip to the glyphs and fill with a gradient.
            guard let mask = textMask(text, attributes: attributes, size: size) else { return }
            context.saveGState()
            context.clip(to: CGRect(origin: origin, size: size), mask: mask)
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [accent.cgColor, base.cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: origin.x, y: origin.y), end: CGPoint(x: origin.x, y: origin.y + size.height), options: [])
            context.restoreGState()
        case .outline:
            var outline = attributes
            outline[.strokeWidth] = 3.0
            outline[.strokeColor] = accent
            (text as NSString).draw(at: origin, withAttributes: outline)
        case .shadow:
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 3, height: -3)
            shadow.shadowBlurRadius = 4
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            var shadowed = attributes
            shadowed[.shadow] = shadow
            shadowed[.foregroundColor] = accent
            (text as NSString).draw(at: origin, withAttributes: shadowed)
        case .neon:
            let glow = NSShadow()
            glow.shadowOffset = .zero
            glow.shadowBlurRadius = 10
            glow.shadowColor = accent
            var neon = attributes
            neon[.shadow] = glow
            neon[.foregroundColor] = NSColor.white
            neon[.strokeWidth] = -2.0
            neon[.strokeColor] = accent
            (text as NSString).draw(at: origin, withAttributes: neon)
        case .retro:
            var back = attributes
            back[.foregroundColor] = accent
            (text as NSString).draw(at: CGPoint(x: origin.x + 3, y: origin.y + 3), withAttributes: back)
            var front = attributes
            front[.foregroundColor] = base
            front[.strokeWidth] = -2.0
            front[.strokeColor] = NSColor.white
            (text as NSString).draw(at: origin, withAttributes: front)
        }
    }

    private static func textMask(_ text: String, attributes: [NSAttributedString.Key: Any], size: CGSize) -> CGImage? {
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        var white = attributes
        white[.foregroundColor] = NSColor.white
        (text as NSString).draw(at: .zero, withAttributes: white)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        // Flip vertically to match the flipped destination context.
        guard let flipped = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        flipped.translateBy(x: 0, y: CGFloat(image.height))
        flipped.scaleBy(x: 1, y: -1)
        flipped.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return flipped.makeImage()
    }
}

// MARK: - Diagrams

enum DiagramRenderer {
    static func image(_ spec: DiagramSpec) -> NSImage {
        let size = CGSize(width: spec.width, height: spec.height)
        let color = NSColor(hex: spec.colorHex) ?? Theme.headingInk
        return ObjectRenderer.draw(size: size) { context in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let top = spec.items.filter { $0.level == 0 }
            switch spec.type {
            case .process: process(top, in: bounds, color: color, context: context)
            case .timeline: timeline(top, in: bounds, color: color, context: context)
            case .cycle: cycle(top, in: bounds, color: color, context: context)
            case .hierarchy: hierarchy(spec.items, in: bounds, color: color, context: context)
            case .list: list(spec.items, in: bounds, color: color)
            case .pyramid: pyramid(top, in: bounds, color: color)
            case .flowchart: flowchart(top, in: bounds, color: color, context: context)
            case .venn: venn(top, in: bounds, color: color)
            }
        }
    }

    private static func shade(_ color: NSColor, _ index: Int, of count: Int) -> NSColor {
        let fraction = count <= 1 ? 0 : CGFloat(index) / CGFloat(count - 1) * 0.55
        return color.blended(withFraction: fraction, of: .white) ?? color
    }

    private static func label(_ text: String, in rect: CGRect, color: NSColor = .white, size: CGFloat = 12, bold: Bool = true) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: FontResolver.font(family: "Helvetica Neue", size: size, bold: bold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: rect.width - 8, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        string.draw(with: CGRect(x: rect.minX + 4, y: rect.midY - bounds.height / 2, width: rect.width - 8, height: bounds.height), options: [.usesLineFragmentOrigin])
    }

    private static func textColor(on color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.6 ? .black : .white
    }

    private static func box(_ rect: CGRect, fill: NSColor, text: String, radius: CGFloat = 8) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        label(text, in: rect, color: textColor(on: fill))
    }

    private static func arrow(from start: CGPoint, to end: CGPoint, color: NSColor, context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(2)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 8
        context.move(to: end)
        context.addLine(to: CGPoint(x: end.x - head * cos(angle - .pi / 7), y: end.y - head * sin(angle - .pi / 7)))
        context.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 7), y: end.y - head * sin(angle + .pi / 7)))
        context.closePath()
        context.fillPath()
    }

    private static func process(_ items: [DiagramItem], in bounds: CGRect, color: NSColor, context: CGContext) {
        guard !items.isEmpty else { return }
        let gap: CGFloat = 26
        let width = (bounds.width - gap * CGFloat(items.count - 1)) / CGFloat(items.count)
        let height = min(bounds.height, 90)
        for (index, item) in items.enumerated() {
            let rect = CGRect(x: bounds.minX + CGFloat(index) * (width + gap), y: bounds.midY - height / 2, width: width, height: height)
            box(rect, fill: shade(color, index, of: items.count), text: item.text)
            if index < items.count - 1 {
                arrow(from: CGPoint(x: rect.maxX + 4, y: rect.midY), to: CGPoint(x: rect.maxX + gap - 4, y: rect.midY), color: color, context: context)
            }
        }
    }

    private static func timeline(_ items: [DiagramItem], in bounds: CGRect, color: NSColor, context: CGContext) {
        guard !items.isEmpty else { return }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(3)
        context.move(to: CGPoint(x: bounds.minX, y: bounds.midY))
        context.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
        context.strokePath()
        let step = bounds.width / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let x = bounds.minX + step * (CGFloat(index) + 0.5)
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: x - 7, y: bounds.midY - 7, width: 14, height: 14)).fill()
            let above = index % 2 == 0
            let rect = CGRect(x: x - step / 2, y: above ? bounds.midY - 58 : bounds.midY + 14, width: step, height: 44)
            label(item.text, in: rect, color: .black, size: 11.5, bold: false)
        }
    }

    private static func cycle(_ items: [DiagramItem], in bounds: CGRect, color: NSColor, context: CGContext) {
        guard !items.isEmpty else { return }
        let radius = min(bounds.width, bounds.height) / 2 - 34
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let nodeSize = CGSize(width: min(110, radius * 1.1), height: 44)
        let positions = items.indices.map { index -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(items.count)
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        for index in items.indices where items.count > 1 {
            let a = positions[index], b = positions[(index + 1) % items.count]
            let inset: CGFloat = 0.28
            arrow(from: CGPoint(x: a.x + (b.x - a.x) * inset, y: a.y + (b.y - a.y) * inset),
                  to: CGPoint(x: a.x + (b.x - a.x) * (1 - inset), y: a.y + (b.y - a.y) * (1 - inset)), color: color.withAlphaComponent(0.6), context: context)
        }
        for (index, item) in items.enumerated() {
            let p = positions[index]
            box(CGRect(x: p.x - nodeSize.width / 2, y: p.y - nodeSize.height / 2, width: nodeSize.width, height: nodeSize.height),
                fill: shade(color, index, of: items.count), text: item.text, radius: 22)
        }
    }

    private static func hierarchy(_ items: [DiagramItem], in bounds: CGRect, color: NSColor, context: CGContext) {
        guard !items.isEmpty else { return }
        // Group items by depth, keeping each child's parent.
        var levels: [[(item: DiagramItem, parent: Int?)]] = []
        var lastAtLevel: [Int: Int] = [:]
        for item in items {
            let level = min(item.level, (levels.count))
            while levels.count <= level { levels.append([]) }
            let parent = level > 0 ? lastAtLevel[level - 1] : nil
            levels[level].append((item, parent))
            lastAtLevel[level] = levels[level].count - 1
        }
        let rowHeight = min(54, bounds.height / CGFloat(levels.count) - 18)
        var frames: [[CGRect]] = []
        for (depth, row) in levels.enumerated() {
            let width = min(140, (bounds.width - 12 * CGFloat(row.count - 1)) / CGFloat(max(row.count, 1)))
            let total = width * CGFloat(row.count) + 12 * CGFloat(row.count - 1)
            let y = bounds.minY + CGFloat(depth) * (bounds.height / CGFloat(levels.count))
            frames.append(row.indices.map { CGRect(x: bounds.midX - total / 2 + CGFloat($0) * (width + 12), y: y, width: width, height: rowHeight) })
        }
        context.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1.5)
        for depth in 1..<max(levels.count, 1) {
            for (index, entry) in levels[depth].enumerated() {
                guard let parent = entry.parent else { continue }
                let from = frames[depth - 1][parent], to = frames[depth][index]
                context.move(to: CGPoint(x: from.midX, y: from.maxY))
                context.addLine(to: CGPoint(x: from.midX, y: (from.maxY + to.minY) / 2))
                context.addLine(to: CGPoint(x: to.midX, y: (from.maxY + to.minY) / 2))
                context.addLine(to: CGPoint(x: to.midX, y: to.minY))
                context.strokePath()
            }
        }
        for (depth, row) in levels.enumerated() {
            for (index, entry) in row.enumerated() {
                box(frames[depth][index], fill: shade(color, depth, of: max(levels.count, 2)), text: entry.item.text, radius: 6)
            }
        }
    }

    private static func list(_ items: [DiagramItem], in bounds: CGRect, color: NSColor) {
        let top = items.filter { $0.level == 0 }
        guard !top.isEmpty else { return }
        let rowHeight = (bounds.height - 6 * CGFloat(top.count - 1)) / CGFloat(top.count)
        var index = 0
        for (row, item) in items.enumerated() where item.level == 0 {
            let y = bounds.minY + CGFloat(index) * (rowHeight + 6)
            let labelRect = CGRect(x: bounds.minX, y: y, width: bounds.width * 0.32, height: rowHeight)
            box(labelRect, fill: shade(color, index, of: top.count), text: item.text, radius: 6)
            let children = items[(row + 1)...].prefix { $0.level > 0 }.map(\.text)
            let detailRect = CGRect(x: labelRect.maxX + 6, y: y, width: bounds.width - labelRect.width - 6, height: rowHeight)
            (color.blended(withFraction: 0.85, of: .white) ?? color).setFill()
            NSBezierPath(roundedRect: detailRect, xRadius: 6, yRadius: 6).fill()
            label(children.map { "• " + $0 }.joined(separator: "\n"), in: detailRect, color: .black, size: 11, bold: false)
            index += 1
        }
    }

    private static func pyramid(_ items: [DiagramItem], in bounds: CGRect, color: NSColor) {
        guard !items.isEmpty else { return }
        let height = bounds.height / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let topWidth = bounds.width * CGFloat(index) / CGFloat(items.count)
            let bottomWidth = bounds.width * CGFloat(index + 1) / CGFloat(items.count)
            let y = bounds.minY + CGFloat(index) * height
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.midX - topWidth / 2, y: y))
            path.line(to: CGPoint(x: bounds.midX + topWidth / 2, y: y))
            path.line(to: CGPoint(x: bounds.midX + bottomWidth / 2, y: y + height - 2))
            path.line(to: CGPoint(x: bounds.midX - bottomWidth / 2, y: y + height - 2))
            path.close()
            let fill = shade(color, index, of: items.count)
            fill.setFill()
            path.fill()
            label(item.text, in: CGRect(x: bounds.minX, y: y, width: bounds.width, height: height), color: textColor(on: fill), size: 11.5)
        }
    }

    private static func flowchart(_ items: [DiagramItem], in bounds: CGRect, color: NSColor, context: CGContext) {
        guard !items.isEmpty else { return }
        let gap: CGFloat = 18
        let height = min(46, (bounds.height - gap * CGFloat(items.count - 1)) / CGFloat(items.count))
        let width = min(220, bounds.width * 0.6)
        for (index, item) in items.enumerated() {
            let rect = CGRect(x: bounds.midX - width / 2, y: bounds.minY + CGFloat(index) * (height + gap), width: width, height: height)
            let isTerminal = index == 0 || index == items.count - 1
            let isDecision = item.text.hasSuffix("?")
            let fill = shade(color, index, of: items.count)
            if isDecision {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.line(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.line(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.line(to: CGPoint(x: rect.minX, y: rect.midY))
                path.close()
                fill.setFill()
                path.fill()
                label(item.text, in: rect, color: textColor(on: fill), size: 11)
            } else {
                box(rect, fill: fill, text: item.text, radius: isTerminal ? height / 2 : 4)
            }
            if index < items.count - 1 {
                arrow(from: CGPoint(x: rect.midX, y: rect.maxY + 2), to: CGPoint(x: rect.midX, y: rect.maxY + gap - 2), color: color, context: context)
            }
        }
    }

    private static func venn(_ items: [DiagramItem], in bounds: CGRect, color: NSColor) {
        let count = min(max(items.count, 1), 4)
        let radius = min(bounds.height / 2, bounds.width / CGFloat(count + 1))
        let spacing = radius * 1.1
        let startX = bounds.midX - spacing * CGFloat(count - 1) / 2
        for index in 0..<count {
            let center = CGPoint(x: startX + CGFloat(index) * spacing, y: bounds.midY)
            shade(color, index, of: count).withAlphaComponent(0.45).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            if index < items.count {
                label(items[index].text, in: CGRect(x: center.x - radius * 0.8, y: center.y - 20, width: radius * 1.6, height: 40), color: .black, size: 12)
            }
        }
    }
}

// MARK: - Spreadsheet

enum SpreadsheetRenderer {
    static func evaluatedCells(_ spec: SpreadsheetSpec) -> [[String]] {
        let grid = FormulaGrid(cells: spec.cells)
        return spec.cells.enumerated().map { row, values in
            values.enumerated().map { column, raw in
                guard raw.hasPrefix("=") else { return raw }
                return grid.number(row, column, depth: 0).map(FormulaEngine.format) ?? "#ERROR"
            }
        }
    }

    static func image(_ spec: SpreadsheetSpec) -> NSImage {
        let values = evaluatedCells(spec)
        let rows = values.count, columns = values.map(\.count).max() ?? 1
        let rowHeight: CGFloat = 22
        let size = CGSize(width: spec.columnWidth * CGFloat(columns) + 1, height: rowHeight * CGFloat(rows) + 1)
        return ObjectRenderer.draw(size: size) { context in
            let font = NSFont.systemFont(ofSize: 11)
            let bold = NSFont.boldSystemFont(ofSize: 11)
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(x: CGFloat(column) * spec.columnWidth + 0.5, y: CGFloat(row) * rowHeight + 0.5, width: spec.columnWidth, height: rowHeight)
                    if spec.headerRow && row == 0 {
                        NSColor(srgbRed: 0.90, green: 0.95, blue: 0.96, alpha: 1).setFill()
                        rect.fill()
                    }
                    NSColor(white: 0.7, alpha: 1).setStroke()
                    NSBezierPath(rect: rect).stroke()
                    let value = column < values[row].count ? values[row][column] : ""
                    let isNumber = FormulaEngine.parseNumber(value) != nil
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = isNumber ? .right : .left
                    paragraph.lineBreakMode = .byTruncatingTail
                    (value as NSString).draw(in: rect.insetBy(dx: 5, dy: 4), withAttributes: [
                        .font: spec.headerRow && row == 0 ? bold : font,
                        .foregroundColor: value == "#ERROR" ? NSColor.systemRed : NSColor.black,
                        .paragraphStyle: paragraph,
                    ])
                }
            }
        }
    }
}

// MARK: - Drawing & signature line

enum DrawingRenderer {
    static func image(_ spec: DrawingSpec) -> NSImage {
        ObjectRenderer.draw(size: CGSize(width: spec.width, height: spec.height)) { context in
            for stroke in spec.strokes { draw(stroke, in: context) }
        }
    }

    static func draw(_ stroke: DrawingStroke, in context: CGContext) {
        guard let first = stroke.points.first else { return }
        let color = NSColor(hex: stroke.colorHex) ?? .black
        context.setStrokeColor(color.withAlphaComponent(stroke.highlighter ? 0.35 : 1).cgColor)
        context.setLineWidth(stroke.highlighter ? max(stroke.width, 12) : stroke.width)
        context.setLineCap(stroke.highlighter ? .butt : .round)
        context.setLineJoin(.round)
        context.move(to: first)
        for point in stroke.points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
}

enum SignatureRenderer {
    static func image(_ spec: SignatureSpec) -> NSImage {
        let size = CGSize(width: 260, height: 96)
        return ObjectRenderer.draw(size: size) { _ in
            if let signed = spec.signedName {
                (signed as NSString).draw(at: CGPoint(x: 26, y: 12), withAttributes: [
                    .font: NSFont(name: "Snell Roundhand", size: 30) ?? NSFont.systemFont(ofSize: 26),
                    .foregroundColor: NSColor(srgbRed: 0.1, green: 0.15, blue: 0.4, alpha: 1),
                ])
            }
            ("✕" as NSString).draw(at: CGPoint(x: 4, y: 34), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray])
            NSColor.darkGray.setFill()
            CGRect(x: 4, y: 58, width: size.width - 8, height: 1).fill()
            let details = [spec.signer, spec.title].filter { !$0.isEmpty }.joined(separator: "\n")
            (details as NSString).draw(at: CGPoint(x: 4, y: 62), withAttributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.darkGray])
            if let date = spec.signedDate {
                let text = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
                (text as NSString).draw(at: CGPoint(x: size.width - 90, y: 62), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
            }
        }
    }
}
