import AppKit

/// Adds Wired Paper's options to the system print panel.
final class PrintOptionsController: NSViewController, NSPrintPanelAccessorizing {
    private weak var document: WiredPaperDocument?
    private let markup = NSButton(checkboxWithTitle: "Print tracked changes", target: nil, action: nil)
    private let comments = NSButton(checkboxWithTitle: "Print comments", target: nil, action: nil)
    private let backgrounds = NSButton(checkboxWithTitle: "Print background colors and images", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "Print hidden text", target: nil, action: nil)

    init(document: WiredPaperDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        title = "Wired Paper"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let options = document?.printOptions ?? PrintOptions()
        markup.state = options.includeMarkup ? .on : .off
        comments.state = options.includeComments ? .on : .off
        backgrounds.state = options.includeBackgrounds ? .on : .off
        hidden.state = options.includeHiddenText ? .on : .off
        for button in [markup, comments, backgrounds, hidden] {
            button.target = self
            button.action = #selector(changed(_:))
        }
        let stack = NSStackView(views: [markup, comments, backgrounds, hidden])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        view = stack
    }

    @objc private func changed(_ sender: NSButton) {
        guard let document else { return }
        document.printOptions = PrintOptions(
            includeMarkup: markup.state == .on,
            includeComments: comments.state == .on,
            includeBackgrounds: backgrounds.state == .on,
            includeHiddenText: hidden.state == .on
        )
        // Re-paginate the view being printed so the preview reflects the options.
        if let view = NSPrintOperation.current?.view as? PrintPagesView {
            view.reconfigure(document.printConfiguration())
        }
        willChangeValue(forKey: "previewToken")
        previewToken += 1
        didChangeValue(forKey: "previewToken")
    }

    /// Changing this tells the print panel to refresh its preview.
    @objc dynamic var previewToken = 0

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        let options = document?.printOptions ?? PrintOptions()
        return [
            [.itemName: "Tracked changes", .itemDescription: options.includeMarkup ? "On" : "Off"],
            [.itemName: "Comments", .itemDescription: options.includeComments ? "On" : "Off"],
        ]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> { ["previewToken"] }
}
