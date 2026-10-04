import AppKit
import Combine

/// The document model. Owns the text storage, page setup and metadata
/// (styles, comments, revisions, notes, sources…), and delegates reading and
/// writing to format codecs. Autosave, versions, crash recovery, the edited
/// indicator and Open Recent all come from NSDocument.
final class WiredPaperDocument: NSDocument, ObservableObject {
    /// The single source of truth for document text. Editors attach their
    /// layout managers to it; codecs read and write snapshots of it.
    let textStorage = NSTextStorage()

    private(set) var pageSetup: PageSetup
    private(set) var metadata = DocumentMetadata()
    private var cachedStyleSheet: StyleSheet?

    /// Called whenever page geometry or document settings change.
    var onLayoutSettingsChange: (() -> Void)?

    override init() {
        pageSetup = AppSettings.shared.defaultPageSetup
        super.init()
        pageSetup.apply(to: printInfo)
        metadata.properties.author = AppSettings.shared.authorName
    }

    // MARK: - NSDocument configuration

    /// Title bar ▸ AutoSave. Off gives classic "Save changes?" behavior.
    override class var autosavesInPlace: Bool { AppSettings.shared.autoSave }
    override class var preservesVersions: Bool { AppSettings.shared.autoSave }
    override class var autosavesDrafts: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    var format: DocumentFormat? {
        fileType.flatMap(DocumentFormat.init(typeName:))
    }

    var editor: EditorController? {
        windowControllers.lazy.compactMap { ($0 as? DocumentWindowController)?.editor }.first
    }

    // MARK: - Derived state

    var styleSheet: StyleSheet {
        if let cachedStyleSheet { return cachedStyleSheet }
        let settings = AppSettings.shared
        let sheet = StyleSheet(
            theme: metadata.theme ?? .paper(bodyFont: settings.defaultFontFamily),
            overrides: metadata.styles,
            bodySize: CGFloat(settings.defaultFontSize)
        )
        cachedStyleSheet = sheet
        return sheet
    }

    var geometry: PageGeometry {
        PageGeometry(setup: pageSetup, decoration: metadata.decoration)
    }

    var fieldValues: FieldValues {
        var values = FieldValues()
        let properties = metadata.properties
        values.title = properties.title
        values.author = properties.author
        values.subject = properties.subject
        values.company = properties.company
        values.filename = displayName ?? "Untitled"
        values.bodyFontFamily = styleSheet.theme.bodyFont
        values.startingPageNumber = metadata.headerFooter.startingPageNumber
        values.numberFormat = metadata.headerFooter.numberFormat
        return values
    }

    /// Revision id → author.
    var revisionAuthors: [String: String] {
        Dictionary(metadata.revisions.map { ($0.id, $0.author) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Metadata changes (undoable)

    /// Applies a change to document metadata as one undoable step.
    func updateMetadata(_ actionName: String, _ change: (inout DocumentMetadata) -> Void) {
        var updated = metadata
        change(&updated)
        guard updated != metadata else { return }
        replaceMetadata(with: updated, actionName: actionName)
    }

    private func replaceMetadata(with updated: DocumentMetadata, actionName: String) {
        let previous = metadata
        undoManager?.registerUndo(withTarget: self) { document in
            document.replaceMetadata(with: previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        metadata = updated
        metadataDidChange(layoutChanged: previous.decoration != updated.decoration
            || previous.headerFooter != updated.headerFooter
            || previous.theme != updated.theme
            || previous.styles != updated.styles
            || previous.properties != updated.properties
            || previous.tracking != updated.tracking
            || previous.footnotes != updated.footnotes)
    }

    /// Changes metadata without undo (e.g. while loading or from generated content).
    func setMetadataSilently(_ change: (inout DocumentMetadata) -> Void) {
        change(&metadata)
        metadataDidChange(layoutChanged: true)
    }

    private func metadataDidChange(layoutChanged: Bool) {
        cachedStyleSheet = nil
        objectWillChange.send()
        if layoutChanged { onLayoutSettingsChange?() }
    }

    // MARK: - Reading

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        guard let format = DocumentFormat(typeName: typeName) else {
            throw WiredPaperError.unsupportedFormat(typeName)
        }
        let codec = try DocumentCodecRegistry.codec(for: format)
        let contents = try codec.read(from: fileWrapper, defaultAttributes: StyleCatalog.attributes(for: .normal))
        apply(contents)
    }

    private func apply(_ contents: DocumentContents) {
        textStorage.beginEditing()
        textStorage.setAttributedString(contents.text)
        textStorage.endEditing()

        if let loaded = contents.metadata { metadata = loaded }
        if let setup = contents.pageSetup, setup.isValid {
            pageSetup = setup
            setup.apply(to: printInfo)
        }
        AttachmentNormalizer.normalize(textStorage, maxSize: geometry.maxAttachmentSize)
        CharacterEffects.restoreSmallCaps(in: textStorage)
        metadataDidChange(layoutChanged: true)

        // Revert replaces content wholesale, so existing undo actions no longer apply.
        undoManager?.removeAllActions()
    }

    /// Fills a new, untitled document with generated content (mail merge, labels, envelopes).
    func loadGenerated(_ text: NSAttributedString, pageSetup setup: PageSetup, metadata generated: DocumentMetadata) {
        var metadata = generated
        metadata.pageSetup = setup
        apply(DocumentContents(text: text, pageSetup: setup, metadata: metadata))
    }

    func load(template: DocumentTemplate) {
        textStorage.setAttributedString(template.makeContent(pageSetup))
        AttachmentNormalizer.normalize(textStorage, maxSize: geometry.maxAttachmentSize)
        metadata.templateID = template.id
    }

    // MARK: - Writing

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard let format = DocumentFormat(typeName: typeName) else {
            throw WiredPaperError.unsupportedFormat(typeName)
        }
        editor?.prepareForSaving()

        var snapshotMetadata = metadata
        snapshotMetadata.modified = Date()
        snapshotMetadata.generator = DocumentMetadata.generatorString
        snapshotMetadata.pageSetup = pageSetup
        if let zoom = editor?.zoom { snapshotMetadata.zoom = Double(zoom) }

        let snapshot = DocumentContents(
            text: NSAttributedString(attributedString: textStorage),
            pageSetup: pageSetup,
            metadata: snapshotMetadata
        )
        return try DocumentCodecRegistry.codec(for: format).write(snapshot)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation, let existing = fileURL {
            BackupManager.backUp(existing, documentID: metadata.documentID)
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            completionHandler(error)
            self?.notifyStatusChanged()
        }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        notifyStatusChanged()
    }

    private func notifyStatusChanged() {
        for controller in windowControllers {
            (controller as? DocumentWindowController)?.updateStatusSubtitle()
        }
    }

    // MARK: - Page setup

    func updatePageSetup(_ setup: PageSetup) {
        guard setup != pageSetup, setup.isValid else { return }
        let previous = pageSetup
        undoManager?.registerUndo(withTarget: self) { document in
            document.updatePageSetup(previous)
        }
        undoManager?.setActionName("Document Setup")
        pageSetup = setup
        setup.apply(to: printInfo)
        onLayoutSettingsChange?()
    }

    /// Page Setup… changes the paper; keep our margins and adopt the new size.
    override func shouldChangePrintInfo(_ newPrintInfo: NSPrintInfo) -> Bool {
        var setup = pageSetup
        setup.paperSize = newPrintInfo.paperSize
        if setup.isValid, setup != pageSetup {
            pageSetup = setup
            onLayoutSettingsChange?()
        }
        return true
    }

    // MARK: - Printing & PDF

    /// Options chosen in the print panel.
    var printOptions = PrintOptions()

    func printConfiguration(options: PrintOptions? = nil) -> PrintConfiguration {
        let options = options ?? printOptions
        var text = NSAttributedString(attributedString: textStorage)
        if options.includeComments {
            text = CommentPrinter.appendingComments(to: text, threads: metadata.comments)
        }
        var configuration = PrintConfiguration(text: text, pageSetup: pageSetup)
        configuration.geometry = geometry
        configuration.decoration = metadata.decoration
        configuration.headerFooter = metadata.headerFooter
        configuration.fields = fieldValues
        configuration.markupMode = options.includeMarkup ? metadata.tracking.markupMode : .none
        configuration.revisionAuthors = revisionAuthors
        configuration.printBackgrounds = options.includeBackgrounds
        configuration.showHiddenText = options.includeHiddenText
        configuration.verticalAlignment = metadata.decoration.verticalAlignment
        configuration.liveValues = LiveValues.compute(for: text, metadata: metadata)
        if metadata.footnotes.contains(where: { !$0.isEndnote }) {
            let footnotes = FootnoteLayout(records: metadata.footnotes)
            footnotes.numbers = configuration.liveValues.noteNumbers
            footnotes.fontFamily = styleSheet.theme.bodyFont
            configuration.footnotes = footnotes
        }
        return configuration
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.dictionary().addEntries(from: printSettings)
        // The print view draws whole sheets, margins included.
        info.topMargin = 0
        info.leftMargin = 0
        info.bottomMargin = 0
        info.rightMargin = 0
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let view = PrintPagesView(configuration: printConfiguration())
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        operation.printPanel.options.insert([.showsCopies, .showsPageRange, .showsPreview, .showsScaling, .showsPaperSize, .showsOrientation])
        operation.printPanel.addAccessoryController(PrintOptionsController(document: self))
        return operation
    }
}

/// Options offered in the print panel and export sheet.
struct PrintOptions: Equatable {
    var includeMarkup = true
    var includeComments = false
    var includeBackgrounds = true
    var includeHiddenText = false
}
