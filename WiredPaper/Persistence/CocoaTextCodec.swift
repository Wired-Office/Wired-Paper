import AppKit

/// Reads and writes formats supported by AppKit's attributed-string converters:
/// RTF, RTFD, DOCX, ODT and HTML.
struct CocoaTextCodec: DocumentCodec {
    let documentType: NSAttributedString.DocumentType

    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        var documentAttributes: NSDictionary?
        let text: NSAttributedString

        if documentType == .rtfd, fileWrapper.isDirectory {
            guard let rtfd = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: &documentAttributes) else {
                throw WiredPaperError.corruptDocument("The RTFD package could not be read.")
            }
            text = rtfd
        } else {
            guard let data = fileWrapper.regularFileContents else {
                throw WiredPaperError.corruptDocument("The file is empty or unreadable.")
            }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
            if documentType == .html {
                options[.characterEncoding] = String.Encoding.utf8.rawValue
            }
            do {
                text = try NSAttributedString(data: data, options: options, documentAttributes: &documentAttributes)
            } catch {
                throw WiredPaperError.corruptDocument(error.localizedDescription)
            }
        }

        var metadata = DocumentMetadata()
        metadata.properties = DocumentProperties(documentAttributes: documentAttributes)
        return DocumentContents(
            text: text,
            pageSetup: PageSetup(documentAttributes: documentAttributes),
            metadata: metadata
        )
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        let text = contents.text
        let range = NSRange(location: 0, length: text.length)
        var attributes = contents.pageSetup?.documentAttributes ?? [:]
        attributes[.documentType] = documentType
        if let properties = contents.metadata?.properties {
            attributes.merge(properties.documentAttributes) { current, _ in current }
        }

        if documentType == .rtfd {
            guard let wrapper = text.rtfdFileWrapper(from: range, documentAttributes: attributes) else {
                throw WiredPaperError.writeFailed("The RTFD package could not be created.")
            }
            return wrapper
        }

        if documentType == .html {
            attributes[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        do {
            let data = try text.data(from: range, documentAttributes: attributes)
            return FileWrapper(regularFileWithContents: data)
        } catch {
            throw WiredPaperError.writeFailed(error.localizedDescription)
        }
    }
}

/// Plain text: UTF-8 on write, with sensible encoding detection on read.
struct PlainTextCodec: DocumentCodec {
    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        guard let data = fileWrapper.regularFileContents else {
            throw WiredPaperError.corruptDocument("The file is empty or unreadable.")
        }
        let string = Self.decode(data)
        return DocumentContents(
            text: NSAttributedString(string: string, attributes: defaultAttributes),
            pageSetup: nil,
            metadata: nil
        )
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        // Attachments are represented by U+FFFC in the backing string; drop them.
        let string = contents.text.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        return FileWrapper(regularFileWithContents: Data(string.utf8))
    }

    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var converted: NSString?
        let detected = NSString.stringEncoding(
            for: data,
            encodingOptions: [.suggestedEncodingsKey: [String.Encoding.utf16.rawValue, String.Encoding.windowsCP1252.rawValue]],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        if detected != 0, let converted { return converted as String }
        return String(decoding: data, as: UTF8.self)
    }
}
