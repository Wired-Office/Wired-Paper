import AppKit

/// Values that live fields display, derived from the whole document: note
/// numbers, caption sequence numbers, bookmark targets and formula results.
struct LiveValues: Equatable {
    var noteNumbers: [String: Int] = [:]
    var sequenceNumbers: [String: Int] = [:]
    var computedValues: [String: String] = [:]
    var bookmarkLocations: [String: Int] = [:]
    var bookmarkNumbers: [String: String] = [:]

    static func compute(for text: NSAttributedString, metadata: DocumentMetadata? = nil) -> LiveValues {
        var values = LiveValues()
        let full = NSRange(location: 0, length: text.length)
        var footnote = 0, endnote = 0
        var sequences: [String: Int] = [:]
        var sequenceLabels: [String: String] = [:]

        text.enumerateAttribute(.wpObject, in: full) { value, _, _ in
            guard let object = DocumentObject.decode(value) else { return }
            switch object.kind {
            case .footnote:
                footnote += 1
                values.noteNumbers[object.id] = footnote
            case .endnote:
                endnote += 1
                values.noteNumbers[object.id] = endnote
            case .field:
                guard let field = object.field else { return }
                if field.kind == .sequence {
                    let label = field.argument.isEmpty ? "Figure" : field.argument
                    sequences[label, default: 0] += 1
                    values.sequenceNumbers[object.id] = sequences[label]
                    sequenceLabels[object.id] = label
                }
            default:
                break
            }
        }

        text.enumerateAttribute(.wpBookmark, in: full) { value, range, _ in
            guard let name = value as? String, values.bookmarkLocations[name] == nil else { return }
            values.bookmarkLocations[name] = range.location
            // A bookmark around a caption can be referenced by its number.
            text.enumerateAttribute(.wpObject, in: range) { objectValue, _, stop in
                guard let object = DocumentObject.decode(objectValue), object.field?.kind == .sequence,
                      let number = values.sequenceNumbers[object.id] else { return }
                values.bookmarkNumbers[name] = "\(sequenceLabels[object.id] ?? "Figure") \(number)"
                stop.pointee = true
            }
        }

        values.computedValues = FormulaFields.evaluateAll(in: text)
        return values
    }

    func apply(to layoutManager: WPLayoutManager) {
        layoutManager.noteNumbers = noteNumbers
        layoutManager.sequenceNumbers = sequenceNumbers
        layoutManager.computedValues = computedValues
        layoutManager.bookmarkLocations = bookmarkLocations
        layoutManager.bookmarkNumbers = bookmarkNumbers
    }
}

extension WPLayoutManager {
    var liveValues: LiveValues {
        LiveValues(
            noteNumbers: noteNumbers,
            sequenceNumbers: sequenceNumbers,
            computedValues: computedValues,
            bookmarkLocations: bookmarkLocations,
            bookmarkNumbers: bookmarkNumbers
        )
    }
}

/// Formula fields inside table cells ("=SUM(ABOVE)", "=AVERAGE(LEFT)", "=A1*2").
enum FormulaFields {
    static func evaluateAll(in text: NSAttributedString) -> [String: String] {
        var results: [String: String] = [:]
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.wpObject, in: full) { value, range, _ in
            guard let object = DocumentObject.decode(value), let field = object.field, field.kind == .formula else { return }
            let result = TableFormula.evaluate(field.argument, at: range.location, in: text)
            results[object.id] = result.map(TableFormula.format) ?? "!Error"
        }
        return results
    }
}
