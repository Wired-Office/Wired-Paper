import AppKit
import XCTest
@testable import WiredPaper

final class EditingTests: XCTestCase {
    /// A standalone text view with its own storage, like one page of the editor.
    private func makeTextView(_ string: String) -> NSTextView {
        let storage = NSTextStorage(string: string, attributes: StyleCatalog.attributes(for: .normal))
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 468, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 600), textContainer: container)
        textView.isRichText = true
        textView.allowsUndo = true
        return textView
    }

    // MARK: Lists

    func testToggleBulletsOnAndOff() {
        let textView = makeTextView("One\nTwo\nThree")
        textView.selectAll(nil)
        ListFormatter.toggle(.bullet, in: textView)

        XCTAssertEqual(textView.string, "\t•\tOne\n\t•\tTwo\n\t•\tThree")
        let style = textView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.textLists.count, 1)
        XCTAssertEqual(ListKind(markerFormat: style.textLists[0].markerFormat), .bullet)

        textView.selectAll(nil)
        ListFormatter.toggle(.bullet, in: textView)
        XCTAssertEqual(textView.string, "One\nTwo\nThree")
        let plain = textView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        XCTAssertTrue(plain.textLists.isEmpty)
    }

    func testNumberedListNumbersItemsAndSwitchesKind() {
        let textView = makeTextView("Alpha\nBeta")
        textView.selectAll(nil)
        ListFormatter.toggle(.numbered, in: textView)
        XCTAssertEqual(textView.string, "\t1.\tAlpha\n\t2.\tBeta")

        textView.selectAll(nil)
        ListFormatter.toggle(.bullet, in: textView)
        XCTAssertEqual(textView.string, "\t•\tAlpha\n\t•\tBeta")
    }

    func testListOnCaretKeepsCaretInText() {
        let textView = makeTextView("Hello")
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        ListFormatter.toggle(.bullet, in: textView)
        XCTAssertEqual(textView.selectedRange().location, 5)
    }

    func testNumberedListContinuesPreviousList() {
        let textView = makeTextView("First\nSecond")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        ListFormatter.toggle(.numbered, in: textView)
        let secondStart = (textView.string as NSString).range(of: "Second").location
        textView.setSelectedRange(NSRange(location: secondStart, length: 0))
        ListFormatter.toggle(.numbered, in: textView)
        XCTAssertEqual(textView.string, "\t1.\tFirst\n\t2.\tSecond")
    }

    // MARK: Tables

    func testMakeTableCreatesOneParagraphPerCell() {
        let table = TableBuilder.makeTable(rows: 2, columns: 3, baseAttributes: StyleCatalog.attributes(for: .normal))
        XCTAssertEqual(table.string, String(repeating: "\n", count: 6))
        for index in 0..<6 {
            let style = table.attribute(.paragraphStyle, at: index, effectiveRange: nil) as! NSParagraphStyle
            let block = style.textBlocks.last as? NSTextTableBlock
            XCTAssertNotNil(block)
            XCTAssertEqual(block?.table.numberOfColumns, 3)
            XCTAssertEqual(block?.startingRow, index / 3)
            XCTAssertEqual(block?.startingColumn, index % 3)
        }
    }

    func testInsertTableAndAppendRow() {
        let textView = makeTextView("Intro")
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        TableBuilder.insertTable(rows: 2, columns: 2, into: textView)
        let storage = textView.textStorage!
        // "Intro" + newline, 4 cells, and a normal paragraph after the table.
        XCTAssertEqual(storage.string, "Intro\n\n\n\n\n\n")
        XCTAssertNotNil(TableBuilder.tableBlock(at: textView.selectedRange().location, in: storage))

        TableBuilder.appendRow(toTableAt: textView.selectedRange().location, in: textView)
        var rows = Set<Int>()
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let block = (value as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock { rows.insert(block.startingRow) }
        }
        XCTAssertEqual(rows, [0, 1, 2])
        XCTAssertNil(TableBuilder.tableBlock(at: storage.length - 1, in: storage), "Text after the table stays outside it")
    }

    // MARK: Formatting

    func testBoldToggleAppliesToSelection() {
        let textView = makeTextView("Make this bold")
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        let manager = NSFontManager.shared
        TextFormatter.changeFonts(in: textView, actionName: "Bold") { manager.convert($0, toHaveTrait: .boldFontMask) }
        let font = textView.textStorage!.attribute(.font, at: 6, effectiveRange: nil) as! NSFont
        XCTAssertTrue(manager.traits(of: font).contains(.boldFontMask))
        let untouched = textView.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertFalse(manager.traits(of: untouched).contains(.boldFontMask))
    }

    func testApplyHeadingStyleTagsParagraph() {
        let textView = makeTextView("Heading\nBody")
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        TextFormatter.applyStyle(.heading1, in: textView)
        let storage = textView.textStorage!
        XCTAssertEqual(storage.attribute(.wpParagraphStyle, at: 0, effectiveRange: nil) as? String, "heading1")
        XCTAssertEqual(storage.attribute(.wpParagraphStyle, at: 9, effectiveRange: nil) as? String, "normal")
    }

    func testParagraphSettingsRoundTrip() {
        var settings = ParagraphSettings()
        settings.leftIndent = 36
        settings.firstLineOffset = -18
        settings.rightIndent = 12
        settings.spacingAfter = 6
        settings.lineHeightMultiple = 1.5
        let style = NSMutableParagraphStyle()
        settings.apply(to: style)
        XCTAssertEqual(ParagraphSettings(style), settings)
    }

    // MARK: Pagination & statistics

    func testPrintPaginationAndPageBreaks() {
        let setup = PageSetup.standard(.letter)
        let short = PrintPagesView(text: NSAttributedString(string: "Hello", attributes: StyleCatalog.attributes(for: .normal)), pageSetup: setup)
        XCTAssertEqual(short.pageCount, 1)

        let broken = PrintPagesView(text: NSAttributedString(string: "One\u{0C}Two\u{0C}Three", attributes: StyleCatalog.attributes(for: .normal)), pageSetup: setup)
        XCTAssertEqual(broken.pageCount, 3)

        let long = String(repeating: "A line of body text that fills the page.\n", count: 200)
        let paged = PrintPagesView(text: NSAttributedString(string: long, attributes: StyleCatalog.attributes(for: .normal)), pageSetup: setup)
        XCTAssertGreaterThan(paged.pageCount, 3)
    }

    func testStatistics() {
        let stats = DocumentStatistics.compute("Hello world. This is Wired Paper.\n\n\t1.\tSecond paragraph")
        XCTAssertEqual(stats.words, 8)
        XCTAssertEqual(stats.paragraphs, 2)
        XCTAssertEqual(DocumentStatistics.compute("").words, 0)
    }

    func testTemplatesProduceContent() {
        for template in TemplateLibrary.all where template.id != "blank" {
            XCTAssertGreaterThan(template.makeContent(.standard(.letter)).length, 50, template.name)
        }
    }

    func testOversizedImagesAreFittedToThePage() {
        let image = NSImage(size: NSSize(width: 2000, height: 3000), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let wrapper = FileWrapper(regularFileWithContents: rep.representation(using: .png, properties: [:])!)
        wrapper.preferredFilename = "big.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let maxSize = PageSetup.standard(.letter).maxAttachmentSize
        AttachmentNormalizer.normalize(attachment, maxSize: maxSize)
        let size = attachment.attachmentCell!.cellSize()
        XCTAssertLessThanOrEqual(size.width, maxSize.width + 0.5)
        XCTAssertLessThanOrEqual(size.height, maxSize.height + 0.5)
    }
}
