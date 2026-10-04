import AppKit
import XCTest
@testable import WiredPaper

/// Renders document windows off screen (never shown, never focused) so the UI
/// can be checked visually without touching the user's desktop.
/// Set TEST_RUNNER_WP_SNAPSHOT_DIR to choose where PNGs are written.
@MainActor
final class SnapshotTests: XCTestCase {
    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["WP_SNAPSHOT_DIR"] ?? NSTemporaryDirectory() + "WiredPaperSnapshots"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEditor(template: DocumentTemplate) -> (WiredPaperDocument, DocumentWindowController) {
        let document = WiredPaperDocument()
        document.load(template: template)
        let controller = DocumentWindowController(document: document)
        document.addWindowController(controller)
        // Far off screen and never ordered in: nothing appears on the desktop.
        controller.window?.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        settle(1.2)
        return (document, controller)
    }

    private func settle(_ seconds: TimeInterval = 0.6) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Column views: [left pane, editor, right pane].
    private func columns(_ controller: DocumentWindowController) -> [NSView] {
        (controller.contentController.view.subviews.first as? NSStackView)?.arrangedSubviews ?? []
    }

    private func render(_ controller: DocumentWindowController, name: String, part: Int? = nil) {
        guard var view = controller.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        if let part, columns(controller).indices.contains(part) { view = columns(controller)[part] }
        settle(0.3)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outputDirectory.appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("SNAPSHOT \(url.path)")
    }

    private func close(_ document: WiredPaperDocument, _ controller: DocumentWindowController) {
        controller.window?.orderOut(nil)
        controller.editor.tearDown()
        document.removeWindowController(controller)
    }

    func testReviewSnapshot() {
        let (document, controller) = makeEditor(template: TemplateLibrary.notes)
        let editor = controller.editor
        let storage = editor.textStorage

        // Track a replacement and a deletion.
        editor.setTracking(true)
        let discussion = (storage.string as NSString).range(of: "Capture decisions")
        editor.textView.setSelectedRange(NSRange(location: discussion.location, length: 7))
        editor.textView.insertText("Record", replacementRange: editor.textView.selectedRange())
        let reasoning = (storage.string as NSString).range(of: " and the reasoning behind them")
        editor.textView.setSelectedRange(reasoning)
        editor.textView.deleteBackward(nil)

        // Comment on the title.
        let title = (storage.string as NSString).range(of: "Meeting Notes")
        editor.textView.setSelectedRange(title)
        if let id = editor.addComment() {
            editor.setCommentText(id, text: "Add the project name here, @Maria")
            editor.replyToComment(id, text: "Will do.")
            editor.toggleReaction("👍", on: id)
        }
        editor.sidebar.editingCommentID = nil
        editor.sidebar.left = nil
        editor.sidebar.right = nil
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        settle(1)
        render(controller, name: "review-editor")
        editor.sidebar.left = .navigation
        editor.sidebar.right = .comments
        settle(1)
        render(controller, name: "review-comments", part: 2)
        render(controller, name: "review-navigation", part: 0)
        editor.sidebar.right = .review
        settle(0.6)
        render(controller, name: "review-changes", part: 2)

        XCTAssertEqual(editor.revisionEntries().count, 3, "insertion, replaced text and deletion")
        XCTAssertEqual(editor.commentThreads().count, 1)
        close(document, controller)
    }

    func testReferencesSnapshot() {
        let (document, controller) = makeEditor(template: TemplateLibrary.report)
        let editor = controller.editor
        var source = CitationSource()
        source.type = .book
        source.authors = ["Knuth, Donald E."]
        source.title = "The TeXbook"
        source.publisher = "Addison-Wesley"
        source.year = "1984"
        editor.saveSource(source)
        let summary = (editor.textStorage.string as NSString).range(of: "make it count.")
        editor.textView.setSelectedRange(NSRange(location: NSMaxRange(summary) - 1, length: 0))
        editor.insertCitation(sourceIDs: [source.id])
        editor.insertNote(isEndnote: false)
        if let note = document.metadata.footnotes.first { editor.setNoteText(note.id, text: "A footnote at the bottom of the page.") }
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertTableOfContents()
        editor.textView.setSelectedRange(NSRange(location: editor.textStorage.length, length: 0))
        editor.insertBibliography()
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollToTop()
        settle(1.2)
        render(controller, name: "references-editor")
        editor.sidebar.right = .references
        settle(1)
        render(controller, name: "references-pane", part: 2)
        XCTAssertNotNil(GeneratedContent.range(of: "toc", in: editor.textStorage))
        XCTAssertTrue(editor.textStorage.string.contains("(Knuth, 1984)"))
        close(document, controller)
    }

    /// Renders every object type into one gallery image.
    func testObjectGallerySnapshot() {
        var objects: [DocumentObject] = []
        for type in ChartType.allCases {
            var object = DocumentObject(kind: .chart)
            var spec = ChartSpec()
            spec.type = type
            spec.width = 300
            spec.height = 200
            if type == .pie { spec.series = [ChartSeries(name: "Share", values: [42, 28, 18, 12])] }
            object.chart = spec
            objects.append(object)
        }
        for latex in ["x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", "\\sum_{k=1}^{n} k^2 = \\frac{n(n+1)(2n+1)}{6}",
                      "\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}", "A = \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}",
                      "|x| = \\begin{cases} x & x \\geq 0 \\\\ -x & x < 0 \\end{cases}", "\\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}"] {
            var object = DocumentObject(kind: .equation)
            var spec = EquationSpec()
            spec.latex = latex
            spec.fontSize = 20
            object.equation = spec
            objects.append(object)
        }
        for kind in ShapeKind.allCases {
            var object = DocumentObject(kind: kind == .wordArt ? .wordArt : .shape)
            var spec = ShapeSpec()
            spec.kind = kind
            spec.width = kind == .wordArt ? 280 : 120
            spec.height = kind == .wordArt ? 70 : 80
            spec.text = kind == .wordArt ? "Wired Paper" : (kind == .textBox || kind == .callout ? "Hello there" : "")
            spec.fontSize = kind == .wordArt ? 40 : 14
            spec.shadow = kind == .star
            spec.rotation = kind == .hexagon ? 15 : 0
            object.shape = spec
            objects.append(object)
        }
        for type in DiagramType.allCases {
            var object = DocumentObject(kind: .diagram)
            var spec = DiagramSpec()
            spec.type = type
            spec.width = 340
            spec.height = type == .flowchart ? 300 : 200
            switch type {
            case .hierarchy: spec.outline = "CEO\n\tDesign\n\t\tResearch\n\tEngineering\n\t\tPlatform\n\t\tApps"
            case .list: spec.outline = "Goals\n\tGrow\n\tDelight\nPlan\n\tShip"
            case .flowchart: spec.outline = "Start\nCollect input\nValid?\nProcess\nEnd"
            default: break
            }
            object.diagram = spec
            objects.append(object)
        }
        var sheet = DocumentObject(kind: .spreadsheet)
        sheet.sheet = SpreadsheetSpec()
        objects.append(sheet)
        var signature = DocumentObject(kind: .signature)
        var signatureSpec = SignatureSpec()
        signatureSpec.signer = "Alex Example"
        signatureSpec.title = "Director"
        signatureSpec.signedName = "Alex Example"
        signatureSpec.signedDate = Date(timeIntervalSince1970: 1_790_000_000)
        signature.signature = signatureSpec
        objects.append(signature)
        var drawing = DocumentObject(kind: .drawing)
        var drawingSpec = DrawingSpec()
        drawingSpec.strokes = [DrawingStroke(points: (0..<40).map { CGPoint(x: 20 + Double($0) * 9, y: 110 + sin(Double($0) / 4) * 60) })]
        drawing.drawing = drawingSpec
        objects.append(drawing)

        let images = objects.compactMap(ObjectRenderer.image(for:))
        XCTAssertEqual(images.count, objects.count)
        // Lay out in rows of four.
        let cell = CGSize(width: 360, height: 320)
        let columns = 4
        let rows = (images.count + columns - 1) / columns
        let size = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
        let gallery = ImageProcessing.render(size: size, scale: 1) {
            NSColor(white: 0.93, alpha: 1).setFill()
            CGRect(origin: .zero, size: size).fill()
            for (index, image) in images.enumerated() {
                let column = index % columns, row = index / columns
                let fit = min(1, (cell.width - 20) / image.size.width, (cell.height - 20) / image.size.height)
                let drawn = CGSize(width: image.size.width * fit, height: image.size.height * fit)
                let origin = CGPoint(x: CGFloat(column) * cell.width + (cell.width - drawn.width) / 2,
                                     y: size.height - CGFloat(row + 1) * cell.height + (cell.height - drawn.height) / 2)
                image.draw(in: CGRect(origin: origin, size: drawn))
            }
        }
        let url = outputDirectory.appendingPathComponent("objects-gallery.png")
        try? ObjectFactory.pngData(gallery).write(to: url)
        print("SNAPSHOT \(url.path)")
    }

    /// Inserts objects and edits a table inside a real editor.
    func testObjectsInEditorSnapshot() {
        let (document, controller) = makeEditor(template: TemplateLibrary.report)
        let editor = controller.editor
        let storage = editor.textStorage
        // Table operations on the template's table.
        var tableLocation: Int?
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let style = value as? NSParagraphStyle, style.textBlocks.contains(where: { $0 is NSTextTableBlock }) {
                tableLocation = range.location
                stop.pointee = true
            }
        }
        if let tableLocation {
            editor.textView.setSelectedRange(NSRange(location: tableLocation, length: 0))
            XCTAssertTrue(editor.isInTable)
            let before = TableModel.read(at: tableLocation, in: storage)!.0
            editor.insertTableRow(below: true)
            editor.insertTableColumn(right: true)
            let after = TableModel.read(at: editor.textView.selectedRange().location, in: storage)!.0
            XCTAssertEqual(after.rowCount, before.rowCount + 1)
            XCTAssertEqual(after.columnCount, before.columnCount + 1)
            editor.applyTableStyle(.bandedRows)
        }
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        var chart = DocumentObject(kind: .chart)
        chart.chart = ChartSpec()
        editor.insertObject(chart, actionName: "Insert Chart")
        var equation = DocumentObject(kind: .equation)
        equation.equation = EquationSpec()
        editor.insertObject(equation, actionName: "Insert Equation")
        editor.insertFormControl(.checkbox)
        XCTAssertNotNil(storage.attribute(.wpObject, at: 0, effectiveRange: nil))

        // Round-trip through the native format keeps objects.
        let data = try? document.fileWrapper(ofType: DocumentFormat.wiredPaper.typeIdentifier)
        XCTAssertNotNil(data)
        editor.scrollToTop()
        settle(1.2)
        render(controller, name: "objects-editor", part: 1)
        close(document, controller)
    }

    /// The window content must follow any window size (e.g. full screen), never
    /// collapse to its minimum width.
    func testContentFollowsWindowSize() {
        let (document, controller) = makeEditor(template: TemplateLibrary.blank)
        guard let window = controller.window, let content = window.contentView else { return XCTFail("no window") }
        for width: CGFloat in [1900, 1000, 1500] {
            window.setFrame(NSRect(x: -30000, y: -30000, width: width, height: 1100), display: false)
            window.layoutIfNeeded()
            XCTAssertEqual(window.frame.width, width, accuracy: 1)
            XCTAssertEqual(content.frame.width, width, accuracy: 1)
            XCTAssertEqual(columns(controller)[1].frame.width, width, accuracy: 1)
        }
        // Showing a sidebar narrows the editor column but keeps the window size.
        controller.editor.sidebar.right = .comments
        settle(0.5)
        window.layoutIfNeeded()
        XCTAssertEqual(window.frame.width, 1500, accuracy: 1)
        XCTAssertEqual(columns(controller)[1].frame.width, 1500 - 320, accuracy: 1)
        controller.editor.sidebar.right = nil
        window.setFrame(NSRect(x: -30000, y: -30000, width: 1600, height: 1000), display: false)
        settle(0.8)
        render(controller, name: "wide-window")
        close(document, controller)
    }
}
