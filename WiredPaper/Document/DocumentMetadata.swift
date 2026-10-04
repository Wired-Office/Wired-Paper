import Foundation

/// A run of text tagged with a named paragraph style. Stored alongside the
/// RTFD body in `.wiredpaper` packages because RTF has no place for it.
struct StyleRun: Codable, Equatable {
    var location: Int
    var length: Int
    var style: String
}

/// Everything in a `.wiredpaper` package besides the text itself.
/// Decoding is tolerant: unknown keys are ignored and missing keys fall back to
/// defaults, so older and newer app versions can read each other's files.
struct DocumentMetadata: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion = DocumentMetadata.currentFormatVersion
    var documentID = UUID().uuidString
    var generator = DocumentMetadata.generatorString
    var created = Date()
    var modified = Date()
    var pageSetup: PageSetup?
    var zoom: Double?
    var templateID: String?
    var properties = DocumentProperties()
    var headerFooter = HeaderFooterSettings()
    var decoration = PageDecoration()
    var theme: DocumentTheme?
    /// Edited built-in styles and custom styles.
    var styles: [StyleDefinition] = []
    var comments: [CommentThread] = []
    var revisions: [RevisionRecord] = []
    var tracking = TrackingSettings()
    var footnotes: [FootnoteRecord] = []
    var sources: [CitationSource] = []
    var citationStyle: CitationStyle = .apa
    var protection = ProtectionSettings()
    var signatures: [DigitalSignature] = []
    /// Mail-merge recipients (Mailings tab).
    var mailMerge: MailMergeData?
    /// Custom text attributes, keyed by attribute name.
    var attributeRuns: [String: [AttributeRun]] = [:]
    /// Legacy (format 1.0): paragraph style runs only.
    var styleRuns: [StyleRun] = []

    static var generatorString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Wired Paper \(version)"
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case formatVersion, documentID, generator, created, modified, pageSetup, zoom, templateID
        case properties, headerFooter, decoration, theme, styles, comments, revisions, tracking
        case footnotes, sources, citationStyle, protection, signatures, mailMerge, attributeRuns, styleRuns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = c.value(.formatVersion, default: 1)
        documentID = c.value(.documentID, default: UUID().uuidString)
        generator = c.value(.generator, default: "")
        created = c.value(.created, default: Date())
        modified = c.value(.modified, default: Date())
        pageSetup = c.value(.pageSetup, default: nil)
        zoom = c.value(.zoom, default: nil)
        templateID = c.value(.templateID, default: nil)
        properties = c.value(.properties, default: DocumentProperties())
        headerFooter = c.value(.headerFooter, default: HeaderFooterSettings())
        decoration = c.value(.decoration, default: PageDecoration())
        theme = c.value(.theme, default: nil)
        styles = c.value(.styles, default: [])
        comments = c.value(.comments, default: [])
        revisions = c.value(.revisions, default: [])
        tracking = c.value(.tracking, default: TrackingSettings())
        footnotes = c.value(.footnotes, default: [])
        sources = c.value(.sources, default: [])
        citationStyle = c.value(.citationStyle, default: .apa)
        protection = c.value(.protection, default: ProtectionSettings())
        signatures = c.value(.signatures, default: [])
        mailMerge = c.value(.mailMerge, default: nil)
        attributeRuns = c.value(.attributeRuns, default: [:])
        styleRuns = c.value(.styleRuns, default: [])
    }
}

/// A format-independent snapshot of a document, produced and consumed by codecs.
struct DocumentContents {
    var text: NSAttributedString
    var pageSetup: PageSetup?
    var metadata: DocumentMetadata?
}

enum WiredPaperError: LocalizedError {
    case unsupportedFormat(String)
    case corruptDocument(String)
    case newerFormatVersion(Int)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let type):
            "Wired Paper can’t open or save documents of type “\(type)”."
        case .corruptDocument:
            "The document is damaged or incomplete."
        case .newerFormatVersion:
            "This document was created by a newer version of Wired Paper."
        case .writeFailed:
            "The document couldn’t be saved."
        }
    }

    var failureReason: String? {
        switch self {
        case .corruptDocument(let reason), .writeFailed(let reason): reason
        case .newerFormatVersion(let version): "It uses document format version \(version)."
        case .unsupportedFormat: nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .newerFormatVersion: "Update Wired Paper to open this document."
        default: nil
        }
    }
}
