import AppKit

/// Adds tab leaders (dots, dashes or lines across a tab) to TextKit drawing,
/// and exposes page information to live fields drawn inside the text.
final class WPLayoutManager: NSLayoutManager {
    /// Set by the pagination engine: columns per page and the page-number offset.
    var columnsPerPage = 1
    var pageCountProvider: () -> Int = { 1 }
    var fieldValues = FieldValues()

    // Values computed by the editor after layout, read by live field cells.
    /// Footnote/endnote id → number.
    var noteNumbers: [String: Int] = [:]
    /// Sequence (caption) field id → number.
    var sequenceNumbers: [String: Int] = [:]
    /// Formula field id → formatted result.
    var computedValues: [String: String] = [:]
    /// Bookmark name → character index.
    var bookmarkLocations: [String: Int] = [:]
    /// Bookmark name → caption number text ("Figure 2"), when the bookmark is a caption.
    var bookmarkNumbers: [String: String] = [:]
    /// Mail-merge preview values (nil = show «field» placeholders).
    var mergePreview: [String: String]?
    /// Show ¶, · and → marks for paragraph ends, spaces and tabs (screen only).
    var showsFormattingMarks = false

    func crossReferenceText(_ field: FieldSpec) -> String {
        guard let storage = textStorage, let location = bookmarkLocations[field.argument], location < storage.length else {
            return "Error! Reference source not found."
        }
        switch field.display {
        case .pageNumber:
            let glyph = glyphIndexForCharacter(at: location)
            let container = glyph < numberOfGlyphs ? textContainer(forGlyphAt: glyph, effectiveRange: nil) : nil
            let page = container.flatMap(pageIndex(of:)) ?? 0
            return fieldValues.numberFormat.format(page + fieldValues.startingPageNumber)
        case .number:
            return bookmarkNumbers[field.argument] ?? "?"
        case .aboveBelow:
            return "below"
        case .text:
            var range = NSRange()
            _ = storage.attribute(.wpBookmark, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
            let text = (storage.string as NSString).substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Re-lays out every live object (after numbers or values change).
    func invalidateLiveObjects() {
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let object = DocumentObject.decode(value), object.isTextual || object.kind == .checkbox || object.kind == .dropdown || object.kind == .date else { return }
            invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            invalidateDisplay(forCharacterRange: range)
        }
    }

    func pageIndex(of container: NSTextContainer) -> Int? {
        guard let index = textContainers.firstIndex(where: { $0 === container }) else { return nil }
        return index / max(columnsPerPage, 1)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawTabLeaders(in: glyphsToShow, at: origin)
        if showsFormattingMarks, NSGraphicsContext.currentContextDrawingToScreen() {
            drawFormattingMarks(in: glyphsToShow, at: origin)
        }
    }

    static let formattingMarkColor = NSColor(srgbRed: 0.25, green: 0.47, blue: 0.75, alpha: 0.85)

    private func drawFormattingMarks(in glyphs: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphs.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard characters.length > 0, NSMaxRange(characters) <= storage.length else { return }
        let string = storage.string as NSString
        for index in characters.location..<NSMaxRange(characters) {
            let character = string.character(at: index)
            let mark: String
            switch character {
            case 0x20: mark = "·"
            case 0xA0: mark = "°"
            case 0x09: mark = "→"
            case 0x0A, 0x0D, 0x2029: mark = "¶"
            case 0x2028: mark = "↵"
            case 0x0C: mark = "¶"
            default: continue
            }
            let glyph = glyphIndexForCharacter(at: index)
            guard glyph < numberOfGlyphs, let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { continue }
            let font = (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 12)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(font.pointSize * 0.9, 7)),
                .foregroundColor: Self.formattingMarkColor,
            ]
            let size = (mark as NSString).size(withAttributes: attributes)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let rect = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let baseline = origin.y + line.minY + location(forGlyphAt: glyph).y
            var x = origin.x + rect.minX
            if character == 0x20 || character == 0xA0 {
                x = origin.x + rect.midX - size.width / 2
            } else if character == 0x09 {
                x = origin.x + rect.minX + max((rect.width - size.width) / 2, 0)
            }
            (mark as NSString).draw(at: NSPoint(x: x, y: baseline - size.height * 0.8), withAttributes: attributes)
        }
    }

    private func drawTabLeaders(in glyphs: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, glyphs.length > 0 else { return }
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard characters.length > 0, NSMaxRange(characters) <= storage.length else { return }
        let string = storage.string as NSString

        storage.enumerateAttribute(.wpTabLeader, in: characters) { value, range, _ in
            guard let raw = value as? String, raw != "none" else { return }
            // Either a leader for every tab, or a map of tab-stop location → leader.
            let map = TabStops.leaderMap(raw)
            for index in range.location..<NSMaxRange(range) where string.character(at: index) == 0x09 {
                let glyph = glyphIndexForCharacter(at: index)
                guard glyph < numberOfGlyphs, let container = textContainer(forGlyphAt: glyph, effectiveRange: nil) else { continue }
                let rect = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                guard rect.width > 8 else { continue }
                var style = raw
                if !map.isEmpty {
                    // The tab belongs to the first stop at or after where it ends.
                    let end = rect.maxX - container.lineFragmentPadding - 1.5
                    guard let stop = map.keys.sorted().first(where: { $0 >= end }), let leader = map[stop] else { continue }
                    style = leader
                }
                guard style != "none" else { continue }
                let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let baseline = origin.y + line.minY + location(forGlyphAt: glyph).y
                let color = (storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor) ?? .black
                Self.drawLeader(style, from: origin.x + rect.minX + 3, to: origin.x + rect.maxX - 3, baseline: baseline, color: color)
            }
        }
    }

    static func drawLeader(_ style: String, from startX: CGFloat, to endX: CGFloat, baseline: CGFloat, color: NSColor) {
        guard endX > startX else { return }
        color.withAlphaComponent(0.75).set()
        switch style {
        case "line":
            NSRect(x: startX, y: baseline - 0.5, width: endX - startX, height: 0.75).fill()
        case "dash":
            var x = startX
            while x + 3 <= endX {
                NSRect(x: x, y: baseline - 2.5, width: 3, height: 0.75).fill()
                x += 5.5
            }
        default:
            var x = startX
            while x <= endX {
                NSBezierPath(ovalIn: NSRect(x: x, y: baseline - 1.6, width: 1.1, height: 1.1)).fill()
                x += 3.6
            }
        }
    }
}

/// Values substituted into header/footer and body fields.
struct FieldValues {
    var title = ""
    var author = ""
    var subject = ""
    var company = ""
    var filename = "Untitled"
    /// Font family for headers and footers (the document's body font).
    var bodyFontFamily = "Helvetica Neue"
    var startingPageNumber = 1
    var numberFormat: PageNumberFormat = .arabic

    func expand(_ template: String, pageIndex: Int, pageCount: Int) -> String {
        guard template.contains("{") else { return template }
        let now = Date()
        var result = template
        let replacements: [String: String] = [
            "{PAGE}": numberFormat.format(pageIndex + startingPageNumber),
            "{PAGES}": String(pageCount),
            "{NUMPAGES}": String(pageCount),
            "{DATE}": DateFormatter.localizedString(from: now, dateStyle: .long, timeStyle: .none),
            "{TIME}": DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short),
            "{TITLE}": title.isEmpty ? filename : title,
            "{AUTHOR}": author,
            "{SUBJECT}": subject,
            "{COMPANY}": company,
            "{FILENAME}": filename,
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }
}
