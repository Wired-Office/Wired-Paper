import AppKit

/// Places footnotes at the bottom of the page that references them. The
/// pagination engine asks for each page's reserve height, shrinking that page's
/// text containers; the renderer then draws the notes into the freed space.
final class FootnoteLayout {
    private(set) var texts: [String: NSAttributedString] = [:]
    var numbers: [String: Int] = [:]
    var fontSize: CGFloat = 9
    var fontFamily = "Helvetica Neue"

    init(records: [FootnoteRecord]) {
        update(records: records)
    }

    func update(records: [FootnoteRecord]) {
        texts = [:]
        for record in records where !record.isEndnote {
            texts[record.id] = record.text
        }
    }

    func attach(to engine: PaginationEngine) {}

    /// Footnote ids referenced on a page, in order.
    func references(onPage page: Int, engine: PaginationEngine) -> [String] {
        guard let storage = engine.layoutManager.textStorage else { return [] }
        let range = engine.characterRange(onPage: page)
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return [] }
        var ids: [String] = []
        storage.enumerateAttribute(.wpObject, in: range) { value, _, _ in
            guard let object = DocumentObject.decode(value), object.kind == .footnote else { return }
            ids.append(object.id)
        }
        return ids
    }

    func noteString(id: String) -> NSAttributedString {
        let font = FontResolver.font(family: fontFamily, size: fontSize)
        let result = NSMutableAttributedString(
            string: "\(numbers[id] ?? 1)",
            attributes: [.font: FontResolver.font(family: fontFamily, size: fontSize * 0.7), .baselineOffset: fontSize * 0.35, .foregroundColor: NSColor.black]
        )
        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
        let body = NSMutableAttributedString(attributedString: texts[id] ?? NSAttributedString(string: ""))
        let full = NSRange(location: 0, length: body.length)
        body.enumerateAttribute(.font, in: full) { value, range, _ in
            let original = value as? NSFont ?? font
            let traits = NSFontManager.shared.traits(of: original)
            body.addAttribute(.font, value: FontResolver.font(family: fontFamily, size: fontSize, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask)), range: range)
        }
        body.removeAttribute(.paragraphStyle, range: full)
        result.append(body)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 2
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static let separatorSpace: CGFloat = 12

    func height(of ids: [String], width: CGFloat) -> CGFloat {
        guard !ids.isEmpty else { return 0 }
        var total = Self.separatorSpace
        for id in ids {
            let rect = noteString(id: id).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            total += ceil(rect.height) + 2
        }
        return total
    }

    func reserve(forPage page: Int, engine: PaginationEngine) -> CGFloat {
        height(of: references(onPage: page, engine: engine), width: engine.geometry.textArea.width)
    }

    func draw(page: Int, in rect: CGRect, engine: PaginationEngine) {
        let ids = references(onPage: page, engine: engine)
        guard !ids.isEmpty else { return }
        NSColor(white: 0.45, alpha: 1).setFill()
        CGRect(x: rect.minX, y: rect.minY + 4, width: min(144, rect.width / 3), height: 0.5).fill()
        var y = rect.minY + Self.separatorSpace
        for id in ids {
            let note = noteString(id: id)
            let bounds = note.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            note.draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: ceil(bounds.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
            y += ceil(bounds.height) + 2
        }
    }
}
