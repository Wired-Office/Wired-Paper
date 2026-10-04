import AppKit
import XCTest
@testable import WiredPaper

/// Ribbon commands, mail merge, proofing and accessibility. Windows are
/// created off screen and never shown.
@MainActor
final class RibbonTests: XCTestCase {
    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["WP_SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "WiredPaperSnapshots"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEditor(_ template: DocumentTemplate = TemplateLibrary.blank) -> (WiredPaperDocument, DocumentWindowController) {
        let document = WiredPaperDocument()
        document.load(template: template)
        let controller = DocumentWindowController(document: document)
        document.addWindowController(controller)
        controller.window?.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        settle(1.2)
        return (document, controller)
    }

    private func settle(_ seconds: TimeInterval = 0.4) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func close(_ document: WiredPaperDocument, _ controller: DocumentWindowController) {
        controller.window?.orderOut(nil)
        controller.editor.tearDown()
        document.removeWindowController(controller)
    }

    private func setText(_ editor: EditorController, _ text: String) {
        editor.textView.selectAll(nil)
        editor.textView.insertText(text, replacementRange: editor.textView.selectedRange())
    }

    // MARK: Menus used by the ribbon

    func testEveryRibbonMenuPathExists() {
        let paths: [[String]] = [
            ["Format", "Font", "Change Case"], ["Format", "Font", "Text Effects"], ["Format", "Font", "Character Spacing"],
            ["Format", "Font", "Kerning"], ["Format", "Font", "Ligatures"], ["Format", "Font", "Baseline"],
            ["Format", "Lists", "Bullet Style"], ["Format", "Lists", "Numbering Style"], ["Format", "Picture"],
            ["Insert", "Shape"], ["Insert", "Diagram"], ["Insert", "Chart"], ["Insert", "Field"], ["Insert", "Form Control"],
            ["Layout", "Page Numbers"], ["Layout", "Page Color"], ["Layout", "Margins"], ["Layout", "Orientation"],
            ["Layout", "Size"], ["Layout", "Columns"], ["Layout", "Breaks"], ["Layout", "Line Numbers"], ["Layout", "Vertical Alignment"],
            ["References", "Citation Style"], ["References", "Table of Figures"], ["Review", "Markup"],
        ]
        for path in paths {
            let menu = RibbonCommand.mainMenu(path)
            XCTAssertFalse(menu.items.isEmpty, "\(path) is empty")
            XCTAssertNotEqual(menu.items.first?.title, "Unavailable", "\(path) not found in the main menu")
        }
    }

    // MARK: Paragraph commands

    func testSortParagraphs() {
        let (document, controller) = makeEditor()
        let editor = controller.editor
        setText(editor, "Pear\napple\nBanana\n10 items\n9 items")
        editor.textView.selectAll(nil)
        XCTAssertTrue(editor.sortParagraphs(ascending: true))
        XCTAssertEqual(editor.textStorage.string, "9 items\n10 items\napple\nBanana\nPear")
        editor.textView.selectAll(nil)
        XCTAssertTrue(editor.sortParagraphs(ascending: false))
        XCTAssertEqual(editor.textStorage.string, "Pear\nBanana\napple\n10 items\n9 items")
        close(document, controller)
    }

    func testBordersShadingUnderlineAndMarks() {
        let (document, controller) = makeEditor()
        let editor = controller.editor
        setText(editor, "Boxed paragraph")
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.applyBorderPreset(.bottom)
        XCTAssertTrue(editor.currentBorders.bottom)
        XCTAssertFalse(editor.currentBorders.top)
        editor.applyBorderPreset(.all)
        XCTAssertTrue(editor.currentBorders.top && editor.currentBorders.left && editor.currentBorders.right)
        editor.setParagraphShading(ColorPalettes.hex(0xD9D9D9))
        XCTAssertNotNil(editor.currentBorders.shading)
        editor.applyBorderPreset(.none)
        XCTAssertFalse(editor.currentBorders.hasBorder)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 5))
        editor.setUnderline(.double)
        let underline = editor.textStorage.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int
        XCTAssertEqual(underline, NSUnderlineStyle.double.rawValue)
        editor.setUnderline(nil)
        XCTAssertNil(editor.textStorage.attribute(.underlineStyle, at: 1, effectiveRange: nil))

        XCTAssertFalse(editor.showsFormattingMarks)
        editor.toggleFormattingMarks()
        XCTAssertTrue(editor.showsFormattingMarks)
        close(document, controller)
    }

    func testSpacingPresetAndSensitivityPersist() throws {
        let (document, controller) = makeEditor()
        let editor = controller.editor
        editor.applySpacingPreset(.relaxed)
        XCTAssertEqual(document.styleSheet.definition("normal")?.spaceAfter, 12)
        XCTAssertEqual(document.styleSheet.definition("normal")?.lineHeight, 1.5)
        editor.setSensitivity(.confidential)
        XCTAssertEqual(editor.sensitivity, .confidential)

        let wrapper = try document.fileWrapper(ofType: DocumentFormat.wiredPaper.typeIdentifier)
        let reopened = WiredPaperDocument()
        try reopened.read(from: wrapper, ofType: DocumentFormat.wiredPaper.typeIdentifier)
        XCTAssertEqual(reopened.metadata.properties.sensitivity, SensitivityLabel.confidential.rawValue)
        XCTAssertEqual(reopened.styleSheet.definition("normal")?.spaceAfter, 12)
        close(document, controller)
    }

    func testViewingModeBlocksEdits() {
        let (document, controller) = makeEditor()
        let editor = controller.editor
        setText(editor, "Read me")
        controller.contentController.setDocumentMode(.viewing)
        XCTAssertEqual(controller.contentController.documentMode, .viewing)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.insertText("X", replacementRange: editor.textView.selectedRange())
        XCTAssertEqual(editor.textStorage.string, "Read me")

        controller.contentController.setDocumentMode(.reviewing)
        XCTAssertTrue(editor.isTrackingChanges)
        controller.contentController.setDocumentMode(.editing)
        XCTAssertFalse(editor.isTrackingChanges)
        editor.textView.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.textStorage.string, "XRead me")
        close(document, controller)
    }

    // MARK: Mail merge

    func testRecipientListParsing() throws {
        let csv = "First Name,Last Name,City\r\n\"Ada\",\"Lovelace, Countess\",London\r\nLinus,\"Torvalds \"\"Linux\"\"\",Portland\r\n"
        let data = try XCTUnwrap(MailMergeData.parse(csv, sourceName: "people.csv"))
        XCTAssertEqual(data.headers, ["First Name", "Last Name", "City"])
        XCTAssertEqual(data.records.count, 2)
        XCTAssertEqual(data.records[0], ["Ada", "Lovelace, Countess", "London"])
        XCTAssertEqual(data.records[1][1], "Torvalds \"Linux\"")
        XCTAssertEqual(data.addressFields.first, ["First Name", "Last Name"])

        let tsv = "Name\tEmail\nGrace\tgrace@example.com\n"
        let tabbed = try XCTUnwrap(MailMergeData.parse(tsv, sourceName: "t.tsv"))
        XCTAssertEqual(tabbed.headers, ["Name", "Email"])
        XCTAssertEqual(tabbed.record(0)["Email"], "grace@example.com")

        let semicolons = try XCTUnwrap(MailMergeData.parse("Vorname;Stadt\nMax;Berlin", sourceName: "de.csv"))
        XCTAssertEqual(semicolons.records, [["Max", "Berlin"]])
    }

    func testMergeProducesOneLetterPerRecipient() throws {
        let (document, controller) = makeEditor()
        let editor = controller.editor
        setText(editor, "Dear ")
        editor.textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.insertMergeField("Name")
        editor.textView.insertText(", welcome.", replacementRange: editor.textView.selectedRange())

        var data = try XCTUnwrap(MailMergeData.parse("Name\nAda\nLinus\nGrace", sourceName: "x.csv"))
        data.excluded = [2]
        editor.setMailMerge(data)

        editor.previewMergeRecord(1)
        XCTAssertEqual(editor.mergePreviewIndex, 1)
        XCTAssertEqual(editor.layoutManager.mergePreview?["Name"], "Linus")
        editor.previewMergeRecord(nil)
        XCTAssertNil(editor.layoutManager.mergePreview)

        let merged = try XCTUnwrap(editor.mergedDocumentText()).string
        XCTAssertTrue(merged.contains("Dear Ada, welcome."))
        XCTAssertTrue(merged.contains("Dear Linus, welcome."))
        XCTAssertFalse(merged.contains("Grace"))
        XCTAssertEqual(merged.filter { $0 == "\u{0C}" }.count, 1)
        close(document, controller)
    }

    func testLabelsAndEnvelopeBuilders() {
        let base = StyleCatalog.attributes(for: .normal)
        let texts = (1...35).map { NSAttributedString(string: "Person \($0)\nStreet \($0)", attributes: base) }
        let (labels, setup) = MailingsBuilder.labels(texts: texts, layout: .avery5160)
        XCTAssertEqual(setup.paperSize, PaperPreset.letter.size)
        XCTAssertEqual(labels.string.filter { $0 == "\u{0C}" }.count, 1, "35 labels need two pages of 30")
        XCTAssertTrue(labels.string.contains("Person 35"))

        let (envelope, envelopeSetup) = MailingsBuilder.envelope(delivery: "Ada Lovelace\n12 St James's Square", returnAddress: "Wired Paper", size: .dl)
        XCTAssertGreaterThan(envelopeSetup.paperSize.width, envelopeSetup.paperSize.height)
        XCTAssertTrue(envelope.string.contains("Ada Lovelace"))
    }

    // MARK: Proofing & accessibility

    func testReadabilityAndAccessibilityChecks() {
        let stats = ReadabilityStats.measure("The cat sat. The dog ran fast.")
        XCTAssertEqual(stats.words, 7)
        XCTAssertEqual(stats.sentences, 2)
        XCTAssertGreaterThan(stats.readingEase, 80)

        let (document, controller) = makeEditor()
        let editor = controller.editor
        setText(editor, "Intro\nDeep heading\nFaint text")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.applyStyle(id: "heading1")
        editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        editor.applyStyle(id: "heading3")
        let faint = (editor.textStorage.string as NSString).range(of: "Faint text")
        editor.textStorage.addAttribute(.foregroundColor, value: NSColor(white: 0.85, alpha: 1), range: faint)
        var chart = DocumentObject(kind: .chart)
        chart.chart = ChartSpec()
        editor.textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.insertObject(chart, actionName: "Chart")

        let issues = editor.checkAccessibility()
        XCTAssertTrue(issues.contains { $0.title == "Skipped heading level" })
        XCTAssertTrue(issues.contains { $0.title == "Hard-to-read text contrast" })
        XCTAssertTrue(issues.contains { $0.title == "Missing alternative text" })
        XCTAssertTrue(issues.contains { $0.title == "No document title" })

        editor.textView.setSelectedRange(NSRange(location: editor.textStorage.length - 1, length: 1))
        editor.setSelectedImageAltText("Quarterly sales chart")
        XCTAssertFalse(editor.checkAccessibility().contains { $0.title == "Missing alternative text" })
        close(document, controller)
    }

    // MARK: Snapshots

    func testRibbonTabsSnapshot() {
        let (document, controller) = makeEditor(TemplateLibrary.report)
        guard let window = controller.window else { return XCTFail("no window") }
        window.setFrame(NSRect(x: -30000, y: -30000, width: 1500, height: 900), display: false)
        let content = controller.contentController
        for tab in RibbonModel.Tab.allCases {
            content.ribbon.tab = tab
            settle(0.5)
            window.contentView?.layoutSubtreeIfNeeded()
            guard let bar = content.formatBar, let rep = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) else { continue }
            XCTAssertEqual(bar.frame.height, RibbonModel.expandedHeight, accuracy: 1)
            bar.cacheDisplay(in: bar.bounds, to: rep)
            let url = outputDirectory.appendingPathComponent("ribbon-\(tab.rawValue).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
        content.ribbon.tab = .home
        content.ribbon.isCollapsed = true
        settle(0.4)
        XCTAssertEqual(content.formatBar.frame.height, RibbonModel.collapsedHeight, accuracy: 1)
        content.ribbon.isCollapsed = false
        settle(0.3)

        // Whole window including the title bar.
        if let frameView = window.contentView?.superview, let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            let url = outputDirectory.appendingPathComponent("ribbon-window.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("SNAPSHOT \(url.path)")
        }
        close(document, controller)
    }
}
