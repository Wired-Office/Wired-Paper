import AppKit

/// A grid of cell texts that formulas can reference (A1-style, 1-based rows).
struct FormulaGrid {
    var cells: [[String]]
    var currentRow = 0
    var currentColumn = 0

    func raw(_ row: Int, _ column: Int) -> String? {
        guard row >= 0, row < cells.count, column >= 0, column < cells[row].count else { return nil }
        return cells[row][column]
    }

    func number(_ row: Int, _ column: Int, depth: Int) -> Double? {
        guard let text = raw(row, column)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("="), depth < 20 {
            var inner = self
            inner.currentRow = row
            inner.currentColumn = column
            return FormulaEngine.evaluate(String(text.dropFirst()), grid: inner, depth: depth + 1)
        }
        return FormulaEngine.parseNumber(text)
    }
}

/// Evaluates spreadsheet-style formulas: + - * / ^ %, parentheses, numbers,
/// cell references (A1), ranges (A1:C3), ABOVE/BELOW/LEFT/RIGHT, and the
/// functions SUM, AVERAGE, MIN, MAX, COUNT, PRODUCT, ROUND, ABS, SQRT, IF.
enum FormulaEngine {
    static func evaluate(_ expression: String, grid: FormulaGrid, depth: Int = 0) -> Double? {
        var parser = Parser(tokens: tokenize(expression), grid: grid, depth: depth)
        guard let value = parser.parseExpression(), parser.atEnd else { return nil }
        return value.isFinite ? value : nil
    }

    static func parseNumber(_ text: String) -> Double? {
        var cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        for symbol in ["$", "€", "£", "¥"] { cleaned = cleaned.replacingOccurrences(of: symbol, with: "") }
        var isPercent = false
        if cleaned.hasSuffix("%") {
            isPercent = true
            cleaned.removeLast()
        }
        guard let value = Double(cleaned) else { return nil }
        return isPercent ? value / 100 : value
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(Character)
        case comma, colon, open, close
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character.isNumber || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
                tokens.append(.number(Double(String(characters[index..<end])) ?? 0))
                index = end
            } else if character.isLetter {
                var end = index
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" { end += 1 }
                tokens.append(.identifier(String(characters[index..<end]).uppercased()))
                index = end
            } else {
                switch character {
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                case ",", ";": tokens.append(.comma)
                case ":": tokens.append(.colon)
                case "<", ">", "=":
                    // Comparison operators for IF: <=, >=, <>, <, >, =
                    if index + 1 < characters.count, characters[index + 1] == "=" || (character == "<" && characters[index + 1] == ">") {
                        let pair = String([character, characters[index + 1]])
                        switch pair {
                        case "<=": tokens.append(.op("≤"))
                        case ">=": tokens.append(.op("≥"))
                        case "==": tokens.append(.op("="))
                        default: tokens.append(.op("≠"))
                        }
                        index += 1
                    } else {
                        tokens.append(.op(character))
                    }
                default: tokens.append(.op(character))
                }
                index += 1
            }
        }
        return tokens
    }

    // MARK: Parser

    struct Parser {
        let tokens: [Token]
        let grid: FormulaGrid
        let depth: Int
        var position = 0

        init(tokens: [Token], grid: FormulaGrid, depth: Int) {
            self.tokens = tokens
            self.grid = grid
            self.depth = depth
        }

        var atEnd: Bool { position >= tokens.count }
        private var current: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func parseExpression() -> Double? { parseComparison() }

        private mutating func parseComparison() -> Double? {
            guard var left = parseAdditive() else { return nil }
            while case .op(let op)? = current, "<>=≤≥≠".contains(op) {
                position += 1
                guard let right = parseAdditive() else { return nil }
                let result: Bool
                switch op {
                case "<": result = left < right
                case ">": result = left > right
                case "=": result = left == right
                case "≤": result = left <= right
                case "≥": result = left >= right
                default: result = left != right
                }
                left = result ? 1 : 0
            }
            return left
        }

        private mutating func parseAdditive() -> Double? {
            guard var left = parseTerm() else { return nil }
            while case .op(let op)? = current, op == "+" || op == "-" {
                position += 1
                guard let right = parseTerm() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        private mutating func parseTerm() -> Double? {
            guard var left = parsePower() else { return nil }
            while case .op(let op)? = current, op == "*" || op == "/" || op == "×" || op == "÷" {
                position += 1
                guard let right = parsePower() else { return nil }
                left = (op == "*" || op == "×") ? left * right : left / right
            }
            return left
        }

        private mutating func parsePower() -> Double? {
            guard var base = parseUnary() else { return nil }
            if case .op("^")? = current {
                position += 1
                guard let exponent = parsePower() else { return nil }
                base = pow(base, exponent)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if case .op("-")? = current {
                position += 1
                return parseUnary().map { -$0 }
            }
            if case .op("+")? = current {
                position += 1
                return parseUnary()
            }
            guard var value = parsePrimary() else { return nil }
            if case .op("%")? = current {
                position += 1
                value /= 100
            }
            return value
        }

        private mutating func parsePrimary() -> Double? {
            guard let token = current else { return nil }
            switch token {
            case .number(let value):
                position += 1
                return value
            case .open:
                position += 1
                let value = parseExpression()
                guard case .close? = current else { return nil }
                position += 1
                return value
            case .identifier(let name):
                position += 1
                if case .open? = current {
                    position += 1
                    let arguments = parseArguments()
                    guard case .close? = current else { return nil }
                    position += 1
                    return call(name, arguments)
                }
                if let reference = FormulaEngine.cellReference(name) {
                    return grid.number(reference.row, reference.column, depth: depth) ?? 0
                }
                if name == "PI" { return .pi }
                return nil
            default:
                return nil
            }
        }

        /// Arguments are lists of values (ranges expand to many).
        private mutating func parseArguments() -> [[Double]] {
            var arguments: [[Double]] = []
            if case .close? = current { return arguments }
            while true {
                if let values = parseRangeOrDirection() {
                    arguments.append(values)
                } else if let value = parseExpression() {
                    arguments.append([value])
                } else {
                    return arguments
                }
                guard case .comma? = current else { break }
                position += 1
            }
            return arguments
        }

        private mutating func parseRangeOrDirection() -> [Double]? {
            guard case .identifier(let name)? = current else { return nil }
            switch name {
            case "ABOVE": position += 1; return (0..<grid.currentRow).reversed().compactMap { grid.number($0, grid.currentColumn, depth: depth) }
            case "BELOW": position += 1; return ((grid.currentRow + 1)..<max(grid.cells.count, grid.currentRow + 1)).compactMap { grid.number($0, grid.currentColumn, depth: depth) }
            case "LEFT": position += 1; return (0..<grid.currentColumn).compactMap { grid.number(grid.currentRow, $0, depth: depth) }
            case "RIGHT":
                position += 1
                let width = grid.cells.indices.contains(grid.currentRow) ? grid.cells[grid.currentRow].count : 0
                return ((grid.currentColumn + 1)..<max(width, grid.currentColumn + 1)).compactMap { grid.number(grid.currentRow, $0, depth: depth) }
            default:
                break
            }
            guard let start = FormulaEngine.cellReference(name),
                  position + 2 < tokens.count, case .colon = tokens[position + 1],
                  case .identifier(let endName) = tokens[position + 2], let end = FormulaEngine.cellReference(endName)
            else { return nil }
            position += 3
            var values: [Double] = []
            for row in min(start.row, end.row)...max(start.row, end.row) {
                for column in min(start.column, end.column)...max(start.column, end.column) {
                    if let value = grid.number(row, column, depth: depth) { values.append(value) }
                }
            }
            return values
        }

        private func call(_ name: String, _ arguments: [[Double]]) -> Double? {
            let flat = arguments.flatMap { $0 }
            switch name {
            case "SUM": return flat.reduce(0, +)
            case "AVERAGE", "AVG", "MEAN": return flat.isEmpty ? 0 : flat.reduce(0, +) / Double(flat.count)
            case "MIN": return flat.min() ?? 0
            case "MAX": return flat.max() ?? 0
            case "COUNT": return Double(flat.count)
            case "PRODUCT": return flat.reduce(1, *)
            case "ABS": return flat.first.map(abs)
            case "SQRT": return flat.first.map(sqrt)
            case "ROUND":
                guard let value = arguments.first?.first else { return nil }
                let digits = arguments.count > 1 ? (arguments[1].first ?? 0) : 0
                let factor = pow(10, digits)
                return (value * factor).rounded() / factor
            case "IF":
                guard arguments.count >= 2, let condition = arguments[0].first else { return nil }
                if condition != 0 { return arguments[1].first }
                return arguments.count > 2 ? arguments[2].first : 0
            default:
                return nil
            }
        }
    }

    /// "B3" → (row: 2, column: 1).
    static func cellReference(_ name: String) -> (row: Int, column: Int)? {
        let letters = name.prefix { $0.isLetter }
        let digits = name.dropFirst(letters.count)
        guard !letters.isEmpty, letters.count <= 3, !digits.isEmpty, digits.allSatisfy(\.isNumber), let row = Int(digits), row > 0 else { return nil }
        var column = 0
        for letter in letters.uppercased().unicodeScalars {
            column = column * 26 + Int(letter.value) - 64
        }
        return (row - 1, column - 1)
    }

    static func columnName(_ index: Int) -> String {
        var index = index + 1
        var name = ""
        while index > 0 {
            index -= 1
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index /= 26
        }
        return name
    }
}

/// Formulas inside NSTextTable cells.
enum TableFormula {
    static func evaluate(_ expression: String, at location: Int, in text: NSAttributedString) -> Double? {
        guard let (grid, _) = grid(at: location, in: text) else {
            return FormulaEngine.evaluate(expression.hasPrefix("=") ? String(expression.dropFirst()) : expression, grid: FormulaGrid(cells: []))
        }
        let formula = expression.hasPrefix("=") ? String(expression.dropFirst()) : expression
        return FormulaEngine.evaluate(formula, grid: grid)
    }

    static func format(_ value: Double) -> String { FormulaEngine.format(value) }

    /// The table containing `location` as a grid of cell texts, with the current cell set.
    static func grid(at location: Int, in text: NSAttributedString) -> (FormulaGrid, NSTextTable)? {
        guard location < text.length,
              let style = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
              let block = style.textBlocks.last as? NSTextTableBlock
        else { return nil }
        let table = block.table
        let tableRange = text.range(of: table, at: location)
        var cells: [[String]] = []
        var seen = Set<ObjectIdentifier>()
        var index = tableRange.location
        while index < NSMaxRange(tableRange) {
            guard let cellStyle = text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle,
                  let cellBlock = cellStyle.textBlocks.last as? NSTextTableBlock, cellBlock.table === table
            else { index += 1; continue }
            let cellRange = text.range(of: cellBlock, at: index)
            if !seen.contains(ObjectIdentifier(cellBlock)) {
                seen.insert(ObjectIdentifier(cellBlock))
                let row = cellBlock.startingRow, column = cellBlock.startingColumn
                while cells.count <= row { cells.append([]) }
                while cells[row].count <= column { cells[row].append("") }
                var value = (text.string as NSString).substring(with: cellRange).trimmingCharacters(in: .whitespacesAndNewlines)
                // A cell holding a formula field contributes its computed value.
                text.enumerateAttribute(.wpObject, in: cellRange) { objectValue, _, _ in
                    if let object = DocumentObject.decode(objectValue), object.field?.kind == .formula {
                        value = "=" + (object.field?.argument ?? "").replacingOccurrences(of: "=", with: "")
                    }
                }
                cells[row][column] = value.replacingOccurrences(of: "\u{FFFC}", with: "")
            }
            index = max(NSMaxRange(cellRange), index + 1)
        }
        var grid = FormulaGrid(cells: cells)
        grid.currentRow = block.startingRow
        grid.currentColumn = block.startingColumn
        return (grid, table)
    }
}
