import AppKit

/// An editable snapshot of an NSTextTable: cells with their rich content, spans
/// and backgrounds. Structural edits (rows, columns, sorting, styles) are made
/// on the model and written back as a freshly built table.
struct TableModel {
    struct Cell {
        var content: NSAttributedString
        var rowSpan = 1
        var columnSpan = 1
        var background: NSColor?
        var verticalAlignment: NSTextBlock.VerticalAlignment = .topAlignment
    }

    /// cells[row][column]; nil where a spanning cell covers the slot.
    var cells: [[Cell?]]
    var borderColor = TableBuilder.borderColor
    var borderWidth: CGFloat = 0.75
    var padding: CGFloat = 6
    var columnWidths: [CGFloat?]
    var baseAttributes: [NSAttributedString.Key: Any]

    var rowCount: Int { cells.count }
    var columnCount: Int { cells.first?.count ?? 0 }

    // MARK: Reading

    /// Reads the table containing `location`.
    static func read(at location: Int, in storage: NSAttributedString) -> (TableModel, NSRange, row: Int, column: Int)? {
        guard let anchor = TableBuilder.tableBlock(at: location, in: storage) else { return nil }
        let table = anchor.table
        let tableRange = storage.range(of: table, at: location)
        var blocks: [(NSTextTableBlock, NSRange)] = []
        var seen = Set<ObjectIdentifier>()
        var index = tableRange.location
        while index < NSMaxRange(tableRange) {
            guard let block = TableBuilder.tableBlock(at: index, in: storage), block.table === table else { index += 1; continue }
            let range = storage.range(of: block, at: index)
            if seen.insert(ObjectIdentifier(block)).inserted { blocks.append((block, range)) }
            index = max(NSMaxRange(range), index + 1)
        }
        guard !blocks.isEmpty else { return nil }
        let rows = blocks.map { $0.0.startingRow + $0.0.rowSpan }.max() ?? 1
        let columns = max(table.numberOfColumns, blocks.map { $0.0.startingColumn + $0.0.columnSpan }.max() ?? 1)
        var cells: [[Cell?]] = Array(repeating: Array(repeating: nil, count: columns), count: rows)
        var widths: [CGFloat?] = Array(repeating: nil, count: columns)
        for (block, range) in blocks {
            // Cell content without its trailing paragraph break.
            var contentRange = range
            if contentRange.length > 0, (storage.string as NSString).character(at: NSMaxRange(contentRange) - 1) == 0x0A {
                contentRange.length -= 1
            }
            let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: contentRange))
            var cell = Cell(content: content, rowSpan: block.rowSpan, columnSpan: block.columnSpan, background: block.backgroundColor)
            cell.verticalAlignment = block.verticalAlignment
            cells[block.startingRow][block.startingColumn] = cell
            if block.columnSpan == 1, block.valueType(for: .width) == .absoluteValueType {
                widths[block.startingColumn] = block.value(for: .width)
            }
        }
        // Fill slots not covered by spans (irregular tables) with empty cells.
        let covered = coverage(cells)
        for row in 0..<rows { for column in 0..<columns where cells[row][column] == nil && !covered[row][column] {
            cells[row][column] = Cell(content: NSAttributedString(string: ""))
        } }
        var model = TableModel(cells: cells, columnWidths: widths, baseAttributes: storage.attributes(at: tableRange.location, effectiveRange: nil))
        if let first = blocks.first?.0 {
            model.borderColor = first.borderColor(for: .minX) ?? model.borderColor
            model.borderWidth = first.width(for: .border, edge: .minX)
            model.padding = first.width(for: .padding, edge: .minX)
        }
        model.baseAttributes.removeValue(forKey: .attachment)
        model.baseAttributes.removeValue(forKey: .wpObject)
        return (model, tableRange, anchor.startingRow, anchor.startingColumn)
    }

    /// Which slots are covered by another cell's span.
    static func coverage(_ cells: [[Cell?]]) -> [[Bool]] {
        let rows = cells.count, columns = cells.first?.count ?? 0
        var covered = Array(repeating: Array(repeating: false, count: columns), count: rows)
        for row in 0..<rows { for column in 0..<columns {
            guard let cell = cells[row][column] else { continue }
            for r in row..<min(row + cell.rowSpan, rows) { for c in column..<min(column + cell.columnSpan, columns) where r != row || c != column {
                covered[r][c] = true
            } }
        } }
        return covered
    }

    // MARK: Building

    func build() -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = max(columnCount, 1)
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        let baseStyle = (baseAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default
        let result = NSMutableAttributedString()
        for row in 0..<rowCount { for column in 0..<columnCount {
            guard let cell = cells[row][column] else { continue }
            let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: cell.rowSpan, startingColumn: column, columnSpan: cell.columnSpan)
            block.setWidth(borderWidth, type: .absoluteValueType, for: .border)
            block.setBorderColor(borderColor)
            block.setWidth(padding, type: .absoluteValueType, for: .padding)
            if cell.columnSpan == 1, let width = columnWidths[column] {
                block.setValue(width, type: .absoluteValueType, for: .width)
            } else {
                block.setValue(100 * CGFloat(cell.columnSpan) / CGFloat(max(columnCount, 1)), type: .percentageValueType, for: .width)
            }
            block.backgroundColor = cell.background
            block.verticalAlignment = cell.verticalAlignment

            let content = NSMutableAttributedString(attributedString: cell.content)
            let paragraphAttributes: [NSAttributedString.Key: Any] = {
                var attributes = content.length > 0 ? content.attributes(at: 0, effectiveRange: nil) : baseAttributes
                attributes.removeValue(forKey: .attachment)
                attributes.removeValue(forKey: .wpObject)
                return attributes
            }()
            content.append(NSAttributedString(string: "\n", attributes: paragraphAttributes))
            let full = NSRange(location: 0, length: content.length)
            content.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
                let style = (value as? NSParagraphStyle) ?? baseStyle
                content.addAttribute(.paragraphStyle, value: TableBuilder.cellParagraphStyle(basedOn: style, block: block), range: range)
            }
            result.append(content)
        } }
        return result
    }

    // MARK: Structure

    mutating func insertRow(at index: Int) {
        let row: [Cell?] = (0..<columnCount).map { _ in Cell(content: NSAttributedString(string: "", attributes: baseAttributes)) }
        cells.insert(row, at: min(max(index, 0), rowCount))
        normalizeSpans()
    }

    mutating func deleteRow(_ index: Int) {
        guard rowCount > 1, cells.indices.contains(index) else { return }
        cells.remove(at: index)
        normalizeSpans()
    }

    mutating func insertColumn(at index: Int) {
        let position = min(max(index, 0), columnCount)
        for row in 0..<rowCount {
            cells[row].insert(Cell(content: NSAttributedString(string: "", attributes: baseAttributes)), at: position)
        }
        columnWidths.insert(nil, at: position)
        normalizeSpans()
    }

    mutating func deleteColumn(_ index: Int) {
        guard columnCount > 1, index >= 0, index < columnCount else { return }
        for row in 0..<rowCount { cells[row].remove(at: index) }
        columnWidths.remove(at: index)
        normalizeSpans()
    }

    /// Merges the rectangle of cells into the top-left one.
    mutating func merge(rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        guard rows.lowerBound >= 0, rows.upperBound < rowCount, columns.lowerBound >= 0, columns.upperBound < columnCount else { return }
        let combined = NSMutableAttributedString()
        for row in rows { for column in columns {
            guard let cell = cells[row][column], cell.content.length > 0 else { continue }
            if combined.length > 0 { combined.append(NSAttributedString(string: " ", attributes: baseAttributes)) }
            combined.append(cell.content)
            if row != rows.lowerBound || column != columns.lowerBound { cells[row][column] = nil }
        } }
        for row in rows { for column in columns where row != rows.lowerBound || column != columns.lowerBound { cells[row][column] = nil } }
        cells[rows.lowerBound][columns.lowerBound] = Cell(
            content: combined,
            rowSpan: rows.count,
            columnSpan: columns.count,
            background: cells[rows.lowerBound][columns.lowerBound]?.background
        )
    }

    /// Splits a merged cell back into single cells.
    mutating func split(row: Int, column: Int) {
        guard let cell = cells[row][column], cell.rowSpan > 1 || cell.columnSpan > 1 else { return }
        for r in row..<min(row + cell.rowSpan, rowCount) { for c in column..<min(column + cell.columnSpan, columnCount) {
            cells[r][c] = Cell(content: r == row && c == column ? cell.content : NSAttributedString(string: "", attributes: baseAttributes), background: cell.background)
        } }
    }

    /// Clamps spans after rows/columns were inserted or removed.
    private mutating func normalizeSpans() {
        for row in 0..<rowCount { for column in 0..<columnCount {
            guard var cell = cells[row][column] else { continue }
            cell.rowSpan = min(cell.rowSpan, rowCount - row)
            cell.columnSpan = min(cell.columnSpan, columnCount - column)
            cells[row][column] = cell
        } }
        let covered = Self.coverage(cells)
        for row in 0..<rowCount { for column in 0..<columnCount where cells[row][column] == nil && !covered[row][column] {
            cells[row][column] = Cell(content: NSAttributedString(string: "", attributes: baseAttributes))
        } }
    }

    // MARK: Content

    func text(row: Int, column: Int) -> String {
        cells[row][column]?.content.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Sorts rows by a column (numbers numerically, otherwise alphabetically).
    mutating func sort(byColumn column: Int, ascending: Bool, hasHeader: Bool) {
        guard column < columnCount, cells.allSatisfy({ $0.allSatisfy { ($0?.rowSpan ?? 1) == 1 } }) else { return }
        let header = hasHeader && rowCount > 1 ? [cells[0]] : []
        var body = hasHeader && rowCount > 1 ? Array(cells.dropFirst()) : cells
        body.sort { a, b in
            let left = a[column]?.content.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let right = b[column]?.content.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let x = FormulaEngine.parseNumber(left), let y = FormulaEngine.parseNumber(right) {
                return ascending ? x < y : x > y
            }
            let order = left.localizedStandardCompare(right)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        cells = header + body
    }

    mutating func distributeColumns() {
        columnWidths = Array(repeating: nil, count: columnCount)
    }

    mutating func setColumnWidth(_ column: Int, width: CGFloat?) {
        guard columnWidths.indices.contains(column) else { return }
        columnWidths[column] = width
    }

    /// Tab-separated text, one paragraph per row.
    func plainText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        var attributes = baseAttributes
        if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.textBlocks = []
            attributes[.paragraphStyle] = style
        }
        for row in 0..<rowCount {
            let line = (0..<columnCount).map { text(row: row, column: $0) }.joined(separator: "\t")
            result.append(NSAttributedString(string: line + "\n", attributes: attributes))
        }
        return result
    }
}

/// Built-in table looks.
enum TableStylePreset: String, CaseIterable, Identifiable {
    case grid, headerAccent, bandedRows, minimal, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grid: "Grid"
        case .headerAccent: "Header Accent"
        case .bandedRows: "Banded Rows"
        case .minimal: "Minimal"
        case .dark: "Dark Header"
        }
    }

    func apply(to model: inout TableModel) {
        let accent = NSColor(srgbRed: 0.90, green: 0.95, blue: 0.96, alpha: 1)
        let band = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        let manager = NSFontManager.shared
        for row in 0..<model.rowCount { for column in 0..<model.columnCount {
            guard var cell = model.cells[row][column] else { continue }
            let isHeader = row == 0
            switch self {
            case .grid:
                cell.background = nil
            case .headerAccent:
                cell.background = isHeader ? accent : nil
            case .bandedRows:
                cell.background = isHeader ? accent : (row % 2 == 0 ? band : nil)
            case .minimal:
                cell.background = nil
            case .dark:
                cell.background = isHeader ? NSColor(srgbRed: 0.12, green: 0.29, blue: 0.35, alpha: 1) : (row % 2 == 0 ? band : nil)
            }
            let content = NSMutableAttributedString(attributedString: cell.content)
            let full = NSRange(location: 0, length: content.length)
            content.enumerateAttribute(.font, in: full) { value, range, _ in
                guard let font = value as? NSFont else { return }
                content.addAttribute(.font, value: isHeader && self != .grid ? manager.convert(font, toHaveTrait: .boldFontMask) : font, range: range)
            }
            if self == .dark {
                content.addAttribute(.foregroundColor, value: isHeader ? NSColor.white : NSColor.black, range: full)
            }
            cell.content = content
            model.cells[row][column] = cell
        } }
        switch self {
        case .minimal:
            model.borderColor = NSColor(white: 0.85, alpha: 1)
            model.borderWidth = 0.5
        case .dark:
            model.borderColor = NSColor(srgbRed: 0.12, green: 0.29, blue: 0.35, alpha: 1)
            model.borderWidth = 0.75
        default:
            model.borderColor = TableBuilder.borderColor
            model.borderWidth = 0.75
        }
    }
}
