import AppKit
import UniformTypeIdentifiers

/// File ▸ Export…: writes a copy of the document in another format without
/// changing the document's own file or type.
@MainActor
final class ExportController: NSObject {
    private static var active: ExportController?

    private let document: WiredPaperDocument
    private let panel = NSSavePanel()
    private let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formats = DocumentFormat.exportFormats

    private init(document: WiredPaperDocument) {
        self.document = document
        super.init()
    }

    static func beginExport(for document: WiredPaperDocument, in window: NSWindow) {
        let controller = ExportController(document: document)
        active = controller
        controller.run(in: window)
    }

    private func run(in window: NSWindow) {
        for format in formats {
            formatPopUp.addItem(withTitle: format.displayName)
        }
        let lastUsed = UserDefaults.standard.string(forKey: "WPLastExportFormat").flatMap(DocumentFormat.init(rawValue:)) ?? .pdf
        formatPopUp.selectItem(at: formats.firstIndex(of: lastUsed) ?? 0)
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged(_:))

        let label = NSTextField(labelWithString: "Format:")
        let accessory = NSStackView(views: [label, formatPopUp])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        panel.title = "Export"
        panel.prompt = "Export"
        panel.accessoryView = accessory
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (document.displayName as NSString).deletingPathExtension
        updateAllowedType()

        panel.beginSheetModal(for: window) { [self] response in
            defer { Self.active = nil }
            guard response == .OK, let url = panel.url else { return }
            let format = selectedFormat
            UserDefaults.standard.set(format.rawValue, forKey: "WPLastExportFormat")
            export(to: url, format: format, window: window)
        }
    }

    private var selectedFormat: DocumentFormat {
        formats[max(formatPopUp.indexOfSelectedItem, 0)]
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        updateAllowedType()
    }

    private func updateAllowedType() {
        let format = selectedFormat
        panel.allowedContentTypes = [format.utType]
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + format.fileExtension
    }

    private func export(to url: URL, format: DocumentFormat, window: NSWindow) {
        if format == .pdf {
            do {
                try PDFExporter.export(document, to: url)
            } catch {
                window.presentError(error)
            }
            return
        }
        document.save(to: url, ofType: format.typeIdentifier, for: .saveToOperation) { error in
            if let error { window.presentError(error) }
        }
    }
}

enum PDFExporter {
    /// Renders the document through the same print path used by File ▸ Print,
    /// so exported PDFs match printed output page for page.
    @MainActor
    static func export(_ document: WiredPaperDocument, to url: URL) throws {
        let operation = try document.printOperation(withSettings: [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: url,
        ])
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw WiredPaperError.writeFailed("The PDF could not be created.")
        }
    }
}
