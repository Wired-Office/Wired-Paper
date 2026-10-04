import AppKit

/// A starting point for a new document. Content is generated in code from the
/// style catalog, so templates always match the user's current default font.
struct DocumentTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    private let builder: (TemplateWriter) -> Void

    init(id: String, name: String, summary: String, symbol: String, builder: @escaping (TemplateWriter) -> Void) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.builder = builder
    }

    func makeContent(_ pageSetup: PageSetup) -> NSAttributedString {
        let writer = TemplateWriter(contentWidth: pageSetup.contentSize.width)
        builder(writer)
        return writer.output
    }

    static func == (lhs: DocumentTemplate, rhs: DocumentTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A tiny builder for styled template content.
final class TemplateWriter {
    let output = NSMutableAttributedString()
    let contentWidth: CGFloat

    init(contentWidth: CGFloat) {
        self.contentWidth = contentWidth
    }

    func paragraph(
        _ text: String,
        _ kind: ParagraphStyleKind = .normal,
        bold: Bool = false,
        italic: Bool = false,
        color: NSColor? = nil,
        alignment: NSTextAlignment? = nil,
        spacingAfter: CGFloat? = nil,
        rightTabText: String? = nil
    ) {
        var attributes = StyleCatalog.attributes(for: kind)
        let manager = NSFontManager.shared
        if var font = attributes[.font] as? NSFont {
            if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            attributes[.font] = font
        }
        if let color { attributes[.foregroundColor] = color }
        if alignment != nil || spacingAfter != nil || rightTabText != nil,
           let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            if let alignment { style.alignment = alignment }
            if let spacingAfter { style.paragraphSpacing = spacingAfter }
            if rightTabText != nil {
                style.tabStops = [NSTextTab(textAlignment: .right, location: contentWidth - 12)]
            }
            attributes[.paragraphStyle] = style
        }

        output.append(NSAttributedString(string: text, attributes: attributes))
        if let rightTabText {
            var trailing = attributes
            trailing[.font] = StyleCatalog.font(for: .normal)
            trailing[.foregroundColor] = Theme.secondaryInk
            output.append(NSAttributedString(string: "\t" + rightTabText, attributes: trailing))
        }
        output.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    func blank() {
        paragraph("", spacingAfter: 0)
    }

    func bullets(_ items: [String]) {
        output.append(ListFormatter.makeList(items, kind: .bullet, attributes: listAttributes))
    }

    func numbered(_ items: [String]) {
        output.append(ListFormatter.makeList(items, kind: .numbered, attributes: listAttributes))
    }

    func table(_ rows: [[String]]) {
        let columns = rows.map(\.count).max() ?? 1
        output.append(TableBuilder.makeTable(
            rows: rows.count,
            columns: columns,
            contents: rows,
            headerRow: true,
            baseAttributes: StyleCatalog.attributes(for: .normal)
        ))
        // Space after the table.
        paragraph("", spacingAfter: 0)
    }

    func rule() {
        var attributes = StyleCatalog.attributes(for: .normal)
        if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.paragraphSpacing = 4
            style.lineHeightMultiple = 1
            attributes[.paragraphStyle] = style
        }
        let rule = NSMutableAttributedString(attachment: HorizontalRule.makeAttachment())
        rule.addAttributes(attributes, range: NSRange(location: 0, length: rule.length))
        output.append(rule)
        output.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    private var listAttributes: [NSAttributedString.Key: Any] {
        var attributes = StyleCatalog.attributes(for: .normal)
        if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.paragraphSpacing = 3
            attributes[.paragraphStyle] = style
        }
        return attributes
    }
}
