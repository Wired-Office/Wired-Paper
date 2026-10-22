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
    case markdown = "net.daringfireball.markdown"
    case wordDoc = "com.microsoft.word.doc"
    case webArchive = "com.apple.webarchive"
    case pdf = "com.adobe.pdf"
    /// Apple Pages. Read-only: Wired Paper imports the text and saves elsewhere.
    case pages = "com.apple.iwork.pages.sffpages"

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
        case .markdown: UTType(rawValue) ?? UTType(filenameExtension: "md") ?? .plainText
        case .wordDoc: UTType(rawValue) ?? UTType(filenameExtension: "doc") ?? .data
        case .webArchive: UTType(rawValue) ?? UTType(filenameExtension: "webarchive") ?? .data
        case .pdf: .pdf
        case .pages: UTType(rawValue) ?? UTType(filenameExtension: "pages") ?? .data
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
        case .markdown: "Markdown (.md)"
        case .wordDoc: "Word 97–2004 Document (.doc)"
        case .webArchive: "Web Archive (.webarchive)"
        case .pdf: "PDF"
        case .pages: "Pages Document (.pages)"
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
        case .markdown: "Markdown"
        case .wordDoc: "Word 97–2004"
        case .webArchive: "Web Archive"
        case .pdf: "PDF"
        case .pages: "Pages"
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
        case .markdown: "md"
        case .wordDoc: "doc"
        case .webArchive: "webarchive"
        case .pdf: "pdf"
        case .pages: "pages"
        }
    }

    /// Formats that store everything Wired Paper knows about a document.
    var isNative: Bool { self == .paper || self == .wiredPaper }

    /// Formats Wired Paper reads but can't write back. Opening one imports its
    /// text into a new untitled document, so saving never touches the original.
    var isImportOnly: Bool { self == .pdf || self == .pages }

    /// Whether saving in this format can drop content (images, tables, styles…).
    var isLossy: Bool {
        switch self {
        case .paper, .wiredPaper, .rtfd, .pdf: false
        default: true
        }
    }

    /// Formats offered by File ▸ Export…, in menu order.
    static let exportFormats: [DocumentFormat] = [.pdf, .docx, .paper, .rtf, .rtfd, .odt, .html, .markdown, .plainText, .wiredPaper]

    /// Resolves a type name handed to us by NSDocument (usually a UTI, possibly a
    /// more specific subtype such as public.utf8-plain-text).
    init?(typeName: String) {
        if let exact = DocumentFormat(rawValue: typeName) {
            self = exact
            return
        }
        // Pages has used several type identifiers (package, single file, '09);
        // some are unknown on Macs without Pages.
        if typeName.hasPrefix("com.apple.iwork.pages") {
            self = .pages
            return
        }
        guard let type = UTType(typeName) else { return nil }
        // Check the specific formats before the generic plain-text family.
        let ordered: [DocumentFormat] = [.paper, .wiredPaper, .rtfd, .rtf, .docx, .wordDoc, .odt, .html, .webArchive, .pdf, .pages, .markdown, .plainText]
        if let match = ordered.first(where: { type.conforms(to: $0.utType) }) {
            self = match
        } else if type.preferredFilenameExtension.map({ ["md", "markdown", "mdown", "mkd"].contains($0) }) == true {
            self = .markdown
        } else if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            // Any other text-based file (JSON, XML, CSV, YAML, logs, source code…) opens as plain text.
            self = .plainText
        } else {
            return nil
        }
    }
}
