import AppKit

/// Converts between a file (as a FileWrapper) and format-independent document contents.
///
/// Every format goes through this protocol, so a format's implementation can be
/// swapped without touching the document or editor. For example, DOCX currently
/// uses AppKit's built-in converter; a dedicated OOXML codec with better
/// fidelity (styles, headers, footnotes) can replace it by changing one line in
/// `DocumentCodecRegistry`.
protocol DocumentCodec {
    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents
    func write(_ contents: DocumentContents) throws -> FileWrapper
}

enum DocumentCodecRegistry {
    static func codec(for format: DocumentFormat) throws -> DocumentCodec {
        switch format {
        case .paper: PaperFileCodec()
        case .wiredPaper: NativePackageCodec()
        case .rtf: CocoaTextCodec(documentType: .rtf)
        case .rtfd: CocoaTextCodec(documentType: .rtfd)
        case .docx: CocoaTextCodec(documentType: .officeOpenXML)
        case .odt: CocoaTextCodec(documentType: .openDocument)
        case .html: CocoaTextCodec(documentType: .html)
        case .plainText: PlainTextCodec()
        case .pdf:
            // PDF is export-only and produced by the print system (see PDFExporter).
            throw WiredPaperError.unsupportedFormat(format.displayName)
        }
    }
}
