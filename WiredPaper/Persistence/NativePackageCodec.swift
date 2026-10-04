import AppKit

/// Reads and writes `.wiredpaper` documents.
///
/// A `.wiredpaper` document is a package (a folder the Finder shows as one file):
///
///     Report.wiredpaper/
///       Content.rtfd/      the text, formatting, tables and images (standard RTFD)
///       Document.json      page setup, named styles and other metadata
///
/// Storing the body as RTFD keeps the content readable by other tools even
/// without Wired Paper, while the JSON sidecar holds what RTF can't express.
struct NativePackageCodec: DocumentCodec {
    static let contentFilename = "Content.rtfd"
    static let metadataFilename = "Document.json"

    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        guard fileWrapper.isDirectory, let children = fileWrapper.fileWrappers else {
            throw WiredPaperError.corruptDocument("The document package is missing.")
        }
        guard let contentWrapper = children[Self.contentFilename],
              let text = NSAttributedString(rtfdFileWrapper: contentWrapper, documentAttributes: nil)
        else {
            throw WiredPaperError.corruptDocument("The document’s text could not be read.")
        }

        // Metadata is optional: a damaged or missing Document.json must never
        // prevent the user from getting their text back.
        var metadata = DocumentMetadata()
        if let data = children[Self.metadataFilename]?.regularFileContents,
           let decoded = try? Self.decoder.decode(DocumentMetadata.self, from: data) {
            metadata = decoded
        }
        guard metadata.formatVersion <= DocumentMetadata.currentFormatVersion else {
            throw WiredPaperError.newerFormatVersion(metadata.formatVersion)
        }

        let mutable = NSMutableAttributedString(attributedString: text)
        // Format 1.0 stored only paragraph styles.
        for run in metadata.styleRuns where run.length > 0 && run.location + run.length <= mutable.length {
            mutable.addAttribute(.wpParagraphStyle, value: run.style, range: NSRange(location: run.location, length: run.length))
        }
        PersistentAttributes.restore(metadata.attributeRuns, into: mutable)
        metadata.styleRuns = []
        return DocumentContents(text: mutable, pageSetup: metadata.pageSetup, metadata: metadata)
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        let text = contents.text
        let range = NSRange(location: 0, length: text.length)
        var attributes = contents.pageSetup?.documentAttributes ?? [:]
        attributes[.documentType] = NSAttributedString.DocumentType.rtfd
        if let properties = contents.metadata?.properties {
            attributes.merge(properties.documentAttributes) { current, _ in current }
        }

        guard let contentWrapper = text.rtfdFileWrapper(from: range, documentAttributes: attributes) else {
            throw WiredPaperError.writeFailed("The document’s text could not be encoded.")
        }
        contentWrapper.preferredFilename = Self.contentFilename

        var metadata = contents.metadata ?? DocumentMetadata()
        metadata.pageSetup = contents.pageSetup
        metadata.attributeRuns = PersistentAttributes.collect(from: text)
        metadata.styleRuns = []
        let json = try Self.encoder.encode(metadata)
        let metadataWrapper = FileWrapper(regularFileWithContents: json)
        metadataWrapper.preferredFilename = Self.metadataFilename

        return FileWrapper(directoryWithFileWrappers: [
            Self.contentFilename: contentWrapper,
            Self.metadataFilename: metadataWrapper,
        ])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
