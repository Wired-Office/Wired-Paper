import AppKit
import Combine

/// Coordinates one document window's editing surface: the shared layout
/// manager, the pages, find, zoom, and the formatting commands used by the
/// format bar and menus. Publishes state for the SwiftUI chrome.
final class EditorController: NSObject, ObservableObject {
    static let minZoom: CGFloat = 0.25
    static let maxZoom: CGFloat = 4
    static let zoomSteps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]

    @Published private(set) var formatting = FormattingState()
    @Published private(set) var currentPage = 1
    @Published private(set) var pageCount = 1
    @Published private(set) var statistics = DocumentStatistics.empty
    @Published private(set) var selectionStatistics: DocumentStatistics?
    @Published private(set) var zoom: CGFloat = 1
    @Published var lastTextColor: NSColor = ColorPalettes.defaultTextColor
    @Published var lastHighlightColor: NSColor = ColorPalettes.defaultHighlightColor

    @Published private(set) var activeCommentID: String?
    @Published var isFormatPainterActive = false
    @Published var showsHiddenText = false
    /// Viewing mode (title bar ▸ Viewing): the document can't be changed.
    @Published var isViewing = false
    /// Attributes captured by the format painter.
    var formatPainterSource: (character: [NSAttributedString.Key: Any], paragraph: NSParagraphStyle?)?
    /// Guards against re-entrant list renumbering.
    var isRenumbering = false
    /// Set while making internal changes that editing restrictions shouldn't block.
    var bypassProtection = false
    /// Message shown when an edit is blocked by document protection.
    @Published var protectionNotice: String?
    /// Side panes and their state.
    let sidebar = SidebarModel()
    private(set) lazy var revisionTracker = RevisionTracker(editor: self)
    /// AI writing suggestions shown as gray text after the insertion point.
    private(set) lazy var inlineCompletion = InlineCompletionController(editor: self)
    private var outlineRefreshPending = false

    private(set) weak var document: WiredPaperDocument?
    let textStorage: NSTextStorage
    let layoutManager = WPLayoutManager()
    let textFinder = NSTextFinder()
    private(set) var engine: PaginationEngine!
    private(set) var renderer: PageRenderer!
    private(set) var pagesView: PagesView!
    private(set) weak var scrollView: DocumentScrollView?
    private let footnoteLayout = FootnoteLayout(records: [])

    private lazy var findClient = DocumentFindClient(editor: self)
    private weak var activeTextView: PageTextView?
    private var statisticsTimer: Timer?
    private var stateUpdatePending = false
    private var observers: [NSObjectProtocol] = []

    init(document: WiredPaperDocument) {
        self.document = document
        self.textStorage = document.textStorage
        super.init()
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)
        textStorage.delegate = self
        document.onLayoutSettingsChange = { [weak self] in
            self?.applyDocumentLayout()
        }
    }

    var pageSetup: PageSetup {
        document?.pageSetup ?? AppSettings.shared.defaultPageSetup
    }

    var geometry: PageGeometry {
        document?.geometry ?? PageGeometry(setup: pageSetup)
    }

    var styleSheet: StyleSheet {
        document?.styleSheet ?? .standard
    }

    // MARK: - Setup & teardown

    func attach(to scrollView: DocumentScrollView) {
        self.scrollView = scrollView
        let engine = PaginationEngine(layoutManager: layoutManager, geometry: geometry)
        let renderer = PageRenderer(geometry: geometry)
        renderer.engine = engine
        renderer.footnoteHeight = { [weak self] page in
            guard let self, let engine = self.engine, engine.reserveProvider != nil else { return 0 }
            return self.footnoteLayout.reserve(forPage: page, engine: engine)
        }
        renderer.footnoteDrawer = { [weak self] page, rect in
            guard let self, let engine = self.engine else { return }
            self.footnoteLayout.draw(page: page, in: rect, engine: engine)
        }
        self.engine = engine
        self.renderer = renderer
        engine.onLayoutSettled = { [weak self] in self?.layoutSettled() }

        let pages = PagesView(engine: engine, renderer: renderer)
        pages.configureTextView = { [unowned self] textView in configure(textView) }
        pages.onPageCountChange = { [weak self] count in
            self?.pageCount = count
            self?.scheduleStateUpdate()
        }
        pagesView = pages
        scrollView.documentView = pages
        applyDocumentLayout(invalidate: false)
        engine.addPage()
        if textStorage.length > 0 {
            // Typing attributes otherwise stay at AppKit's default until the selection first moves.
            pages.pages[0].textView.typingAttributes = textStorage.attributes(at: 0, effectiveRange: nil)
        }

        textFinder.client = findClient
        textFinder.findBarContainer = scrollView
        textFinder.isIncrementalSearchingEnabled = true
        textFinder.incrementalSearchingShouldDimContentView = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            guard let self, let scrollView = self.scrollView else { return }
            self.zoom = scrollView.magnification
        })
        observers.append(center.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        })
        inlineCompletion.onChange = { [weak self] old, new in
            self?.redrawSuggestion(old)
            self?.redrawSuggestion(new)
        }

        if let saved = document?.metadata.zoom, saved > 0 {
            setZoom(CGFloat(saved), animated: false)
        }
        applySettings()
        scheduleStatistics(delay: 0)
        refreshState()
    }

    func tearDown() {
        statisticsTimer?.invalidate()
        inlineCompletion.isEnabled = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        textFinder.findBarContainer = nil
        textFinder.client = nil
        if textStorage.delegate === self { textStorage.delegate = nil }
        textStorage.removeLayoutManager(layoutManager)
    }

    private func configure(_ textView: PageTextView) {
        textView.editor = self
        textView.delegate = self
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFontPanel = true
        textView.usesRuler = true
        textView.usesInspectorBar = false
        textView.usesFindBar = false
        textView.usesFindPanel = false
        textView.isIncrementalSearchingEnabled = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.displaysLinkToolTips = true
        textView.smartInsertDeleteEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.drawsBackground = false
        textView.insertionPointColor = .black
        textView.linkTextAttributes = [
            .foregroundColor: Theme.linkInk,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.defaultParagraphStyle = styleSheet.paragraphStyle(for: ParagraphStyleKind.normal.rawValue)
        // New text views (after a column change) start with AppKit defaults, so
        // restore the typing attributes and ruler visibility.
        if textStorage.length == 0 {
            textView.typingAttributes = styleSheet.attributes(for: ParagraphStyleKind.normal.rawValue)
        } else if let current = activeTextView, current !== textView {
            textView.typingAttributes = current.typingAttributes
        } else {
            let location = min(textView.selectedRange().location, textStorage.length - 1)
            textView.typingAttributes = textStorage.attributes(at: max(location, 0), effectiveRange: nil)
        }
        textView.isRulerVisible = scrollView?.rulersVisible ?? AppSettings.shared.showRuler
        applySettings(to: textView)
    }

    private func applySettings() {
        guard let pagesView else { return }
        pagesView.allTextViews.forEach { applySettings(to: $0) }
        scrollView?.applyRulerUnits(AppSettings.shared.measurementUnit)
        inlineCompletion.isEnabled = AppSettings.shared.inlineSuggestions
    }

    private func redrawSuggestion(_ suggestion: InlineCompletionController.Suggestion?) {
        guard let suggestion, pagesView != nil else { return }
        let textView = textView(containingCharacterAt: max(suggestion.location - 1, 0)).textView
        if let rect = textView.suggestionRect(for: suggestion) {
            textView.setNeedsDisplay(rect.insetBy(dx: -2, dy: -4))
        } else {
            textView.needsDisplay = true
        }
    }

    private func applySettings(to textView: NSTextView) {
        let settings = AppSettings.shared
        textView.isContinuousSpellCheckingEnabled = settings.checkSpellingWhileTyping
        textView.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = settings.smartDashes
        textView.isAutomaticLinkDetectionEnabled = settings.autoLinkDetection
    }

    /// Ends typing coalescing so a save captures a clean undo boundary.
    func prepareForSaving() {
        textView.breakUndoCoalescing()
    }

    // MARK: - Text views

    /// The page text view that commands should act on.
    var textView: PageTextView {
        if let responder = scrollView?.window?.firstResponder as? PageTextView, responder.editor === self {
            return responder
        }
        if let active = activeTextView, active.superview != nil {
            return active
        }
        return pagesView.pages[0].textView
    }

    func textViewDidBecomeActive(_ textView: PageTextView) {
        activeTextView = textView
        scheduleStateUpdate()
    }

    func focusTextView() {
        let textView = self.textView
        textView.window?.makeFirstResponder(textView)
    }

    func scrollToTop() {
        guard let scrollView else { return }
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// The column text view holding `index`, plus that column's character range.
    func textView(containingCharacterAt index: Int) -> (textView: PageTextView, characters: NSRange) {
        let fallback = (pagesView.pages[0].textView, NSRange(location: 0, length: textStorage.length))
        guard textStorage.length > 0 else { return fallback }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(index, textStorage.length - 1))
        var glyphRange = NSRange()
        guard glyph < layoutManager.numberOfGlyphs,
              let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: &glyphRange),
              let textView = pagesView.textView(for: container)
        else { return fallback }
        return (textView, layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
    }

    func scrollRangeToVisible(_ range: NSRange) {
        guard textStorage.length > 0 else { return }
        let (textView, _) = textView(containingCharacterAt: range.location)
        guard let container = textView.textContainer else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = textView.textContainerOrigin
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -24, dy: -48)
        textView.scrollToVisible(rect)
    }

    /// Selects a range and scrolls it into view.
    func reveal(_ range: NSRange) {
        guard NSMaxRange(range) <= textStorage.length else { return }
        focusTextView()
        textView.setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    // MARK: - State

    private func scheduleStateUpdate() {
        guard !stateUpdatePending else { return }
        stateUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            self?.stateUpdatePending = false
            self?.refreshState()
        }
    }

    func refreshState() {
        guard pagesView != nil else { return }
        refreshFormattingState()
        refreshCurrentPage()
        refreshSelectionStatistics()
    }

    private func refreshFormattingState() {
        let textView = self.textView
        let selection = textView.selectedRange()
        let length = textStorage.length

        let characterAttributes: [NSAttributedString.Key: Any]
        if selection.length == 0 || length == 0 {
            characterAttributes = textView.typingAttributes
        } else {
            characterAttributes = textStorage.attributes(at: min(selection.location, length - 1), effectiveRange: nil)
        }

        // Paragraph-level state comes from the paragraph holding the insertion point.
        let paragraphAttributes: [NSAttributedString.Key: Any]
        if selection.location < length {
            paragraphAttributes = textStorage.attributes(at: selection.location, effectiveRange: nil)
        } else {
            paragraphAttributes = textView.typingAttributes
        }

        let font = characterAttributes[.font] as? NSFont ?? StyleCatalog.bodyFont
        let traits = NSFontManager.shared.traits(of: font)
        let paragraph = paragraphAttributes[.paragraphStyle] as? NSParagraphStyle ?? textView.defaultParagraphStyle ?? .default

        var state = FormattingState()
        state.fontFamily = font.familyName ?? font.fontName
        state.fontSize = font.pointSize
        state.isBold = traits.contains(.boldFontMask)
        state.isItalic = traits.contains(.italicFontMask)
        state.isUnderlined = (characterAttributes[.underlineStyle] as? Int ?? 0) != 0
        state.isStruckThrough = (characterAttributes[.strikethroughStyle] as? Int ?? 0) != 0
        state.textColor = characterAttributes[.foregroundColor] as? NSColor
        state.highlightColor = characterAttributes[.backgroundColor] as? NSColor
        state.hasLink = characterAttributes[.link] != nil
        state.alignment = paragraph.alignment
        state.lineHeightMultiple = paragraph.lineHeightMultiple == 0 ? 1 : paragraph.lineHeightMultiple
        state.listKind = paragraph.textLists.last.flatMap { ListKind(markerFormat: $0.markerFormat) }
        state.isInTable = paragraph.textBlocks.contains { $0 is NSTextTableBlock }
        state.styleID = paragraphAttributes[.wpParagraphStyle] as? String ?? ParagraphStyleKind.normal.rawValue
        state.styleName = styleSheet.displayName(state.styleID)
        state.isAllCaps = CharacterEffects.hasFlag(CharacterFlags.allCaps, attributes: characterAttributes)
        state.isSmallCaps = CharacterEffects.hasFlag(CharacterFlags.smallCaps, attributes: characterAttributes)
        state.isHidden = characterAttributes[.wpHidden] != nil
        state.isDoubleUnderline = (characterAttributes[.underlineStyle] as? Int ?? 0) & NSUnderlineStyle.double.rawValue == NSUnderlineStyle.double.rawValue
        state.isSuperscript = (characterAttributes[.superscript] as? Int ?? 0) > 0
        state.isSubscript = (characterAttributes[.superscript] as? Int ?? 0) < 0
        state.paragraphFlags = FlagTokens.set(paragraphAttributes[.wpParaFlags])

        if state != formatting { formatting = state }
    }

    private func refreshCurrentPage() {
        guard let engine else { return }
        let page = engine.page(forCharacterAt: textView.selectedRange().location) + 1
        if currentPage != page { currentPage = page }
    }

    private func refreshSelectionStatistics() {
        let selection = textView.selectedRange()
        guard selection.length > 0, selection.length < 400_000, NSMaxRange(selection) <= textStorage.length else {
            if selectionStatistics != nil { selectionStatistics = nil }
            return
        }
        let stats = DocumentStatistics.compute((textStorage.string as NSString).substring(with: selection))
        if stats != selectionStatistics { selectionStatistics = stats }
    }

    private func scheduleStatistics(delay: TimeInterval = 0.4) {
        statisticsTimer?.invalidate()
        statisticsTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let text = self?.textStorage.string else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let stats = DocumentStatistics.compute(text)
                DispatchQueue.main.async {
                    if self?.statistics != stats { self?.statistics = stats }
                }
            }
        }
    }

    private func didChangeFormatting() {
        refreshFormattingState()
        focusTextView()
    }

    // MARK: - Document layout

    /// Applies page geometry, decoration, headers/footers, markup mode and
    /// footnotes from the document to the engine and renderer.
    func applyDocumentLayout(invalidate: Bool = true) {
        guard let document, let engine, let renderer else { return }
        let metadata = document.metadata
        let decoration = metadata.decoration

        engine.verticalAlignment = decoration.verticalAlignment
        engine.widowControl = decoration.widowControl
        engine.policy.markupMode = metadata.tracking.markupMode
        layoutManager.usesDefaultHyphenation = decoration.hyphenation
        layoutManager.fieldValues = document.fieldValues

        renderer.decoration = decoration
        renderer.headerFooter = metadata.headerFooter
        renderer.fields = document.fieldValues
        renderer.markupMode = metadata.tracking.markupMode
        renderer.showChangeBars = metadata.tracking.markupMode == .simple

        footnoteLayout.update(records: metadata.footnotes)
        footnoteLayout.fontFamily = styleSheet.theme.bodyFont
        let hasFootnotes = metadata.footnotes.contains { !$0.isEndnote }
        engine.reserveProvider = hasFootnotes ? { [weak self] page in
            guard let self, let engine = self.engine else { return 0 }
            return self.footnoteLayout.reserve(forPage: page, engine: engine)
        } : nil

        engine.setGeometry(document.geometry)
        renderer.geometry = engine.geometry
        AttachmentNormalizer.normalize(textStorage, maxSize: engine.geometry.maxAttachmentSize)
        pagesView?.allTextViews.first?.defaultParagraphStyle = styleSheet.paragraphStyle(for: ParagraphStyleKind.normal.rawValue)

        if invalidate {
            engine.invalidateAllGlyphs()
            refreshMarkup()
        }
        pagesView?.refreshPages()
        scheduleStateUpdate()
    }

    /// Called whenever pagination settles after an edit.
    private func layoutSettled() {
        let values = LiveValues.compute(for: textStorage, metadata: document?.metadata)
        if values != layoutManager.liveValues {
            values.apply(to: layoutManager)
            footnoteLayout.numbers = values.noteNumbers
            layoutManager.invalidateLiveObjects()
        }
        footnoteLayout.numbers = values.noteNumbers
        pagesView?.refreshPages()
        if pageCount != engine.pageCount { pageCount = engine.pageCount }
        scheduleStateUpdate()
        scheduleOutlineRefresh()
        onLayoutSettled?()
    }

    private func scheduleOutlineRefresh() {
        guard !outlineRefreshPending else { return }
        outlineRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.outlineRefreshPending = false
            self.refreshOutline()
            self.sidebar.revision += 1
        }
    }

    /// Observers of settled layout (navigation pane, comments pane…).
    var onLayoutSettled: (() -> Void)?
    /// Asks the window to open the editor for the object at a location.
    var onEditObject: ((DocumentObject, Int) -> Void)?
    let mergePreviewState = MergePreviewState()

    // MARK: - Screen markup (tracked changes, comments, hidden text)

    func refreshMarkup(in range: NSRange? = nil) {
        guard let document else { return }
        let full = NSRange(location: 0, length: textStorage.length)
        var target = range ?? full
        target = NSIntersectionRange(target, full)
        guard target.length > 0 else { return }
        RevisionMarkup.applyScreenMarkup(
            to: layoutManager,
            range: target,
            mode: document.metadata.tracking.markupMode,
            authors: document.revisionAuthors,
            activeComment: activeCommentID
        )
    }

    func setActiveComment(_ id: String?) {
        guard id != activeCommentID else { return }
        activeCommentID = id
        refreshMarkup()
    }

    // MARK: - Character formatting

    func toggleBold() {
        let bold = !formatting.isBold
        let manager = NSFontManager.shared
        TextFormatter.changeFonts(in: textView, actionName: "Bold") {
            bold ? manager.convert($0, toHaveTrait: .boldFontMask) : manager.convert($0, toNotHaveTrait: .boldFontMask)
        }
        didChangeFormatting()
    }

    func toggleItalic() {
        let italic = !formatting.isItalic
        let manager = NSFontManager.shared
        TextFormatter.changeFonts(in: textView, actionName: "Italic") {
            italic ? manager.convert($0, toHaveTrait: .italicFontMask) : manager.convert($0, toNotHaveTrait: .italicFontMask)
        }
        didChangeFormatting()
    }

    func toggleUnderline() {
        let value: Int? = formatting.isUnderlined ? nil : NSUnderlineStyle.single.rawValue
        TextFormatter.setAttribute(.underlineStyle, to: value, in: textView, actionName: "Underline")
        didChangeFormatting()
    }

    func toggleStrikethrough() {
        let value: Int? = formatting.isStruckThrough ? nil : NSUnderlineStyle.single.rawValue
        TextFormatter.setAttribute(.strikethroughStyle, to: value, in: textView, actionName: "Strikethrough")
        didChangeFormatting()
    }

    func setFontFamily(_ family: String) {
        let manager = NSFontManager.shared
        TextFormatter.changeFonts(in: textView, actionName: "Font") { font in
            let traits = manager.traits(of: font)
            return FontResolver.font(
                family: family,
                size: font.pointSize,
                bold: traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask)
            )
        }
        didChangeFormatting()
    }

    func setFontSize(_ size: CGFloat) {
        let size = min(max(size, 1), 1638)
        TextFormatter.changeFonts(in: textView, actionName: "Font Size") {
            NSFontManager.shared.convert($0, toSize: size)
        }
        didChangeFormatting()
    }

    func adjustFontSize(larger: Bool) {
        let sizes = FontSizeField.standardSizes
        TextFormatter.changeFonts(in: textView, actionName: larger ? "Bigger" : "Smaller") { font in
            let current = font.pointSize
            let next = larger
                ? sizes.first { $0 > current + 0.01 } ?? current + 12
                : sizes.last { $0 < current - 0.01 } ?? max(current - 1, 1)
            return NSFontManager.shared.convert(font, toSize: next)
        }
        didChangeFormatting()
    }

    func setTextColor(_ color: NSColor?) {
        if let color { lastTextColor = color }
        TextFormatter.setAttribute(.foregroundColor, to: color, in: textView, actionName: "Text Color")
        didChangeFormatting()
    }

    func setHighlight(_ color: NSColor?) {
        if let color { lastHighlightColor = color }
        TextFormatter.setAttribute(.backgroundColor, to: color, in: textView, actionName: "Highlight")
        didChangeFormatting()
    }

    func clearFormatting() {
        TextFormatter.clearFormatting(in: textView)
        didChangeFormatting()
    }

    // MARK: - Paragraph formatting

    func setAlignment(_ alignment: NSTextAlignment) {
        let textView = self.textView
        switch alignment {
        case .center: textView.alignCenter(nil)
        case .right: textView.alignRight(nil)
        case .justified: textView.alignJustified(nil)
        default: textView.alignLeft(nil)
        }
        didChangeFormatting()
    }

    func applyStyle(_ kind: ParagraphStyleKind) {
        applyStyle(id: kind.rawValue)
    }

    func applyStyle(id: String) {
        TextFormatter.applyStyle(id: id, sheet: styleSheet, in: textView)
        didChangeFormatting()
    }

    func toggleList(_ kind: ListKind) {
        ListFormatter.toggle(kind, in: textView)
        didChangeFormatting()
    }

    func changeIndent(by delta: CGFloat) {
        TextFormatter.changeParagraphs(in: textView, actionName: delta > 0 ? "Increase Indent" : "Decrease Indent") { style in
            let head = max(style.headIndent + delta, 0)
            let shift = head - style.headIndent
            style.headIndent = head
            style.firstLineHeadIndent = max(style.firstLineHeadIndent + shift, 0)
        }
        didChangeFormatting()
    }

    func setLineSpacing(_ multiple: CGFloat) {
        TextFormatter.changeParagraphs(in: textView, actionName: "Line Spacing") { style in
            style.lineHeightMultiple = multiple
            style.lineSpacing = 0
        }
        didChangeFormatting()
    }

    func currentParagraphSettings() -> ParagraphSettings {
        let textView = self.textView
        let location = textView.selectedRange().location
        let style: NSParagraphStyle?
        if location < textStorage.length {
            style = textStorage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        } else {
            style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return ParagraphSettings(style ?? textView.defaultParagraphStyle ?? .default)
    }

    func applyParagraphSettings(_ settings: ParagraphSettings) {
        TextFormatter.changeParagraphs(in: textView, actionName: "Paragraph") { style in
            settings.apply(to: style)
        }
        didChangeFormatting()
    }

    // MARK: - Insertion

    func insertTable(rows: Int, columns: Int) {
        TableBuilder.insertTable(rows: rows, columns: columns, into: textView)
        didChangeFormatting()
    }

    func addTableRow() {
        let location = textView.selectedRange().location
        TableBuilder.appendRow(toTableAt: min(location, max(textStorage.length - 1, 0)), in: textView)
        didChangeFormatting()
    }

    func insertImage() {
        guard let window = scrollView?.window else { return }
        ImageInserter.chooseAndInsert(into: textView, window: window, maxSize: geometry.maxAttachmentSize)
    }

    func insertPageBreak() {
        textView.insertContainerBreak(nil)
        textView.undoManager?.setActionName("Page Break")
        focusTextView()
    }

    func insertHorizontalRule() {
        let textView = self.textView
        let string = textStorage.string as NSString
        let selection = textView.selectedRange()
        var base = TextFormatter.baseAttributes(for: textView)
        base[.paragraphStyle] = StyleCatalog.paragraphStyle(for: .normal)

        let content = NSMutableAttributedString()
        if !TextFormatter.isAtParagraphStart(selection.location, in: string) {
            content.append(NSAttributedString(string: "\n", attributes: base))
        }
        let rule = NSMutableAttributedString(attachment: HorizontalRule.makeAttachment())
        rule.addAttributes(base, range: NSRange(location: 0, length: rule.length))
        content.append(rule)
        content.append(NSAttributedString(string: "\n", attributes: base))
        TextFormatter.replaceSelection(in: textView, with: content, actionName: "Horizontal Line")
        didChangeFormatting()
    }

    func insertCurrentDate() {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let textView = self.textView
        textView.insertText(formatter.string(from: Date()), replacementRange: textView.selectedRange())
        focusTextView()
    }

    // MARK: - Links

    struct LinkContext {
        var text: String
        var url: String
        var range: NSRange
    }

    func linkContext() -> LinkContext {
        var range = textView.selectedRange()
        var url = ""
        if textStorage.length > 0 {
            let probe = min(range.location, textStorage.length - 1)
            var effective = NSRange()
            let full = NSRange(location: 0, length: textStorage.length)
            if let value = textStorage.attribute(.link, at: probe, longestEffectiveRange: &effective, in: full) {
                url = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                if range.length == 0 { range = effective }
            }
        }
        let text = NSMaxRange(range) <= textStorage.length ? (textStorage.string as NSString).substring(with: range) : ""
        return LinkContext(text: text, url: url, range: range)
    }

    func applyLink(text: String, urlString: String, range: NSRange) {
        let textView = self.textView
        let url = Self.normalizedURL(urlString)
        let existing = NSMaxRange(range) <= textStorage.length ? (textStorage.string as NSString).substring(with: range) : ""
        textView.setSelectedRange(range)

        if range.length == 0 || (!text.isEmpty && text != existing) {
            var attributes = range.length > 0 ? textStorage.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes
            attributes.removeValue(forKey: .attachment)
            attributes[.link] = url
            let display = text.isEmpty ? urlString : text
            TextFormatter.replaceSelection(in: textView, with: NSAttributedString(string: display, attributes: attributes), actionName: "Link")
        } else {
            TextFormatter.setAttribute(.link, to: url, in: textView, actionName: url == nil ? "Remove Link" : "Link")
        }
        didChangeFormatting()
    }

    static func normalizedURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") || trimmed.hasPrefix("tel:") {
            return URL(string: trimmed)
        }
        if trimmed.contains("@") && !trimmed.contains("/") {
            return URL(string: "mailto:" + trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    // MARK: - Tables

    /// Tab / Shift-Tab inside a table moves between cells; Tab in the last cell adds a row.
    func moveToAdjacentTableCell(forward: Bool) -> Bool {
        let textView = self.textView
        guard textStorage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, textStorage.length - 1)
        guard let block = TableBuilder.tableBlock(at: location, in: textStorage) else { return false }
        let cell = textStorage.range(of: block, at: location)

        if forward {
            let next = NSMaxRange(cell)
            if let nextBlock = TableBuilder.tableBlock(at: next, in: textStorage), nextBlock.table === block.table {
                selectCell(textStorage.range(of: nextBlock, at: next))
            } else {
                TableBuilder.appendRow(toTableAt: location, in: textView)
            }
        } else if cell.location > 0,
                  let previous = TableBuilder.tableBlock(at: cell.location - 1, in: textStorage),
                  previous.table === block.table {
            selectCell(textStorage.range(of: previous, at: cell.location - 1))
        }
        refreshFormattingState()
        return true
    }

    private func selectCell(_ range: NSRange) {
        let selection = NSRange(location: range.location, length: max(range.length - 1, 0))
        textView.setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    // MARK: - Find

    func performFindAction(_ sender: Any?) {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        guard let action = NSTextFinder.Action(rawValue: tag) else { return }
        textFinder.performAction(action)
    }

    func validateFindAction(_ tag: Int) -> Bool {
        guard let action = NSTextFinder.Action(rawValue: tag) else { return false }
        return textFinder.validateAction(action)
    }

    // MARK: - Zoom

    func setZoom(_ value: CGFloat, animated: Bool = true) {
        let clamped = min(max(value, Self.minZoom), Self.maxZoom)
        zoom = clamped
        guard let scrollView else { return }
        let visible = scrollView.documentVisibleRect
        let center = NSPoint(x: visible.midX, y: visible.midY)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                scrollView.animator().magnification = clamped
            }
        } else {
            scrollView.setMagnification(clamped, centeredAt: center)
        }
    }

    func zoomIn() {
        setZoom(Self.zoomSteps.first { $0 > zoom + 0.001 } ?? Self.maxZoom)
    }

    func zoomOut() {
        setZoom(Self.zoomSteps.last { $0 < zoom - 0.001 } ?? Self.minZoom)
    }

    func zoomToPageWidth() {
        guard let scrollView else { return }
        let available = scrollView.contentSize.width - 32
        setZoom(available / (geometry.paperSize.width * CGFloat(max(pagesView?.pagesPerRow ?? 1, 1)) + 16))
    }
}

// MARK: - NSTextViewDelegate

extension EditorController: NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            // After the edit (if any) has been seen by textDidChange.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.inlineCompletion.selectionDidChange(in: textView)
            }
        }
        applyFormatPainterIfNeeded()
        scheduleStateUpdate()
        updateActiveCommentFromSelection()
    }

    func textDidChange(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            inlineCompletion.textDidChange(in: textView)
        }
        renumberListsIfNeeded()
        scheduleStatistics()
        scheduleStateUpdate()
    }

    func textViewDidChangeTypingAttributes(_ notification: Notification) {
        scheduleStateUpdate()
    }

    /// Typed text must not inherit objects, anchors or tracked-change marks from its neighbors.
    func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:], toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        var attributes = newTypingAttributes
        for key in [NSAttributedString.Key.wpObject, .wpComment, .wpBookmark, .wpRevision, .wpAltText, .wpGenerated, .wpMergeField, .wpCitation, .wpIndexEntry] {
            attributes.removeValue(forKey: key)
        }
        return attributes
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        followInternalLink(link)
    }

    func textView(_ textView: NSTextView, clickedOn cell: any NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
        guard charIndex < textStorage.length,
              let object = DocumentObject.decode(textStorage.attribute(.wpObject, at: charIndex, effectiveRange: nil)) else { return }
        if object.form != nil {
            _ = handleFormControlClick(object, at: charIndex, in: textView, cellFrame: cellFrame)
        } else {
            textView.setSelectedRange(NSRange(location: charIndex, length: 1))
        }
    }

    func textView(_ textView: NSTextView, doubleClickedOn cell: any NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
        guard charIndex < textStorage.length,
              let object = DocumentObject.decode(textStorage.attribute(.wpObject, at: charIndex, effectiveRange: nil)),
              !object.isTextual, object.kind != .checkbox, object.kind != .date else { return }
        textView.setSelectedRange(NSRange(location: charIndex, length: 1))
        onEditObject?(object, charIndex)
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        document?.undoManager
    }
}

// MARK: - NSTextStorageDelegate

extension EditorController: NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) {
            textFinder.noteClientStringWillChange()
        }
        let paragraphStart = (textStorage.string as NSString).paragraphRange(for: NSRange(location: min(editedRange.location, textStorage.length), length: 0)).location
        engine?.noteTextChanged(at: paragraphStart)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        // Fit pasted or dropped images to the page.
        // Temporary markup must be recomputed after the storage finishes processing.
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: NSIntersectionRange(editedRange, NSRange(location: 0, length: textStorage.length)))
        DispatchQueue.main.async { [weak self] in self?.refreshMarkup(in: paragraphRange) }
        guard editedMask.contains(.editedCharacters), editedRange.length > 0 else { return }
        if revisionTracker.pendingInsertion != nil {
            revisionTracker.markPendingInsertion(in: textStorage)
        }
        AttachmentNormalizer.normalize(textStorage, in: editedRange, maxSize: geometry.maxAttachmentSize)
    }
}
