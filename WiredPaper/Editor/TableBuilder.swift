import AppKit

/// Creates and extends tables built from NSTextTable / NSTextTableBlock.
///
/// Each table cell is one or more paragraphs whose paragraph style carries an
/// NSTextTableBlock. NSTextView edits cells natively; Format ▸ Table ▸ Table
/// Properties opens AppKit's table panel for borders, merging and sizing.
enum TableBuilder {
    static let borderColor = NSColor(srgbRed: 0.66, green: 0.69, blue: 0.71, alpha: 1)
    static let headerBackground = NSColor(srgbRed: 0.90, green: 0.95, blue: 0.96, alpha: 1)

    static func makeTable(
        rows: Int,
        columns: Int,
        contents: [[String]]? = nil,
        headerRow: Bool = true,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let rows = max(rows, 1)
        let columns = max(columns, 1)
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)

        let baseStyle = (baseAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default
        let baseFont = (baseAttributes[.font] as? NSFont) ?? StyleCatalog.bodyFont
        var cellAttributes = baseAttributes
        cellAttributes.removeValue(forKey: .link)
        cellAttributes.removeValue(forKey: .attachment)
        cellAttributes[.wpParagraphStyle] = ParagraphStyleKind.normal.rawValue

        let result = NSMutableAttributedString()
        for row in 0..<rows {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                configure(block, columns: columns, isHeader: headerRow && row == 0)

                var attributes = cellAttributes
                attributes[.paragraphStyle] = cellParagraphStyle(basedOn: baseStyle, block: block)
                if headerRow && row == 0 {
                    attributes[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                }
                let text = contents.flatMap { row < $0.count && column < $0[row].count ? $0[row][column] : nil } ?? ""
                result.append(NSAttributedString(string: text + "\n", attributes: attributes))
            }
        }
        return result
    }

    static func configure(_ block: NSTextTableBlock, columns: Int, isHeader: Bool) {
        block.setWidth(0.75, type: .absoluteValueType, for: .border)
        block.setBorderColor(borderColor)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setValue(100 / CGFloat(columns), type: .percentageValueType, for: .width)
        if isHeader { block.backgroundColor = headerBackground }
    }

    static func cellParagraphStyle(basedOn base: NSParagraphStyle, block: NSTextBlock) -> NSParagraphStyle {
        let style = (base.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.textLists = []
        style.headIndent = 0
        style.firstLineHeadIndent = 0
        style.tailIndent = 0
        style.paragraphSpacing = 0
        style.paragraphSpacingBefore = 0
        return style
    }

    static func tableBlock(at location: Int, in storage: NSAttributedString) -> NSTextTableBlock? {
        guard location >= 0, location < storage.length,
              let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        else { return nil }
        return style.textBlocks.last as? NSTextTableBlock
    }

    // MARK: - Editing

    /// Inserts a new table at the insertion point, starting on its own paragraph.
    static func insertTable(rows: Int, columns: Int, into textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let string = storage.string as NSString
        var base = TextFormatter.baseAttributes(for: textView)
        if let style = base[.paragraphStyle] as? NSParagraphStyle, !style.textBlocks.isEmpty || !style.textLists.isEmpty {
            // Don't nest a table inside a cell or list; fall back to Normal.
            base = StyleCatalog.attributes(for: .normal)
        }

        let insertion = NSMutableAttributedString()
        if !TextFormatter.isAtParagraphStart(selection.location, in: string) {
            insertion.append(NSAttributedString(string: "\n", attributes: base))
        }
        let tableStart = selection.location + insertion.length
        insertion.append(makeTable(rows: rows, columns: columns, baseAttributes: base))

        // A table at the very end needs a normal paragraph after it, or typing
        // below it would continue inside the last cell.
        if NSMaxRange(selection) >= storage.length {
            var normal = base
            normal[.paragraphStyle] = StyleCatalog.paragraphStyle(for: .normal)
            insertion.append(NSAttributedString(string: "\n", attributes: normal))
        }

        TextFormatter.replaceSelection(
            in: textView,
            with: insertion,
            actionName: "Insert Table",
            selectAfter: NSRange(location: tableStart, length: 0)
        )
    }

    /// Appends a row to the table containing `location`, copying the last row's
    /// cell geometry. Returns the range of the new row's first cell.
    @discardableResult
    static func appendRow(toTableAt location: Int, in textView: NSTextView) -> NSRange? {
        guard let storage = textView.textStorage, let anchor = tableBlock(at: location, in: storage) else { return nil }
        let table = anchor.table
        let tableRange = storage.range(of: table, at: location)

        var lastRow = -1
        storage.enumerateAttribute(.paragraphStyle, in: tableRange) { value, _, _ in
            guard let block = (value as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock, block.table === table else { return }
            lastRow = max(lastRow, block.startingRow + block.rowSpan - 1)
        }
        guard lastRow >= 0 else { return nil }

        var templateCells: [(block: NSTextTableBlock, attributes: [NSAttributedString.Key: Any])] = []
        var seen = Set<ObjectIdentifier>()
        let string = storage.string as NSString
        string.enumerateSubstrings(in: tableRange, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let probe = min(range.location, storage.length - 1)
            let attributes = storage.attributes(at: probe, effectiveRange: nil)
            guard let block = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock,
                  block.table === table,
                  block.startingRow + block.rowSpan - 1 == lastRow,
                  !seen.contains(ObjectIdentifier(block))
            else { return }
            seen.insert(ObjectIdentifier(block))
            templateCells.append((block, attributes))
        }
        templateCells.sort { $0.block.startingColumn < $1.block.startingColumn }

        let newRow = NSMutableAttributedString()
        for cell in templateCells {
            let block = NSTextTableBlock(
                table: table,
                startingRow: lastRow + 1,
                rowSpan: 1,
                startingColumn: cell.block.startingColumn,
                columnSpan: cell.block.columnSpan
            )
            copyGeometry(from: cell.block, to: block)
            var attributes = cell.attributes
            attributes.removeValue(forKey: .attachment)
            attributes.removeValue(forKey: .link)
            let baseStyle = (attributes[.paragraphStyle] as? NSParagraphStyle) ?? .default
            attributes[.paragraphStyle] = cellParagraphStyle(basedOn: baseStyle, block: block)
            newRow.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        guard newRow.length > 0 else { return nil }

        let insertionPoint = NSMaxRange(tableRange)
        let range = NSRange(location: insertionPoint, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: newRow.string) else { return nil }
        storage.replaceCharacters(in: range, with: newRow)
        textView.didChangeText()
        textView.undoManager?.setActionName("Add Row")
        let firstCell = NSRange(location: insertionPoint, length: 0)
        textView.setSelectedRange(firstCell)
        textView.scrollRangeToVisible(firstCell)
        return firstCell
    }

    private static func copyGeometry(from source: NSTextBlock, to target: NSTextBlock) {
        let edges: [NSRectEdge] = [.minX, .minY, .maxX, .maxY]
        for layer in [NSTextBlock.Layer.padding, .border, .margin] {
            for edge in edges {
                target.setWidth(source.width(for: layer, edge: edge), type: source.widthValueType(for: layer, edge: edge), for: layer, edge: edge)
            }
        }
        for edge in edges {
            target.setBorderColor(source.borderColor(for: edge), for: edge)
        }
        target.setValue(source.value(for: .width), type: source.valueType(for: .width), for: .width)
        target.verticalAlignment = source.verticalAlignment
        // Header shading shouldn't propagate into new body rows.
        if source.backgroundColor != headerBackground {
            target.backgroundColor = source.backgroundColor
        }
    }
}
