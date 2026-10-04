import AppKit

/// Draws charts with Core Graphics so output is identical on screen, in PDF
/// and in exported files.
enum ChartRenderer {
    static let palette: [NSColor] = [
        NSColor(hex: "#13787F")!, NSColor(hex: "#E08A2E")!, NSColor(hex: "#5B6EE1")!,
        NSColor(hex: "#C8475B")!, NSColor(hex: "#6BA34A")!, NSColor(hex: "#8E5BB5")!,
    ]

    static func color(_ index: Int) -> NSColor { palette[index % palette.count] }

    static func image(_ spec: ChartSpec) -> NSImage {
        let size = CGSize(width: spec.width, height: spec.height)
        return ObjectRenderer.draw(size: size) { context in
            NSColor.white.setFill()
            CGRect(origin: .zero, size: size).fill()
            var plot = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 10)

            if !spec.title.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor(white: 0.15, alpha: 1)]
                let titleSize = (spec.title as NSString).size(withAttributes: attributes)
                (spec.title as NSString).draw(at: CGPoint(x: size.width / 2 - titleSize.width / 2, y: plot.minY), withAttributes: attributes)
                plot.origin.y += titleSize.height + 8
                plot.size.height -= titleSize.height + 8
            }
            if spec.showLegend && !spec.series.isEmpty {
                let legendHeight = drawLegend(spec, width: size.width, bottom: plot.maxY)
                plot.size.height -= legendHeight + 6
            }
            if spec.type == .pie {
                drawPie(spec, in: plot)
            } else {
                drawAxes(spec, in: plot, context: context)
            }
        }
    }

    private static let smallFont = NSFont.systemFont(ofSize: 10)
    private static var labelAttributes: [NSAttributedString.Key: Any] { [.font: smallFont, .foregroundColor: NSColor(white: 0.35, alpha: 1)] }

    private static func legendEntries(_ spec: ChartSpec) -> [String] {
        spec.type == .pie ? spec.categories : spec.series.map(\.name)
    }

    private static func drawLegend(_ spec: ChartSpec, width: CGFloat, bottom: CGFloat) -> CGFloat {
        let entries = legendEntries(spec)
        let widths = entries.map { ($0 as NSString).size(withAttributes: labelAttributes).width + 24 }
        let total = widths.reduce(0, +)
        var x = max(8, width / 2 - total / 2)
        let y = bottom - 14
        for (index, entry) in entries.enumerated() {
            color(index).setFill()
            CGRect(x: x, y: y + 2, width: 10, height: 10).fill()
            (entry as NSString).draw(at: CGPoint(x: x + 14, y: y), withAttributes: labelAttributes)
            x += widths[index]
        }
        return 14
    }

    private static func niceStep(_ range: Double) -> Double {
        guard range > 0 else { return 1 }
        let raw = range / 5
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let step: Double = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10
        return step * magnitude
    }

    private static func label(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func drawAxes(_ spec: ChartSpec, in bounds: CGRect, context: CGContext) {
        let values = spec.series.flatMap(\.values)
        let categories = spec.type == .scatter ? [] : spec.categories
        var minValue = min(0, values.min() ?? 0)
        var maxValue = max(values.max() ?? 1, minValue + 1)
        let step = niceStep(maxValue - minValue)
        minValue = floor(minValue / step) * step
        maxValue = ceil(maxValue / step) * step

        let isHorizontal = spec.type == .bar
        let valueLabels = stride(from: minValue, through: maxValue + step / 2, by: step).map { label($0) }
        let valueLabelWidth = valueLabels.map { ($0 as NSString).size(withAttributes: labelAttributes).width }.max() ?? 20
        let categoryLabelWidth = categories.map { ($0 as NSString).size(withAttributes: labelAttributes).width }.max() ?? 0

        var plot = bounds
        let leftInset = isHorizontal ? categoryLabelWidth + 8 : valueLabelWidth + 8
        plot.origin.x += leftInset + (spec.yAxisTitle.isEmpty ? 0 : 16)
        plot.size.width -= leftInset + (spec.yAxisTitle.isEmpty ? 0 : 16) + 6
        plot.size.height -= 18 + (spec.xAxisTitle.isEmpty ? 0 : 16)
        plot.origin.y += 4
        guard plot.width > 10, plot.height > 10 else { return }

        func valuePosition(_ value: Double) -> CGFloat {
            let fraction = CGFloat((value - minValue) / (maxValue - minValue))
            return isHorizontal ? plot.minX + fraction * plot.width : plot.maxY - fraction * plot.height
        }

        // Gridlines and value labels.
        context.setLineWidth(0.5)
        for (index, value) in stride(from: minValue, through: maxValue + step / 2, by: step).enumerated() {
            let p = valuePosition(value)
            context.setStrokeColor(NSColor(white: value == 0 ? 0.55 : 0.86, alpha: 1).cgColor)
            let text = valueLabels[index] as NSString
            let textSize = text.size(withAttributes: labelAttributes)
            if isHorizontal {
                context.move(to: CGPoint(x: p, y: plot.minY)); context.addLine(to: CGPoint(x: p, y: plot.maxY))
                text.draw(at: CGPoint(x: p - textSize.width / 2, y: plot.maxY + 3), withAttributes: labelAttributes)
            } else {
                context.move(to: CGPoint(x: plot.minX, y: p)); context.addLine(to: CGPoint(x: plot.maxX, y: p))
                text.draw(at: CGPoint(x: plot.minX - textSize.width - 5, y: p - textSize.height / 2), withAttributes: labelAttributes)
            }
            context.strokePath()
        }

        // Axis titles.
        if !spec.xAxisTitle.isEmpty {
            let size = (spec.xAxisTitle as NSString).size(withAttributes: labelAttributes)
            (spec.xAxisTitle as NSString).draw(at: CGPoint(x: plot.midX - size.width / 2, y: plot.maxY + 18), withAttributes: labelAttributes)
        }
        if !spec.yAxisTitle.isEmpty {
            context.saveGState()
            let size = (spec.yAxisTitle as NSString).size(withAttributes: labelAttributes)
            context.translateBy(x: bounds.minX + size.height / 2, y: plot.midY)
            context.rotate(by: -.pi / 2)
            (spec.yAxisTitle as NSString).draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: labelAttributes)
            context.restoreGState()
        }

        if spec.type == .scatter {
            drawScatter(spec, plot: plot, valuePosition: valuePosition, context: context)
            return
        }

        let count = max(categories.count, spec.series.map(\.values.count).max() ?? 0)
        guard count > 0 else { return }
        let band = (isHorizontal ? plot.height : plot.width) / CGFloat(count)
        for index in 0..<count where index < categories.count {
            let text = categories[index] as NSString
            let size = text.size(withAttributes: labelAttributes)
            if isHorizontal {
                text.draw(at: CGPoint(x: plot.minX - size.width - 5, y: plot.minY + band * (CGFloat(index) + 0.5) - size.height / 2), withAttributes: labelAttributes)
            } else {
                text.draw(at: CGPoint(x: plot.minX + band * (CGFloat(index) + 0.5) - size.width / 2, y: plot.maxY + 3), withAttributes: labelAttributes)
            }
        }

        let barSeries = spec.series.enumerated().filter { _, series in
            spec.type == .column || spec.type == .bar || (spec.type == .combo && !series.asLine)
        }
        let lineSeries = spec.series.enumerated().filter { _, series in
            spec.type == .line || spec.type == .area || (spec.type == .combo && series.asLine)
        }

        // Bars.
        if !barSeries.isEmpty {
            let groupWidth = band * 0.72
            let barWidth = groupWidth / CGFloat(barSeries.count)
            let zero = valuePosition(0)
            for (slot, (seriesIndex, series)) in barSeries.enumerated() {
                color(seriesIndex).setFill()
                for (index, value) in series.values.prefix(count).enumerated() {
                    let start = band * CGFloat(index) + (band - groupWidth) / 2 + barWidth * CGFloat(slot)
                    let p = valuePosition(value)
                    let rect = isHorizontal
                        ? CGRect(x: min(zero, p), y: plot.minY + start, width: abs(p - zero), height: barWidth - 1)
                        : CGRect(x: plot.minX + start, y: min(zero, p), width: barWidth - 1, height: abs(p - zero))
                    rect.fill()
                }
            }
        }

        // Lines and areas.
        for (seriesIndex, series) in lineSeries {
            let points = series.values.prefix(count).enumerated().map { index, value in
                CGPoint(x: plot.minX + band * (CGFloat(index) + 0.5), y: valuePosition(value))
            }
            guard let first = points.first, let last = points.last else { continue }
            let tint = color(seriesIndex)
            if spec.type == .area {
                context.move(to: CGPoint(x: first.x, y: valuePosition(0)))
                points.forEach { context.addLine(to: $0) }
                context.addLine(to: CGPoint(x: last.x, y: valuePosition(0)))
                context.closePath()
                context.setFillColor(tint.withAlphaComponent(0.3).cgColor)
                context.fillPath()
            }
            context.setStrokeColor(tint.cgColor)
            context.setLineWidth(2.2)
            context.setLineJoin(.round)
            context.addLines(between: points)
            context.strokePath()
            tint.setFill()
            for point in points {
                NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
            }
        }
    }

    /// Scatter charts plot values against their index (1…n) on a numeric x axis.
    private static func drawScatter(_ spec: ChartSpec, plot: CGRect, valuePosition: (Double) -> CGFloat, context: CGContext) {
        let count = spec.series.map(\.values.count).max() ?? 0
        guard count > 0 else { return }
        for (seriesIndex, series) in spec.series.enumerated() {
            color(seriesIndex).setFill()
            for (index, value) in series.values.enumerated() {
                let x = plot.minX + plot.width * (CGFloat(index) + 0.5) / CGFloat(count)
                NSBezierPath(ovalIn: CGRect(x: x - 4, y: valuePosition(value) - 4, width: 8, height: 8)).fill()
            }
        }
    }

    private static func drawPie(_ spec: ChartSpec, in bounds: CGRect) {
        let values = (spec.series.first?.values ?? []).map { max($0, 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return }
        let radius = min(bounds.width, bounds.height) / 2 - 4
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var angle: CGFloat = -90
        for (index, value) in values.enumerated() {
            let sweep = CGFloat(value / total) * 360
            let path = NSBezierPath()
            path.move(to: center)
            // Flipped context: clockwise in view space means clockwise: false.
            path.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            path.close()
            color(index).setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            if sweep > 18 {
                let mid = (angle + sweep / 2) * .pi / 180
                let text = "\(Int((value / total * 100).rounded()))%" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white]
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: center.x + cos(mid) * radius * 0.62 - size.width / 2, y: center.y + sin(mid) * radius * 0.62 - size.height / 2), withAttributes: attributes)
            }
            angle += sweep
        }
    }
}
