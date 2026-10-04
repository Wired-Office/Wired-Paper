import AppKit

/// Recipients for a mail merge, stored with the document.
struct MailMergeData: Codable, Equatable {
    var sourceName = ""
    var headers: [String] = []
    var records: [[String]] = []
    /// Indices of records left out of the merge.
    var excluded: Set<Int> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceName = c.value(.sourceName, default: "")
        headers = c.value(.headers, default: [])
        records = c.value(.records, default: [])
        excluded = c.value(.excluded, default: [])
    }

    var isEmpty: Bool { headers.isEmpty }
    var includedIndices: [Int] { records.indices.filter { !excluded.contains($0) } }

    func record(_ index: Int) -> [String: String] {
        guard records.indices.contains(index) else { return [:] }
        var values: [String: String] = [:]
        for (column, header) in headers.enumerated() {
            values[header] = column < records[index].count ? records[index][column] : ""
        }
        return values
    }

    /// Parses CSV or TSV (quoted fields, embedded separators, "" escapes, CRLF).
    static func parse(_ text: String, sourceName: String) -> MailMergeData? {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let separator: Character = firstLine.contains("\t") ? "\t" : (firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ",")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        func next() -> Character? {
            if let value = pending { pending = nil; return value }
            return iterator.next()
        }
        while let character = next() {
            if inQuotes {
                if character == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { inQuotes = false; pending = following }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                row.append(field); field = ""
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                if character == "\r", let following = next(), following != "\n" { pending = following }
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard let header = rows.first, !header.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        var data = MailMergeData()
        data.sourceName = sourceName
        data.headers = header.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Field\(index + 1)" : trimmed
        }
        data.records = rows.dropFirst().map { record in
            (0..<data.headers.count).map { $0 < record.count ? record[$0] : "" }
        }
        return data
    }

    /// Headers that look like parts of a postal address, in address order.
    var addressFields: [[String]] {
        func find(_ names: [String]) -> String? {
            headers.first { header in names.contains { header.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") == $0 } }
        }
        var lines: [[String]] = []
        let first = find(["firstname", "vorname", "givenname"])
        let last = find(["lastname", "nachname", "surname", "familyname"])
        if let name = find(["name", "fullname"]) {
            lines.append([name])
        } else if first != nil || last != nil {
            lines.append([first, last].compactMap { $0 })
        }
        for group in [["company", "firma", "organization"], ["address", "street", "straße", "strasse", "address1", "adresse"], ["address2"]] {
            if let field = find(group) { lines.append([field]) }
        }
        let city = find(["city", "stadt", "ort", "town"])
        let postal = find(["zip", "zipcode", "postalcode", "plz", "postcode"])
        let state = find(["state", "region", "province", "bundesland"])
        let cityLine = [postal, city, state].compactMap { $0 }
        if !cityLine.isEmpty { lines.append(cityLine) }
        if let country = find(["country", "land"]) { lines.append([country]) }
        return lines
    }
}

/// Mailings: recipients, merge fields, preview and merging.
extension EditorController {
    var mailMerge: MailMergeData { document?.metadata.mailMerge ?? MailMergeData() }

    func setMailMerge(_ data: MailMergeData?) {
        document?.updateMetadata("Recipients") { $0.mailMerge = data }
        if mergePreviewIndex != nil { previewMergeRecord(mergePreviewIndex ?? 0) }
        objectWillChange.send()
    }

    func loadRecipients(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard let parsed = MailMergeData.parse(text, sourceName: url.lastPathComponent) else {
            throw WiredPaperError.corruptDocument("The recipient list has no header row.")
        }
        setMailMerge(parsed)
    }

    func insertMergeField(_ name: String) {
        insertField(FieldSpec(kind: .mergeField, argument: name))
    }

    /// Inserts an address block built from the recipient list's address fields.
    func insertAddressBlock() {
        let lines = mailMerge.addressFields
        guard !lines.isEmpty else { NSSound.beep(); return }
        insertMergeFieldLines(lines)
    }

    /// Inserts "Dear «First Name» «Last Name»,".
    func insertGreetingLine() {
        let data = mailMerge
        let nameFields = data.addressFields.first ?? []
        let textView = self.textView
        textView.insertText("Dear ", replacementRange: textView.selectedRange())
        for (index, field) in nameFields.enumerated() {
            if index > 0 { textView.insertText(" ", replacementRange: textView.selectedRange()) }
            insertMergeField(field)
        }
        if nameFields.isEmpty { textView.insertText("Sir or Madam", replacementRange: textView.selectedRange()) }
        textView.insertText(",", replacementRange: textView.selectedRange())
    }

    private func insertMergeFieldLines(_ lines: [[String]]) {
        let textView = self.textView
        for (lineIndex, fields) in lines.enumerated() {
            if lineIndex > 0 { textView.insertText("\u{2028}", replacementRange: textView.selectedRange()) }
            for (index, field) in fields.enumerated() {
                if index > 0 { textView.insertText(" ", replacementRange: textView.selectedRange()) }
                insertMergeField(field)
            }
        }
    }

    // MARK: Preview

    /// The record shown in place of «fields», or nil when showing field names.
    var mergePreviewIndex: Int? {
        get { mergePreviewState.index }
        set { mergePreviewState.index = newValue }
    }

    func previewMergeRecord(_ index: Int?) {
        let data = mailMerge
        if let index, !data.records.isEmpty {
            let clamped = min(max(index, 0), data.records.count - 1)
            mergePreviewIndex = clamped
            layoutManager.mergePreview = data.record(clamped)
        } else {
            mergePreviewIndex = nil
            layoutManager.mergePreview = nil
        }
        layoutManager.invalidateLiveObjects()
        pagesView.refreshPages()
        objectWillChange.send()
    }

    // MARK: Merging

    /// The document with every merge field replaced by `values`.
    func mergedText(_ values: [String: String]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: textStorage)
        var replacements: [(NSRange, String)] = []
        result.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let object = DocumentObject.decode(value), let field = object.field, field.kind == .mergeField else { return }
            replacements.append((range, values[field.argument] ?? ""))
        }
        for (range, text) in replacements.reversed() {
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes.removeValue(forKey: .attachment)
            attributes.removeValue(forKey: .wpObject)
            result.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }

    /// All included records, one after another with page breaks between.
    func mergedDocumentText() -> NSAttributedString? {
        let data = mailMerge
        let indices = data.includedIndices
        guard !indices.isEmpty else { return nil }
        let output = NSMutableAttributedString()
        for (position, index) in indices.enumerated() {
            let merged = mergedText(data.record(index))
            output.append(merged)
            if position < indices.count - 1 {
                var attributes = merged.length > 0 ? merged.attributes(at: merged.length - 1, effectiveRange: nil) : [:]
                attributes.removeValue(forKey: .attachment)
                attributes.removeValue(forKey: .wpObject)
                if !(merged.string.hasSuffix("\n")) { output.append(NSAttributedString(string: "\n", attributes: attributes)) }
                output.append(NSAttributedString(string: "\u{0C}", attributes: attributes))
            }
        }
        return output
    }

    /// Metadata for documents generated from this one (layout and styles, no review data).
    var generatedMetadata: DocumentMetadata {
        var metadata = DocumentMetadata()
        guard let source = document?.metadata else { return metadata }
        metadata.headerFooter = source.headerFooter
        metadata.decoration = source.decoration
        metadata.theme = source.theme
        metadata.styles = source.styles
        metadata.footnotes = source.footnotes
        metadata.properties = source.properties
        return metadata
    }
}

/// Keeps the preview index per editor without a stored property in the extension.
final class MergePreviewState {
    var index: Int?
}

// MARK: - Envelopes & labels

enum EnvelopeSize: String, CaseIterable, Identifiable {
    case dl, c5, c6, number10
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dl: "DL (110 × 220 mm)"
        case .c5: "C5 (162 × 229 mm)"
        case .c6: "C6 (114 × 162 mm)"
        case .number10: "US #10 (4⅛ × 9½ in)"
        }
    }

    /// Landscape size in points.
    var size: CGSize {
        let mm: CGFloat = 72 / 25.4
        switch self {
        case .dl: return CGSize(width: 220 * mm, height: 110 * mm)
        case .c5: return CGSize(width: 229 * mm, height: 162 * mm)
        case .c6: return CGSize(width: 162 * mm, height: 114 * mm)
        case .number10: return CGSize(width: 684, height: 297)
        }
    }
}

enum LabelLayout: String, CaseIterable, Identifiable {
    case avery5160, avery3474, avery5163
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avery5160: "Address — 30 per page (Letter, 3 × 10)"
        case .avery3474: "Address — 24 per page (A4, 3 × 8)"
        case .avery5163: "Shipping — 10 per page (Letter, 2 × 5)"
        }
    }

    var paper: PaperPreset {
        switch self {
        case .avery5160, .avery5163: .letter
        case .avery3474: .a4
        }
    }

    var columns: Int { self == .avery5163 ? 2 : 3 }
    var rows: Int {
        switch self {
        case .avery5160: 10
        case .avery3474: 8
        case .avery5163: 5
        }
    }

    var margins: Margins {
        switch self {
        case .avery5160: Margins(top: 36, left: 13.5, bottom: 36, right: 13.5)
        case .avery3474: Margins(top: 12, left: 0, bottom: 12, right: 0)
        case .avery5163: Margins(top: 36, left: 11, bottom: 36, right: 11)
        }
    }
}

enum MailingsBuilder {
    static func envelope(delivery: String, returnAddress: String, size: EnvelopeSize) -> (NSAttributedString, PageSetup) {
        let setup = PageSetup(paperSize: size.size, margins: Margins(top: 28, left: 28, bottom: 28, right: 28))
        let base = StyleCatalog.attributes(for: .normal)
        let output = NSMutableAttributedString()
        func paragraph(_ text: String, indent: CGFloat = 0, spaceBefore: CGFloat = 0, size fontSize: CGFloat? = nil) {
            var attributes = base
            let style = ((base[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            style.paragraphSpacingBefore = spaceBefore
            style.paragraphSpacing = 0
            attributes[.paragraphStyle] = style
            if let fontSize, let font = attributes[.font] as? NSFont { attributes[.font] = font.withSize(fontSize) }
            output.append(NSAttributedString(string: text + "\n", attributes: attributes))
        }
        for line in returnAddress.split(separator: "\n", omittingEmptySubsequences: false) {
            paragraph(String(line), size: 9)
        }
        let contentWidth = size.size.width - 56
        let lines = delivery.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            paragraph(String(line), indent: contentWidth * 0.45, spaceBefore: index == 0 ? size.size.height * 0.28 : 0)
        }
        return (output, setup)
    }

    /// A grid of labels, one per record (or `repeatText` on every label).
    static func labels(texts: [NSAttributedString], layout: LabelLayout) -> (NSAttributedString, PageSetup) {
        let paper = layout.paper.size
        let setup = PageSetup(paperSize: paper, margins: layout.margins)
        let contentWidth = paper.width - layout.margins.left - layout.margins.right
        let contentHeight = paper.height - layout.margins.top - layout.margins.bottom
        let cellHeight = floor(contentHeight / CGFloat(layout.rows)) - 1
        let perPage = layout.rows * layout.columns
        let output = NSMutableAttributedString()
        let base = StyleCatalog.attributes(for: .normal)
        let pages = max(1, Int(ceil(Double(texts.count) / Double(perPage))))

        for page in 0..<pages {
            let table = NSTextTable()
            table.numberOfColumns = layout.columns
            table.layoutAlgorithm = .fixedLayoutAlgorithm
            table.collapsesBorders = true
            table.setContentWidth(contentWidth, type: .absoluteValueType)
            for row in 0..<layout.rows {
                for column in 0..<layout.columns {
                    let index = page * perPage + row * layout.columns + column
                    let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    block.setContentWidth(contentWidth / CGFloat(layout.columns) - 12, type: .absoluteValueType)
                    block.setValue(cellHeight - 12, type: .absoluteValueType, for: .height)
                    block.setValue(cellHeight - 12, type: .absoluteValueType, for: .minimumHeight)
                    block.setValue(cellHeight - 12, type: .absoluteValueType, for: .maximumHeight)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    block.setWidth(0, type: .absoluteValueType, for: .border)
                    block.verticalAlignment = .middleAlignment
                    let text = index < texts.count ? NSMutableAttributedString(attributedString: texts[index]) : NSMutableAttributedString(string: "", attributes: base)
                    // Each label is one paragraph; inner lines use line separators.
                    text.mutableString.replaceOccurrences(of: "\n", with: "\u{2028}", options: [], range: NSRange(location: 0, length: text.length))
                    text.append(NSAttributedString(string: "\n", attributes: base))
                    text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                        let style = ((value as? NSParagraphStyle ?? base[.paragraphStyle] as? NSParagraphStyle ?? .default).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                        style.textBlocks = [block]
                        style.paragraphSpacing = 0
                        style.paragraphSpacingBefore = 0
                        text.addAttribute(.paragraphStyle, value: style, range: range)
                    }
                    if text.length > 0 && text.attribute(.font, at: 0, effectiveRange: nil) == nil {
                        text.addAttributes(base, range: NSRange(location: 0, length: text.length))
                    }
                    output.append(text)
                }
            }
            if page < pages - 1 {
                output.append(NSAttributedString(string: "\u{0C}", attributes: base))
            }
        }
        return (output, setup)
    }
}
