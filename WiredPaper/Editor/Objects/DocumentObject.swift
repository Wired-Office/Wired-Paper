import AppKit

/// Kinds of live objects embedded in text. Each is an attachment character
/// carrying a `.wpObject` JSON description; the attachment's file is a rendered
/// image so other apps still see something sensible.
enum ObjectKind: String, Codable {
    case footnote, endnote, field, chart, equation, shape, diagram, checkbox, dropdown, date, signature, drawing, spreadsheet, wordArt
}

enum FieldKind: String, Codable, CaseIterable, Identifiable {
    case page, numPages, date, time, title, author, subject, filename, sequence, crossReference, mergeField, formula
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .page: "Page Number"
        case .numPages: "Number of Pages"
        case .date: "Date"
        case .time: "Time"
        case .title: "Title"
        case .author: "Author"
        case .subject: "Subject"
        case .filename: "File Name"
        case .sequence: "Sequence (Caption Number)"
        case .crossReference: "Cross-reference"
        case .mergeField: "Merge Field"
        case .formula: "Formula"
        }
    }
}

enum CrossReferenceDisplay: String, Codable, CaseIterable, Identifiable {
    case text, pageNumber, number, aboveBelow
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .pageNumber: "Page Number"
        case .number: "Number"
        case .aboveBelow: "Above/Below"
        }
    }
}

struct FieldSpec: Codable, Equatable {
    var kind: FieldKind
    /// Sequence label ("Figure"), bookmark name, merge field name or formula.
    var argument = ""
    var display: CrossReferenceDisplay = .text
    /// Frozen value for date/time fields (nil = always current).
    var fixedValue: String?

    init(kind: FieldKind, argument: String = "") {
        self.kind = kind
        self.argument = argument
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(FieldKind.self, forKey: .kind)
        argument = c.value(.argument, default: "")
        display = c.value(.display, default: .text)
        fixedValue = c.value(.fixedValue, default: nil)
    }
}

/// The JSON envelope stored in `.wpObject`. Only the member for `kind` is set.
struct DocumentObject: Codable, Equatable {
    var kind: ObjectKind
    var id = UUID().uuidString
    var field: FieldSpec?
    var chart: ChartSpec?
    var equation: EquationSpec?
    var shape: ShapeSpec?
    var diagram: DiagramSpec?
    var form: FormControlSpec?
    var drawing: DrawingSpec?
    var sheet: SpreadsheetSpec?
    var signature: SignatureSpec?

    init(kind: ObjectKind) {
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ObjectKind.self, forKey: .kind)
        id = c.value(.id, default: UUID().uuidString)
        field = c.value(.field, default: nil)
        chart = c.value(.chart, default: nil)
        equation = c.value(.equation, default: nil)
        shape = c.value(.shape, default: nil)
        diagram = c.value(.diagram, default: nil)
        form = c.value(.form, default: nil)
        drawing = c.value(.drawing, default: nil)
        sheet = c.value(.sheet, default: nil)
        signature = c.value(.signature, default: nil)
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decode(_ value: Any?) -> DocumentObject? {
        guard let string = value as? String, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DocumentObject.self, from: data)
    }

    static func footnote(isEndnote: Bool, id: String) -> DocumentObject {
        var object = DocumentObject(kind: isEndnote ? .endnote : .footnote)
        object.id = id
        return object
    }

    static func field(_ spec: FieldSpec) -> DocumentObject {
        var object = DocumentObject(kind: .field)
        object.field = spec
        return object
    }

    /// True for objects that render as text (fields, note references).
    var isTextual: Bool { kind == .field || kind == .footnote || kind == .endnote }
}

/// Builds attachment strings for objects.
enum ObjectFactory {
    static let placeholderFilename = "wp-object.png"

    /// An attachment character for `object`, carrying `attributes` and a
    /// rendered image so other apps show something sensible.
    static func string(for object: DocumentObject, image: NSImage?, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let wrapper = FileWrapper(regularFileWithContents: pngData(image ?? placeholderImage(for: object)))
        wrapper.preferredFilename = "wp-\(object.kind.rawValue).png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let result = NSMutableAttributedString(attachment: attachment)
        var combined = attributes
        combined.removeValue(forKey: .link)
        combined[.wpObject] = object.json
        combined[.attachment] = attachment
        result.addAttributes(combined, range: NSRange(location: 0, length: result.length))
        ObjectCells.install(for: attachment, object: object)
        return result
    }

    static func pngData(_ image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return Data() }
        return data
    }

    static func placeholderImage(for object: DocumentObject) -> NSImage {
        let text: String
        switch object.kind {
        case .footnote, .endnote: text = "*"
        case .field: text = object.field.map { "[\($0.kind.displayName)]" } ?? "[Field]"
        default: text = "[\(object.kind.rawValue)]"
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray]
        let size = (text as NSString).size(withAttributes: attributes)
        return NSImage(size: NSSize(width: max(size.width, 1), height: max(size.height, 1)), flipped: false) { _ in
            (text as NSString).draw(at: .zero, withAttributes: attributes)
            return true
        }
    }
}
