import AppKit
import Compression
import PDFKit

/// Import-only codecs: they pull the text out of formats Wired Paper can't
/// write (see `DocumentFormat.isImportOnly`). Layout, images and styling are
/// left behind; the result is ordinary paragraphs in the Normal style.
private func importedText(_ paragraphs: [String], attributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
    let kept = paragraphs.map { $0.trimmingCharacters(in: .whitespaces) }
    guard kept.contains(where: { !$0.isEmpty }) else {
        throw WiredPaperError.corruptDocument("The file contains no text that Wired Paper can import.")
    }
    var lines = kept
    while lines.last?.isEmpty == true { lines.removeLast() }
    return DocumentContents(
        text: NSAttributedString(string: lines.joined(separator: "\n") + "\n", attributes: attributes),
        pageSetup: nil,
        metadata: nil
    )
}

private func importOnlyWriteError(_ format: DocumentFormat) -> Error {
    WiredPaperError.unsupportedFormat(format.displayName)
}

// MARK: - PDF

/// Extracts the text layer of a PDF. Scanned PDFs without one are rejected.
struct PDFTextCodec: DocumentCodec {
    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        guard let data = fileWrapper.regularFileContents, let pdf = PDFDocument(data: data) else {
            throw WiredPaperError.corruptDocument("The PDF could not be read.")
        }
        if pdf.isLocked {
            throw WiredPaperError.corruptDocument("The PDF is password-protected.")
        }
        var paragraphs: [String] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index)?.string else { continue }
            paragraphs += Self.paragraphs(fromPageText: page)
        }
        return try importedText(paragraphs, attributes: defaultAttributes)
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        throw importOnlyWriteError(.pdf)
    }

    /// PDF text comes as visual lines. Joins lines that continue a sentence
    /// into one paragraph and keeps breaks where a paragraph plausibly ends.
    static func paragraphs(fromPageText text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current) }
                current = ""
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), line.first?.isLowercase == true {
                current.removeLast()                    // re-join a hyphenated word
                current += line
            } else if continues(current, with: line) {
                current += " " + line
            } else {
                paragraphs.append(current)
                current = line
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    private static func continues(_ previous: String, with next: String) -> Bool {
        guard let last = previous.last, let first = next.first else { return false }
        if ".!?:;\"”»)".contains(last) { return first.isLowercase }
        // Bullets and numbered items start their own paragraph.
        if "•◦▪–-*".contains(first) { return false }
        return true
    }
}

// MARK: - Pages

/// Extracts the body text of an Apple Pages document.
///
/// Pages 5 and later store a document as protobuf messages in Snappy-compressed
/// `.iwa` files inside `Index/` (in a ZIP, or an `Index.zip` within a package).
/// The body text sits in `TSWP.StorageArchive` messages. Pages '09 used an
/// XML file (`index.xml`, possibly gzipped) instead; both are handled.
struct PagesTextCodec: DocumentCodec {
    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        let files = try Self.files(in: fileWrapper)

        let archives = files.keys.filter { $0.hasPrefix("Index/") && $0.hasSuffix(".iwa") }.sorted { lhs, rhs in
            // Document.iwa holds the body; read it first.
            (lhs == "Index/Document.iwa" ? 0 : 1, lhs) < (rhs == "Index/Document.iwa" ? 0 : 1, rhs)
        }
        if !archives.isEmpty {
            var storages: [IWAStorage] = []
            for name in archives {
                guard let data = files[name] else { continue }
                storages += try IWAReader.storages(in: data)
            }
            let body = storages.filter { $0.kind == IWAStorage.body }
            // Page-layout documents have no body; their text lives in text boxes.
            let chosen = body.isEmpty ? storages.filter { $0.kind == IWAStorage.textBox } : body
            let text = chosen.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            return try importedText(Self.paragraphs(fromStorageText: text), attributes: defaultAttributes)
        }

        if let xml = files["index.xml"] ?? files["index.xml.gz"].flatMap(Gzip.decompress) {
            return try importedText(Pages09Reader.paragraphs(in: xml), attributes: defaultAttributes)
        }
        throw WiredPaperError.corruptDocument("The Pages document has no readable content.")
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        throw importOnlyWriteError(.pages)
    }

    /// The files of a Pages document, by path, whether it's a ZIP or a package.
    static func files(in wrapper: FileWrapper) throws -> [String: Data] {
        if wrapper.isRegularFile, let data = wrapper.regularFileContents {
            return try ZipArchive.read(data)
        }
        var files: [String: Data] = [:]
        func collect(_ wrapper: FileWrapper, path: String) {
            for (name, child) in wrapper.fileWrappers ?? [:] {
                let childPath = path.isEmpty ? name : path + "/" + name
                if child.isDirectory {
                    collect(child, path: childPath)
                } else if let data = child.regularFileContents {
                    files[childPath] = data
                }
            }
        }
        collect(wrapper, path: "")
        if let index = files["Index.zip"] {
            for (name, data) in try ZipArchive.read(index) {
                files[name.hasPrefix("Index/") ? name : "Index/" + name] = data
            }
        }
        return files
    }

    /// Maps Pages' special characters to plain paragraphs.
    static func paragraphs(fromStorageText text: String) -> [String] {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x2029, 0x0A, 0x0D, 0x04, 0x05, 0x0C:   // paragraph, section, column and page breaks
                result.append("\n")
            case 0x2028:
                result.unicodeScalars.append(scalar)      // line break within a paragraph
            case 0x09:
                result.append("\t")
            case 0xFFFC, 0x0E, 0x0F:                      // attachments, footnote and object markers
                continue
            case 0..<0x20:
                continue
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result.components(separatedBy: "\n")
    }
}

/// A run of text found in an `.iwa` archive.
struct IWAStorage {
    static let body = 0
    static let textBox = 3

    var kind: Int
    var text: String
}

/// Reads the iWork Archive (`.iwa`) container: Snappy-compressed chunks holding
/// length-prefixed `ArchiveInfo` headers, each followed by its messages.
enum IWAReader {
    /// `TSWP.StorageArchive` type ids (Pages uses both).
    private static let storageTypes: Set<UInt64> = [2001, 2005]

    static func storages(in data: Data) throws -> [IWAStorage] {
        let stream = try decompress(data)
        var storages: [IWAStorage] = []
        var reader = ProtobufReader(stream)
        while !reader.isAtEnd {
            let infoLength = try reader.varint()
            var info = ProtobufReader(try reader.bytes(Int(infoLength)))
            var messages: [(type: UInt64, length: Int)] = []
            while !info.isAtEnd {
                let field = try info.field()
                if field.number == 2, case .bytes(let bytes) = field.value {
                    var message = ProtobufReader(bytes)
                    var type: UInt64 = 0
                    var length = 0
                    while !message.isAtEnd {
                        let messageField = try message.field()
                        if case .varint(let value) = messageField.value {
                            if messageField.number == 1 { type = value }
                            if messageField.number == 3 { length = Int(value) }
                        }
                    }
                    messages.append((type, length))
                }
            }
            for message in messages {
                let payload = try reader.bytes(message.length)
                if storageTypes.contains(message.type), let storage = try? storage(from: payload) {
                    storages.append(storage)
                }
            }
        }
        return storages
    }

    /// `TSWP.StorageArchive`: field 1 is the kind, field 3 the (repeated) text.
    private static func storage(from payload: [UInt8]) throws -> IWAStorage {
        var reader = ProtobufReader(payload)
        var kind = -1
        var text = ""
        while !reader.isAtEnd {
            let field = try reader.field()
            switch (field.number, field.value) {
            case (1, .varint(let value)): kind = Int(value)
            case (3, .bytes(let bytes)): text += String(decoding: bytes, as: UTF8.self)
            default: break
            }
        }
        return IWAStorage(kind: kind, text: text)
    }

    /// Each chunk: a 0x00 marker, a 24-bit little-endian length, then a raw Snappy block.
    private static func decompress(_ data: Data) throws -> [UInt8] {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        var cursor = 0
        while cursor + 4 <= bytes.count {
            guard bytes[cursor] == 0 else { throw WiredPaperError.corruptDocument("Unexpected IWA chunk.") }
            let length = Int(bytes[cursor + 1]) | Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3]) << 16
            cursor += 4
            guard cursor + length <= bytes.count else { throw WiredPaperError.corruptDocument("Truncated IWA chunk.") }
            output += try Snappy.decompress(bytes[cursor..<(cursor + length)])
            cursor += length
        }
        return output
    }
}

/// Decoder for raw Snappy blocks (no framing format).
enum Snappy {
    static func decompress(_ input: ArraySlice<UInt8>) throws -> [UInt8] {
        let bytes = Array(input)
        var reader = ProtobufReader(bytes)
        let expected = Int(try reader.varint())
        var cursor = reader.position
        var output: [UInt8] = []
        output.reserveCapacity(expected)

        func readLE(_ count: Int) throws -> Int {
            guard cursor + count <= bytes.count else { throw WiredPaperError.corruptDocument("Truncated Snappy data.") }
            var value = 0
            for index in 0..<count { value |= Int(bytes[cursor + index]) << (8 * index) }
            cursor += count
            return value
        }

        func copy(offset: Int, length: Int) throws {
            guard offset > 0, offset <= output.count else { throw WiredPaperError.corruptDocument("Invalid Snappy copy.") }
            let start = output.count - offset
            // Copies may overlap their own output (run-length style), so go byte by byte.
            for index in 0..<length { output.append(output[start + index]) }
        }

        while cursor < bytes.count {
            let tag = Int(bytes[cursor])
            cursor += 1
            switch tag & 3 {
            case 0:
                var length = tag >> 2
                if length >= 60 { length = try readLE(length - 59) }
                length += 1
                guard cursor + length <= bytes.count else { throw WiredPaperError.corruptDocument("Truncated Snappy literal.") }
                output += bytes[cursor..<(cursor + length)]
                cursor += length
                continue
            case 1:
                let length = ((tag >> 2) & 7) + 4
                let low = try readLE(1)
                let offset = (tag >> 5) << 8 | low
                try copy(offset: offset, length: length)
            case 2:
                try copy(offset: try readLE(2), length: (tag >> 2) + 1)
            default:
                try copy(offset: try readLE(4), length: (tag >> 2) + 1)
            }
        }
        return output
    }
}

/// Just enough of the protobuf wire format to walk untyped messages.
struct ProtobufReader {
    enum Value {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed
    }

    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { position >= bytes.count }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < bytes.count, shift < 64 else { throw WiredPaperError.corruptDocument("Malformed varint.") }
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, position + count <= bytes.count else { throw WiredPaperError.corruptDocument("Truncated message.") }
        defer { position += count }
        return Array(bytes[position..<(position + count)])
    }

    mutating func field() throws -> (number: UInt64, value: Value) {
        let key = try varint()
        switch key & 7 {
        case 0: return (key >> 3, .varint(try varint()))
        case 1: _ = try bytes(8); return (key >> 3, .fixed)
        case 2: return (key >> 3, .bytes(try bytes(Int(try varint()))))
        case 5: _ = try bytes(4); return (key >> 3, .fixed)
        default: throw WiredPaperError.corruptDocument("Unsupported protobuf wire type.")
        }
    }
}

/// Pages '09: the body is a sequence of `sf:p` elements inside `sf:text-body`.
private final class Pages09Reader: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var current: String?
    private var bodyDepth = 0

    static func paragraphs(in data: Data) throws -> [String] {
        let reader = Pages09Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw WiredPaperError.corruptDocument(parser.parserError?.localizedDescription ?? "The Pages '09 XML could not be read.")
        }
        return reader.paragraphs
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "sf:text-body": bodyDepth += 1
        case "sf:p" where bodyDepth > 0: current = ""
        case "sf:tab" where current != nil: current? += "\t"
        case "sf:br", "sf:lnbr": current? += "\u{2028}"
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "sf:text-body": bodyDepth -= 1
        case "sf:p":
            if let current { paragraphs.append(current) }
            current = nil
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current? += string
    }
}

enum Gzip {
    /// Strips the gzip header and trailer and inflates the raw DEFLATE stream between.
    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var cursor = 10
        if flags & 4 != 0, cursor + 2 <= bytes.count {                 // FEXTRA
            cursor += 2 + (Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8)
        }
        if flags & 8 != 0 { while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }; cursor += 1 }   // FNAME
        if flags & 16 != 0 { while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }; cursor += 1 }  // FCOMMENT
        if flags & 2 != 0 { cursor += 2 }                               // FHCRC
        guard cursor < bytes.count - 8 else { return nil }
        let size = Int(bytes[bytes.count - 4]) | Int(bytes[bytes.count - 3]) << 8
            | Int(bytes[bytes.count - 2]) << 16 | Int(bytes[bytes.count - 1]) << 24
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let deflated = Array(bytes[cursor..<(bytes.count - 8)])
        let written = compression_decode_buffer(&output, size, deflated, deflated.count, nil, COMPRESSION_ZLIB)
        return written == size ? Data(output) : nil
    }
}
