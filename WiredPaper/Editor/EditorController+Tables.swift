import AppKit

/// Structural table editing through `TableModel`.
extension EditorController {
    var isInTable: Bool {
        let location = min(textView.selectedRange().location, max(textStorage.length - 1, 0))
        return textStorage.length > 0 && TableBuilder.tableBlock(at: location, in: textStorage) != nil
    }

    /// Reads the table at the insertion point, lets `change` edit it, and writes it back.
    func editTable(_ actionName: String, _ change: (inout TableModel, _ row: Int, _ column: Int) -> (row: Int, column: Int)?) {
        let textView = self.textView
        let location = min(textView.selectedRange().location, max(textStorage.length - 1, 0))
        guard var (model, range, row, column) = TableModel.read(at: location, in: textStorage) else {
            NSSound.beep()
            return
        }
        let target = change(&model, row, column)
        let rebuilt = model.build()
        guard textView.shouldChangeText(in: range, replacementString: rebuilt.string) else { return }
        textStorage.replaceCharacters(in: range, with: rebuilt)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        if let target { selectTableCell(row: target.row, column: target.column, tableStart: range.location) }
        refreshState()
    }

    private func selectTableCell(row: Int, column: Int, tableStart: Int) {
        guard let anchor = TableBuilder.tableBlock(at: tableStart, in: textStorage) else { return }
        let tableRange = textStorage.range(of: anchor.table, at: tableStart)
        var index = tableRange.location
        while index < NSMaxRange(tableRange) {
            guard let block = TableBuilder.tableBlock(at: index, in: textStorage) else { index += 1; continue }
            let cellRange = textStorage.range(of: block, at: index)
            if block.startingRow == row && block.startingColumn == column {
                textView.setSelectedRange(NSRange(location: cellRange.location, length: 0))
                scrollRangeToVisible(cellRange)
                return
            }
            index = max(NSMaxRange(cellRange), index + 1)
        }
    }

    func insertTableRow(below: Bool) {
        editTable(below ? "Insert Row Below" : "Insert Row Above") { model, row, column in
            let rowSpan = model.cells[row][column]?.rowSpan ?? 1
            let index = below ? row + rowSpan : row
            model.insertRow(at: index)
            return (index, column)
        }
    }

    func insertTableColumn(right: Bool) {
        editTable(right ? "Insert Column Right" : "Insert Column Left") { model, row, column in
            let span = model.cells[row][column]?.columnSpan ?? 1
            let index = right ? column + span : column
            model.insertColumn(at: index)
            return (row, index)
        }
    }

    func deleteTableRow() {
        editTable("Delete Row") { model, row, column in
            guard model.rowCount > 1 else { return nil }
            model.deleteRow(row)
            return (min(row, model.rowCount - 1), column)
        }
    }

    func deleteTableColumn() {
        editTable("Delete Column") { model, row, column in
            guard model.columnCount > 1 else { return nil }
            model.deleteColumn(column)
            return (row, min(column, model.columnCount - 1))
        }
    }

    func deleteTable() {
        let location = min(textView.selectedRange().location, max(textStorage.length - 1, 0))
        guard let block = TableBuilder.tableBlock(at: location, in: textStorage) else { NSSound.beep(); return }
        let range = textStorage.range(of: block.table, at: location)
        textView.setSelectedRange(range)
        textView.delete(nil)
    }

    func selectTable() {
        let location = min(textView.selectedRange().location, max(textStorage.length - 1, 0))
        guard let block = TableBuilder.tableBlock(at: location, in: textStorage) else { NSSound.beep(); return }
        textView.setSelectedRange(textStorage.range(of: block.table, at: location))
    }

    /// Merges the cells covered by the selection.
    func mergeTableCells() {
        let selection = textView.selectedRange()
        var rows = Set<Int>(), columns = Set<Int>()
        var index = selection.location
        repeat {
            if let block = TableBuilder.tableBlock(at: min(index, textStorage.length - 1), in: textStorage) {
                rows.formUnion(block.startingRow..<(block.startingRow + block.rowSpan))
                columns.formUnion(block.startingColumn..<(block.startingColumn + block.columnSpan))
                index = NSMaxRange(textStorage.range(of: block, at: min(index, textStorage.length - 1)))
            } else {
                index += 1
            }
        } while index < NSMaxRange(selection)
        guard let minRow = rows.min(), let maxRow = rows.max(), let minColumn = columns.min(), let maxColumn = columns.max(),
              maxRow > minRow || maxColumn > minColumn else {
            NSSound.beep()
            return
        }
        textView.setSelectedRange(NSRange(location: selection.location, length: 0))
        editTable("Merge Cells") { model, _, _ in
            model.merge(rows: minRow...maxRow, columns: minColumn...maxColumn)
            return (minRow, minColumn)
        }
    }

    func splitTableCell() {
        editTable("Split Cell") { model, row, column in
            model.split(row: row, column: column)
            return (row, column)
        }
    }

    func sortTable(ascending: Bool, hasHeader: Bool = true) {
        editTable("Sort") { model, row, column in
            model.sort(byColumn: column, ascending: ascending, hasHeader: hasHeader)
            return (hasHeader ? 0 : row, column)
        }
    }

    func distributeTableColumns() {
        editTable("Distribute Columns") { model, row, column in
            model.distributeColumns()
            return (row, column)
        }
    }

    func applyTableStyle(_ preset: TableStylePreset) {
        editTable("Table Style") { model, row, column in
            preset.apply(to: &model)
            return (row, column)
        }
    }

    func setCellShading(_ color: NSColor?) {
        editTable("Cell Shading") { model, row, column in
            model.cells[row][column]?.background = color
            return (row, column)
        }
    }

    func setCellVerticalAlignment(_ alignment: NSTextBlock.VerticalAlignment) {
        editTable("Cell Alignment") { model, row, column in
            model.cells[row][column]?.verticalAlignment = alignment
            return (row, column)
        }
    }

    func setCellMargins(_ padding: CGFloat) {
        editTable("Cell Margins") { model, row, column in
            model.padding = padding
            return (row, column)
        }
    }

    func convertTableToText() {
        let location = min(textView.selectedRange().location, max(textStorage.length - 1, 0))
        guard let (model, range, _, _) = TableModel.read(at: location, in: textStorage) else { NSSound.beep(); return }
        let text = model.plainText()
        textView.setSelectedRange(range)
        TextFormatter.replaceSelection(in: textView, with: text, actionName: "Convert Table to Text")
    }

    /// Turns the selected lines into a table, splitting cells at tabs (or commas).
    func convertTextToTable() {
        let selection = textView.selectedRange()
        let string = textStorage.string as NSString
        let range = string.paragraphRange(for: selection)
        guard range.length > 0 else { NSSound.beep(); return }
        let lines = string.substring(with: range).split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        let separator: Character = lines.contains { $0.contains("\t") } ? "\t" : ","
        let rows = lines.map { $0.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }
        let columns = rows.map(\.count).max() ?? 1
        let base = textStorage.attributes(at: range.location, effectiveRange: nil)
        let table = TableBuilder.makeTable(rows: rows.count, columns: columns, contents: rows, headerRow: true, baseAttributes: base)
        textView.setSelectedRange(range)
        TextFormatter.replaceSelection(in: textView, with: table, actionName: "Convert Text to Table", selectAfter: NSRange(location: range.location, length: 0))
    }

    /// Inserts a formula field (e.g. =SUM(ABOVE)) at the insertion point.
    func insertTableFormula(_ formula: String) {
        insertField(FieldSpec(kind: .formula, argument: formula))
    }
}
