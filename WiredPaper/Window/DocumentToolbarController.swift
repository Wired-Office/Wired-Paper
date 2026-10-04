import AppKit

/// The title bar, laid out like Word's: AutoSave, Home, Save, Undo, Redo,
/// Print and More on the left; the document title in the middle; Comments,
/// the Editing/Reviewing/Viewing mode, Share and Search on the right.
final class DocumentToolbarController: NSObject, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate, NSSearchFieldDelegate {
    private struct ItemSpec {
        let label: String
        let symbol: String
        let action: Selector
        var tag = 0
        var tooltip: String?
    }

    static let autoSave = NSToolbarItem.Identifier("wp.autosave")
    static let home = NSToolbarItem.Identifier("wp.home")
    static let new = NSToolbarItem.Identifier("wp.new")
    static let open = NSToolbarItem.Identifier("wp.open")
    static let save = NSToolbarItem.Identifier("wp.save")
    static let undo = NSToolbarItem.Identifier("wp.undo")
    static let redo = NSToolbarItem.Identifier("wp.redo")
    static let print = NSToolbarItem.Identifier("wp.print")
    static let more = NSToolbarItem.Identifier("wp.more")
    static let title = NSToolbarItem.Identifier("wp.title")
    static let comments = NSToolbarItem.Identifier("wp.comments")
    static let mode = NSToolbarItem.Identifier("wp.mode")
    static let share = NSToolbarItem.Identifier("wp.share")
    static let search = NSToolbarItem.Identifier("wp.search")
    static let image = NSToolbarItem.Identifier("wp.insertImage")
    static let table = NSToolbarItem.Identifier("wp.insertTable")
    static let link = NSToolbarItem.Identifier("wp.insertLink")
    static let find = NSToolbarItem.Identifier("wp.find")
    static let export = NSToolbarItem.Identifier("wp.export")

    /// The document window's content, for Share, Search and the mode menu.
    weak var contentController: DocumentViewController?
    private(set) var titleField: NSTextField?
    private(set) var subtitleField: NSTextField?
    private weak var autoSaveSwitch: NSSwitch?
    private weak var modeItem: NSMenuToolbarItem?
    private var settingsObserver: NSObjectProtocol?

    private let specs: [NSToolbarItem.Identifier: ItemSpec] = [
        home: ItemSpec(label: "Home", symbol: "house", action: #selector(AppDelegate.showTemplateChooser(_:)), tooltip: "New from template"),
        new: ItemSpec(label: "New", symbol: "doc.badge.plus", action: #selector(NSDocumentController.newDocument(_:)), tooltip: "New document (⌘N)"),
        open: ItemSpec(label: "Open", symbol: "folder", action: #selector(NSDocumentController.openDocument(_:)), tooltip: "Open a document (⌘O)"),
        save: ItemSpec(label: "Save", symbol: "square.and.arrow.down", action: #selector(NSDocument.save(_:)), tooltip: "Save (⌘S)"),
        undo: ItemSpec(label: "Undo", symbol: "arrow.uturn.backward", action: Selector(("undo:")), tooltip: "Undo (⌘Z)"),
        redo: ItemSpec(label: "Redo", symbol: "arrow.uturn.forward", action: Selector(("redo:")), tooltip: "Redo (⇧⌘Z)"),
        print: ItemSpec(label: "Print", symbol: "printer", action: #selector(NSDocument.printDocument(_:)), tooltip: "Print (⌘P)"),
        comments: ItemSpec(label: "Comments", symbol: "text.bubble", action: #selector(DocumentViewController.showCommentsPane(_:)), tooltip: "Comments"),
        image: ItemSpec(label: "Image", symbol: "photo", action: #selector(DocumentViewController.insertImageFromFile(_:)), tooltip: "Insert an image"),
        table: ItemSpec(label: "Table", symbol: "tablecells", action: #selector(DocumentViewController.showInsertTableSheet(_:)), tooltip: "Insert a table"),
        link: ItemSpec(label: "Link", symbol: "link", action: #selector(DocumentViewController.showLinkSheet(_:)), tooltip: "Insert a link (⌘K)"),
        find: ItemSpec(label: "Find", symbol: "magnifyingglass", action: #selector(NSResponder.performTextFinderAction(_:)), tag: NSTextFinder.Action.showFindInterface.rawValue, tooltip: "Find and replace (⌘F)"),
        export: ItemSpec(label: "Export", symbol: "square.and.arrow.up.on.square", action: #selector(DocumentViewController.exportDocument(_:)), tooltip: "Export as PDF, Word and more"),
    ]

    func makeToolbar() -> NSToolbar {
        // A new identifier so older saved (customized) layouts don't hide the new items.
        let toolbar = NSToolbar(identifier: "WiredPaperTitleBar2")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.centeredItemIdentifiers = [Self.title]
        settingsObserver = NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.autoSaveSwitch?.state = AppSettings.shared.autoSave ? .on : .off
        }
        return toolbar
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.autoSave, Self.home, Self.save, Self.undo, Self.redo, Self.print, Self.more,
         .flexibleSpace, Self.title, .flexibleSpace,
         Self.comments, Self.mode, Self.share, Self.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.autoSave, Self.home, Self.new, Self.open, Self.save, Self.undo, Self.redo, Self.print, Self.more, Self.title,
         Self.comments, Self.mode, Self.share, Self.search, Self.image, Self.table, Self.link, Self.find, Self.export,
         .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.autoSave: return makeAutoSaveItem()
        case Self.more: return makeMoreItem()
        case Self.title: return makeTitleItem()
        case Self.mode: return makeModeItem()
        case Self.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share this document"
            item.delegate = self
            return item
        case Self.search:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.label = "Search"
            item.paletteLabel = "Search"
            item.searchField.placeholderString = "Search document"
            item.searchField.delegate = self
            item.searchField.target = self
            item.searchField.action = #selector(searchSubmitted(_:))
            item.searchField.sendsWholeSearchString = true
            return item
        default:
            break
        }
        guard let spec = specs[identifier] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = spec.label
        item.paletteLabel = spec.label
        item.toolTip = spec.tooltip ?? spec.label
        item.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.label)
        item.action = spec.action
        item.target = nil
        item.tag = spec.tag
        item.isBordered = true
        item.autovalidates = true
        return item
    }

    // MARK: AutoSave

    private func makeAutoSaveItem() -> NSToolbarItem {
        let label = NSTextField(labelWithString: "AutoSave")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.state = AppSettings.shared.autoSave ? .on : .off
        toggle.target = self
        toggle.action = #selector(autoSaveChanged(_:))
        toggle.toolTip = "Save changes to the file automatically"
        autoSaveSwitch = toggle
        let stack = NSStackView(views: [label, toggle])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        let item = NSToolbarItem(itemIdentifier: Self.autoSave)
        item.view = stack
        item.label = "AutoSave"
        item.paletteLabel = "AutoSave"
        item.toolTip = "Save changes to the file automatically"
        return item
    }

    @objc private func autoSaveChanged(_ sender: NSSwitch) {
        AppSettings.shared.autoSave = sender.state == .on
        // Save now when turning AutoSave on, like Word.
        if sender.state == .on, let document = contentController?.document, document.fileURL != nil, document.isDocumentEdited {
            document.save(nil)
        }
    }

    // MARK: More

    private func makeMoreItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: Self.more)
        item.label = "More"
        item.paletteLabel = "More Commands"
        item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        item.showsIndicator = false
        item.toolTip = "More commands"
        let menu = NSMenu()
        menu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Duplicate", action: #selector(NSDocument.duplicate(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export…", action: #selector(DocumentViewController.exportDocument(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Export as PDF…", action: #selector(NSDocument.saveToPDF(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Properties…", action: #selector(DocumentViewController.showDocumentProperties(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Browse All Versions…", action: #selector(NSDocument.browseVersions(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Customize Title Bar…", action: #selector(NSWindow.runToolbarCustomizationPalette(_:)), keyEquivalent: "")
        item.menu = menu
        return item
    }

    // MARK: Title

    private func makeTitleItem() -> NSToolbarItem {
        let title = NSTextField(labelWithString: "Untitled")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .center
        title.lineBreakMode = .byTruncatingMiddle
        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        titleField = title
        subtitleField = subtitle
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .centerX
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let item = NSToolbarItem(itemIdentifier: Self.title)
        item.view = stack
        item.label = "Title"
        item.paletteLabel = "Document Title"
        item.visibilityPriority = .high
        return item
    }

    func updateTitle(_ title: String, subtitle: String) {
        titleField?.stringValue = title
        subtitleField?.stringValue = subtitle
        subtitleField?.isHidden = subtitle.isEmpty
    }

    // MARK: Editing mode

    private func makeModeItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: Self.mode)
        item.paletteLabel = "Editing Mode"
        item.label = "Mode"
        item.toolTip = "Editing, Reviewing (track changes) or Viewing"
        let menu = NSMenu()
        for mode in DocumentMode.allCases {
            let entry = NSMenuItem(title: mode.title, action: #selector(DocumentViewController.setDocumentModeFromMenu(_:)), keyEquivalent: "")
            entry.tag = mode.rawValue
            entry.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            entry.toolTip = mode.detail
            menu.addItem(entry)
        }
        item.menu = menu
        modeItem = item
        updateMode(.editing)
        return item
    }

    func updateMode(_ mode: DocumentMode) {
        modeItem?.title = mode.title
        modeItem?.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.title)
    }

    // MARK: Share

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let document = contentController?.document else { return [] }
        if let url = document.fileURL {
            if document.isDocumentEdited { document.save(nil) }
            return [url]
        }
        // Unsaved documents are shared as a PDF.
        let name = (document.displayName as NSString).deletingPathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        do {
            try PDFExporter.export(document, to: url)
            return [url]
        } catch {
            return [document.textStorage.string]
        }
    }

    // MARK: Search

    @objc private func searchSubmitted(_ sender: NSSearchField) {
        guard let editor = contentController?.editor else { return }
        let query = sender.stringValue
        guard !query.isEmpty else { return }
        editor.sidebar.left = .navigation
        editor.sidebar.navigationTab = .results
        editor.sidebar.searchQuery = query
    }
}

/// Title bar ▸ mode menu.
enum DocumentMode: Int, CaseIterable {
    case editing, reviewing, viewing

    var title: String {
        switch self {
        case .editing: "Editing"
        case .reviewing: "Reviewing"
        case .viewing: "Viewing"
        }
    }

    var symbol: String {
        switch self {
        case .editing: "pencil"
        case .reviewing: "pencil.line"
        case .viewing: "eye"
        }
    }

    var detail: String {
        switch self {
        case .editing: "Edit the document directly"
        case .reviewing: "All edits become tracked changes"
        case .viewing: "Read without making changes"
        }
    }
}
