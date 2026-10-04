import AppKit
import XCTest
@testable import WiredPaper

final class PersistenceTests: XCTestCase {
    private func sampleText() -> NSAttributedString {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Quarterly Review\n", attributes: StyleCatalog.attributes(for: .heading1)))
        var body = StyleCatalog.attributes(for: .normal)
        text.append(NSAttributedString(string: "Plain and ", attributes: body))
        body[.font] = NSFontManager.shared.convert(StyleCatalog.bodyFont, toHaveTrait: .boldFontMask)
        text.append(NSAttributedString(string: "bold", attributes: body))
        text.append(NSAttributedString(string: " text.\n", attributes: StyleCatalog.attributes(for: .normal)))
        return text
    }

    private func imageAttachment() -> NSTextAttachment {
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let wrapper = FileWrapper(regularFileWithContents: rep.representation(using: .png, properties: [:])!)
        wrapper.preferredFilename = "swatch.png"
        return NSTextAttachment(fileWrapper: wrapper)
    }

    func testNativePackageRoundTripPreservesTextStylesImagesAndPageSetup() throws {
        let text = NSMutableAttributedString(attributedString: sampleText())
        text.append(NSAttributedString(attachment: imageAttachment()))
        text.append(NSAttributedString(string: "\n"))
        let setup = PageSetup(paperSize: PaperPreset.a4.size, margins: Margins(top: 50, left: 60, bottom: 70, right: 80))
        var metadata = DocumentMetadata()
        metadata.templateID = "report"

        let codec = NativePackageCodec()
        let wrapper = try codec.write(DocumentContents(text: text, pageSetup: setup, metadata: metadata))
        XCTAssertTrue(wrapper.isDirectory)
        XCTAssertNotNil(wrapper.fileWrappers?[NativePackageCodec.contentFilename])
        XCTAssertNotNil(wrapper.fileWrappers?[NativePackageCodec.metadataFilename])

        // Round-trip through disk, as NSDocument would.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wiredpaper")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let reread = try FileWrapper(url: url, options: .immediate)

        let contents = try codec.read(from: reread, defaultAttributes: [:])
        XCTAssertEqual(contents.text.string, text.string)
        XCTAssertEqual(contents.pageSetup, setup)
        XCTAssertEqual(contents.metadata?.templateID, "report")

        let boldLocation = (contents.text.string as NSString).range(of: "bold").location
        let boldFont = contents.text.attribute(.font, at: boldLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont!).contains(.boldFontMask))

        let heading = contents.text.attribute(.wpParagraphStyle, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(heading, ParagraphStyleKind.heading1.rawValue)

        var attachmentCount = 0
        contents.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: contents.text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, attachment.fileWrapper?.regularFileContents != nil { attachmentCount += 1 }
        }
        XCTAssertEqual(attachmentCount, 1)
    }

    func testNativePackageToleratesMissingMetadata() throws {
        let wrapper = try NativePackageCodec().write(DocumentContents(text: sampleText(), pageSetup: nil, metadata: nil))
        wrapper.removeFileWrapper(wrapper.fileWrappers![NativePackageCodec.metadataFilename]!)
        let contents = try NativePackageCodec().read(from: wrapper, defaultAttributes: [:])
        XCTAssertEqual(contents.text.string, sampleText().string)
    }

    func testNativePackageRejectsNewerFormatVersion() throws {
        var metadata = DocumentMetadata()
        metadata.formatVersion = DocumentMetadata.currentFormatVersion + 1
        let wrapper = try NativePackageCodec().write(DocumentContents(text: sampleText(), pageSetup: nil, metadata: metadata))
        XCTAssertThrowsError(try NativePackageCodec().read(from: wrapper, defaultAttributes: [:]))
    }

    func testCorruptPackageThrows() {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        XCTAssertThrowsError(try NativePackageCodec().read(from: wrapper, defaultAttributes: [:]))
    }

    func testPaperFileRoundTripIsOneFileAndLossless() throws {
        let text = NSMutableAttributedString(attributedString: sampleText())
        text.append(NSAttributedString(attachment: imageAttachment()))
        text.append(NSAttributedString(string: "\n"))
        let setup = PageSetup(paperSize: PaperPreset.a4.size, margins: Margins(top: 50, left: 60, bottom: 70, right: 80))
        var metadata = DocumentMetadata()
        metadata.templateID = "report"

        let codec = PaperFileCodec()
        let wrapper = try codec.write(DocumentContents(text: text, pageSetup: setup, metadata: metadata))
        XCTAssertTrue(wrapper.isRegularFile)
        let data = try XCTUnwrap(wrapper.regularFileContents)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "a .paper file is a ZIP archive")

        let entries = try ZipArchive.read(data)
        XCTAssertEqual(entries[PaperFileCodec.mimeTypeFilename].map { String(decoding: $0, as: UTF8.self) }, PaperFileCodec.mimeType)
        XCTAssertNotNil(entries[NativePackageCodec.metadataFilename])
        XCTAssertNotNil(entries["\(NativePackageCodec.contentFilename)/TXT.rtf"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("paper")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = try codec.read(from: try FileWrapper(url: url, options: .immediate), defaultAttributes: [:])

        XCTAssertEqual(contents.text.string, text.string)
        XCTAssertEqual(contents.pageSetup, setup)
        XCTAssertEqual(contents.metadata?.templateID, "report")
        let heading = contents.text.attribute(.wpParagraphStyle, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(heading, ParagraphStyleKind.heading1.rawValue)
        var attachmentCount = 0
        contents.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: contents.text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, attachment.fileWrapper?.regularFileContents != nil { attachmentCount += 1 }
        }
        XCTAssertEqual(attachmentCount, 1)
    }

    func testPaperFileRejectsGarbageAndForeignZips() {
        XCTAssertThrowsError(try PaperFileCodec().read(from: FileWrapper(regularFileWithContents: Data("not a zip".utf8)), defaultAttributes: [:]))
        let foreign = ZipArchive.write([("mimetype", Data("application/epub+zip".utf8))])
        XCTAssertThrowsError(try PaperFileCodec().read(from: FileWrapper(regularFileWithContents: foreign), defaultAttributes: [:]))
    }

    func testZipReaderInflatesDeflatedEntries() throws {
        // Written by `zip -9` so the entry is deflated, as a re-zipped file would be.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = String(repeating: "Wired Paper ", count: 500)
        try body.write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = directory
        zip.arguments = ["-q", "-9", "out.zip", "a.txt"]
        try zip.run()
        zip.waitUntilExit()
        let entries = try ZipArchive.read(Data(contentsOf: directory.appendingPathComponent("out.zip")))
        XCTAssertEqual(entries["a.txt"].map { String(decoding: $0, as: UTF8.self) }, body)
    }

    func testPaperDocumentExportsToDOCXAndPDF() throws {
        let document = WiredPaperDocument()
        document.textStorage.setAttributedString(sampleText())
        let paper = try document.fileWrapper(ofType: DocumentFormat.paper.typeIdentifier)
        let reopened = WiredPaperDocument()
        try reopened.read(from: paper, ofType: DocumentFormat.paper.typeIdentifier)

        let docx = try reopened.fileWrapper(ofType: DocumentFormat.docx.typeIdentifier)
        let docxText = try DocumentCodecRegistry.codec(for: .docx).read(from: docx, defaultAttributes: [:]).text.string
        XCTAssertTrue(docxText.contains("Quarterly Review"))
        XCTAssertTrue(DocumentFormat.exportFormats.contains(.docx))
        XCTAssertTrue(DocumentFormat.exportFormats.contains(.pdf))
    }

    func testRTFRoundTripKeepsBoldAndPaperSize() throws {
        let setup = PageSetup.standard(.a4)
        let codec = try DocumentCodecRegistry.codec(for: .rtf)
        let wrapper = try codec.write(DocumentContents(text: sampleText(), pageSetup: setup, metadata: nil))
        let contents = try codec.read(from: wrapper, defaultAttributes: [:])
        XCTAssertEqual(contents.text.string, sampleText().string)
        XCTAssertEqual(contents.pageSetup?.paperSize.width ?? 0, setup.paperSize.width, accuracy: 1)
        let location = (contents.text.string as NSString).range(of: "bold").location
        let font = contents.text.attribute(.font, at: location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testDOCXAndODTRoundTripText() throws {
        for format in [DocumentFormat.docx, .odt, .html, .rtfd] {
            let codec = try DocumentCodecRegistry.codec(for: format)
            let wrapper = try codec.write(DocumentContents(text: sampleText(), pageSetup: .standard(.letter), metadata: nil))
            let contents = try codec.read(from: wrapper, defaultAttributes: [:])
            XCTAssertTrue(contents.text.string.contains("Quarterly Review"), "\(format)")
            XCTAssertTrue(contents.text.string.contains("bold text."), "\(format)")
        }
    }

    func testPlainTextUsesDefaultAttributesAndDropsAttachments() throws {
        let codec = PlainTextCodec()
        let text = NSMutableAttributedString(string: "Hello ")
        text.append(NSAttributedString(attachment: imageAttachment()))
        text.append(NSAttributedString(string: "world"))
        let wrapper = try codec.write(DocumentContents(text: text, pageSetup: nil, metadata: nil))
        XCTAssertEqual(String(data: wrapper.regularFileContents!, encoding: .utf8), "Hello world")

        let defaults = StyleCatalog.attributes(for: .normal)
        let contents = try codec.read(from: wrapper, defaultAttributes: defaults)
        XCTAssertEqual(contents.text.string, "Hello world")
        XCTAssertNotNil(contents.text.attribute(.font, at: 0, effectiveRange: nil))
    }

    func testPlainTextDecodesUTF16() {
        let data = "Grüße".data(using: .utf16)!
        XCTAssertEqual(PlainTextCodec.decode(data), "Grüße")
    }

    func testFormatResolution() {
        XCTAssertEqual(DocumentFormat(typeName: "public.utf8-plain-text"), .plainText)
        XCTAssertEqual(DocumentFormat(typeName: "com.apple.rtfd"), .rtfd)
        XCTAssertEqual(DocumentFormat(typeName: "public.rtf"), .rtf)
        XCTAssertEqual(DocumentFormat(typeName: "com.wiredpaper.document"), .wiredPaper)
        XCTAssertEqual(DocumentFormat(typeName: "com.wiredpaper.paper"), .paper)
        XCTAssertEqual(DocumentFormat(typeName: "org.openxmlformats.wordprocessingml.document"), .docx)
        XCTAssertNil(DocumentFormat(typeName: "public.jpeg"))
    }

    func testMetadataDecodingIsTolerant() throws {
        let json = #"{"formatVersion": 1, "unknownFutureKey": true}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(DocumentMetadata.self, from: json)
        XCTAssertEqual(metadata.formatVersion, 1)
        XCTAssertTrue(metadata.styleRuns.isEmpty)
    }

    @MainActor
    func testPDFExportMatchesPagination() throws {
        let document = WiredPaperDocument()
        document.textStorage.setAttributedString(NSAttributedString(
            string: "Page one\u{0C}Page two",
            attributes: StyleCatalog.attributes(for: .normal)
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PDFExporter.export(document, to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
        let box = try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, document.pageSetup.paperSize.width, accuracy: 1)
    }

    func testDocumentReadWriteThroughNSDocument() throws {
        let document = WiredPaperDocument()
        document.textStorage.setAttributedString(sampleText())
        let wrapper = try document.fileWrapper(ofType: DocumentFormat.wiredPaper.typeIdentifier)

        let reopened = WiredPaperDocument()
        try reopened.read(from: wrapper, ofType: DocumentFormat.wiredPaper.typeIdentifier)
        XCTAssertEqual(reopened.textStorage.string, sampleText().string)
        XCTAssertEqual(reopened.pageSetup, document.pageSetup)
    }
}
