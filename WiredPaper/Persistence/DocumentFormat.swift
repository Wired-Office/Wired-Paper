import AppKit
import UniformTypeIdentifiers

/// Every file format Wired Paper can read or write.
enum DocumentFormat: String, CaseIterable, Identifiable {
    /// `.paper`: the native single-file format and the default for new documents.
    case paper = "com.wiredpaper.paper"
    /// `.wiredpaper`: the original package format, still fully supported.
    case wiredPaper = "com.wiredpaper.document"
    case docx = "org.openxmlformats.wordprocessingml.document"
    case rtf = "public.rtf"
    case rtfd = "com.apple.rtfd"
    case odt = "org.oasis-open.opendocument.text"
    case html = "public.html"
    case plainText = "public.plain-text"
    case pdf = "com.adobe.pdf"

    var id: String { rawValue }
    var typeIdentifier: String { rawValue }

    var utType: UTType {
        switch self {
        case .paper: UTType(exportedAs: rawValue, conformingTo: .data)
        case .wiredPaper: UTType(exportedAs: rawValue, conformingTo: .package)
        case .docx: UTType(rawValue) ?? UTType(filenameExtension: "docx") ?? .data
        case .rtf: .rtf
        case .rtfd: .rtfd
        case .odt: UTType(rawValue) ?? UTType(filenameExtension: "odt") ?? .data
        case .html: .html
        case .plainText: .plainText
        case .pdf: .pdf
        }
    }

    var displayName: String {
        switch self {
        case .paper: "Paper Document (.paper)"
        case .wiredPaper: "Wired Paper Package (.wiredpaper)"
        case .docx: "Word Document (.docx)"
        case .rtf: "Rich Text (.rtf)"
        case .rtfd: "Rich Text with Attachments (.rtfd)"
        case .odt: "OpenDocument Text (.odt)"
        case .html: "Web Page (.html)"
        case .plainText: "Plain Text (.txt)"
        case .pdf: "PDF"
        }
    }

    /// Short label shown in the window subtitle for non-native documents.
    var shortName: String {
        switch self {
        case .paper: "Paper"
        case .wiredPaper: "Wired Paper Package"
        case .docx: "Word Document"
        case .rtf: "RTF"
        case .rtfd: "RTFD"
        case .odt: "OpenDocument"
        case .html: "HTML"
        case .plainText: "Plain Text"
        case .pdf: "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .paper: "paper"
        case .wiredPaper: "wiredpaper"
        case .docx: "docx"
        case .rtf: "rtf"
        case .rtfd: "rtfd"
        case .odt: "odt"
        case .html: "html"
        case .plainText: "txt"
        case .pdf: "pdf"
        }
    }

    /// Formats that store everything Wired Paper knows about a document.
    var isNative: Bool { self == .paper || self == .wiredPaper }

    /// Whether saving in this format can drop content (images, tables, styles…).
    var isLossy: Bool {
        switch self {
        case .paper, .wiredPaper, .rtfd, .pdf: false
        default: true
        }
    }

    /// Formats offered by File ▸ Export…, in menu order.
    static let exportFormats: [DocumentFormat] = [.pdf, .docx, .paper, .rtf, .rtfd, .odt, .html, .plainText, .wiredPaper]

    /// Resolves a type name handed to us by NSDocument (usually a UTI, possibly a
    /// more specific subtype such as public.utf8-plain-text).
    init?(typeName: String) {
        if let exact = DocumentFormat(rawValue: typeName) {
            self = exact
            return
        }
        guard let type = UTType(typeName) else { return nil }
        // Check the specific formats before the generic plain-text family.
        let ordered: [DocumentFormat] = [.paper, .wiredPaper, .rtfd, .rtf, .docx, .odt, .html, .pdf, .plainText]
        guard let match = ordered.first(where: { type.conforms(to: $0.utType) }) else { return nil }
        self = match
    }
}
