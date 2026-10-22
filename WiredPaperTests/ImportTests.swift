import AppKit
import XCTest
@testable import WiredPaper

final class ImportTests: XCTestCase {
    private let normal = StyleCatalog.attributes(for: .normal)

    // MARK: Formats

    func testTextBasedTypesResolveToReadableFormats() {
        XCTAssertEqual(DocumentFormat(typeName: "public.json"), .plainText)
        XCTAssertEqual(DocumentFormat(typeName: "public.swift-source"), .plainText)
        XCTAssertEqual(DocumentFormat(typeName: "public.comma-separated-values-text"), .plainText)
        XCTAssertEqual(DocumentFormat(typeName: "net.daringfireball.markdown"), .markdown)
        XCTAssertEqual(DocumentFormat(typeName: "com.adobe.pdf"), .pdf)
        XCTAssertEqual(DocumentFormat(typeName: "com.apple.iwork.pages.pages"), .pages)
        XCTAssertEqual(DocumentFormat(typeName: "com.microsoft.word.doc"), .wordDoc)
        XCTAssertEqual(DocumentFormat(typeName: "public.html"), .html)
        XCTAssertNil(DocumentFormat(typeName: "public.png"))
        XCTAssertTrue(DocumentFormat.pdf.isImportOnly)
        XCTAssertFalse(DocumentFormat.markdown.isImportOnly)
    }

    func testDocumentControllerAcceptsTextFiles() throws {
        let controller = NSDocumentController.shared
        for (name, contents) in [("notes.md", "# Hi"), ("data.json", "{}"), ("main.swift", "let x = 1"), ("table.csv", "a,b")] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let type = try controller.typeForContents(of: url)
            XCTAssertNotNil(controller.documentClass(forType: type), "\(name) → \(type)")
            XCTAssertNotNil(DocumentFormat(typeName: type), "\(name) → \(type)")
        }
    }

    // MARK: Markdown

    func testMarkdownReadsHeadingsEmphasisListsAndCode() throws {
        let source = """
        # Title

        Some **bold**, *italic* and `code` with a [link](https://example.com).

        - one
        - two
            1. nested

        > quoted

        ```
        let x = 1
        let y = 2
        ```
        """
        let contents = try MarkdownCodec().read(from: FileWrapper(regularFileWithContents: Data(source.utf8)), defaultAttributes: normal)
        let text = contents.text
        let string = text.string as NSString
        let paragraphs = text.string.components(separatedBy: "\n")

        XCTAssertEqual(paragraphs[0], "Title")
        XCTAssertEqual(text.attribute(.wpParagraphStyle, at: 0, effectiveRange: nil) as? String, "heading1")

        let bold = text.attribute(.font, at: string.range(of: "bold").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let italic = text.attribute(.font, at: string.range(of: "italic").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        let code = text.attribute(.font, at: string.range(of: "code").location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(code.isFixedPitch)
        XCTAssertNotNil(text.attribute(.link, at: string.range(of: "link").location, effectiveRange: nil))

        XCTAssertTrue(paragraphs.contains("\t•\tone"))
        XCTAssertTrue(paragraphs.contains("\t•\ttwo"))
        let nested = string.range(of: "nested").location
        let nestedStyle = text.attribute(.paragraphStyle, at: nested, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(nestedStyle.textLists.count, 2)

        XCTAssertEqual(text.attribute(.wpParagraphStyle, at: string.range(of: "quoted").location, effectiveRange: nil) as? String, "quote")
        XCTAssertTrue(paragraphs.contains("let x = 1"))
        XCTAssertTrue(paragraphs.contains("let y = 2"))
        XCTAssertEqual(text.attribute(.wpParagraphStyle, at: string.range(of: "let y").location, effectiveRange: nil) as? String, "code")
    }

    func testMarkdownRoundTrip() throws {
        let source = """
        # Title

        Some **bold**, *italic* and `code` with a [link](https://example.com).

        - one
        - two

        1. first
        2. second

        > quoted

        ```
        let x = 1
        ```

        Plain 2 \\* 3.

        """
        let codec = MarkdownCodec()
        let contents = try codec.read(from: FileWrapper(regularFileWithContents: Data(source.utf8)), defaultAttributes: normal)
        let written = try codec.write(contents)
        let markdown = String(decoding: written.regularFileContents!, as: UTF8.self)
        XCTAssertEqual(markdown, source)
    }

    // MARK: PDF

    func testPDFImportExtractsAndReflowsText() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for page in ["First paragraph line one\ncontinues here.\n\nSecond paragraph.", "Page two."] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (page as NSString).draw(in: CGRect(x: 72, y: 72, width: 468, height: 648), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()

        let contents = try PDFTextCodec().read(from: FileWrapper(regularFileWithContents: data as Data), defaultAttributes: normal)
        XCTAssertEqual(contents.text.string, "First paragraph line one continues here.\nSecond paragraph.\nPage two.\n")
    }

    func testPDFReflowJoinsHyphenatedWordsAndKeepsBullets() {
        XCTAssertEqual(
            PDFTextCodec.paragraphs(fromPageText: "An exam-\nple sentence that\nwraps.\n• Bullet one\n• Bullet two"),
            ["An example sentence that wraps.", "• Bullet one", "• Bullet two"]
        )
    }

    func testImportedPDFOpensAsUntitledDocument() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Report \(UUID().uuidString).pdf")
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 300)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("Hello PDF" as NSString).draw(at: CGPoint(x: 20, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        NSGraphicsContext.current = nil
        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let controller = WiredPaperDocumentController()
        let document = try controller.makeDocument(withContentsOf: url, ofType: "com.adobe.pdf") as! WiredPaperDocument
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.format, .paper)
        XCTAssertEqual(document.importedFormat, .pdf)
        XCTAssertEqual(document.displayName, url.deletingPathExtension().lastPathComponent)
        XCTAssertEqual(document.textStorage.string, "Hello PDF\n")
    }

    // MARK: Pages

    func testPagesImportReadsBodyStorageFromIWA() throws {
        let body = "Heading\u{2029}Body text\u{FFFC} here."
        var storage = protobufField(1, varint: 0)                      // kind = BODY
        storage += protobufField(3, bytes: Array(body.utf8))
        let textBox = protobufField(1, varint: 3) + protobufField(3, bytes: Array("Ignored box".utf8))

        var stream: [UInt8] = []
        for (identifier, payload) in [(UInt64(1), storage), (2, textBox)] {
            let messageInfo = protobufField(1, varint: 2001) + protobufField(3, varint: UInt64(payload.count))
            let archiveInfo = protobufField(1, varint: identifier) + protobufField(2, bytes: messageInfo)
            stream += varint(UInt64(archiveInfo.count)) + archiveInfo + payload
        }
        let iwa = Data([0] + littleEndian24(snappyLiteral(stream).count) + snappyLiteral(stream))
        let zip = ZipArchive.write([(path: "Index/Document.iwa", data: iwa)])

        let contents = try PagesTextCodec().read(from: FileWrapper(regularFileWithContents: zip), defaultAttributes: normal)
        XCTAssertEqual(contents.text.string, "Heading\nBody text here.\n")
    }

    func testSnappyDecodesCopies() throws {
        // "abcd" literal, then copy 8 bytes at offset 4 (overlapping) → "abcdabcdabcd".
        let block: [UInt8] = [12, 0b0000_1100, 0x61, 0x62, 0x63, 0x64, 0b0001_0001, 4]
        XCTAssertEqual(String(decoding: try Snappy.decompress(block[...]), as: UTF8.self), "abcdabcdabcd")
    }

    func testRealPagesDocumentIfAvailable() throws {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~Pages/Documents")
        guard let file = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL }).first(where: { $0.pathExtension == "pages" }),
            let wrapper = try? FileWrapper(url: file, options: .immediate)
        else { throw XCTSkip("No Pages document on this Mac") }
        let contents = try PagesTextCodec().read(from: wrapper, defaultAttributes: normal)
        XCTAssertFalse(contents.text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        print("Imported \(file.lastPathComponent): \(contents.text.length) characters")
    }

    // MARK: Helpers

    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private func protobufField(_ number: UInt64, varint value: UInt64) -> [UInt8] {
        varint(number << 3) + varint(value)
    }

    private func protobufField(_ number: UInt64, bytes: [UInt8]) -> [UInt8] {
        varint(number << 3 | 2) + varint(UInt64(bytes.count)) + bytes
    }

    /// A Snappy block holding `data` as literals (at most 256 bytes per literal element).
    private func snappyLiteral(_ data: [UInt8]) -> [UInt8] {
        var block = varint(UInt64(data.count))
        var start = 0
        while start < data.count {
            let chunk = data[start..<min(start + 256, data.count)]
            block += [60 << 2, UInt8(chunk.count - 1)] + chunk
            start += chunk.count
        }
        return block
    }

    private func littleEndian24(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF)]
    }
}
