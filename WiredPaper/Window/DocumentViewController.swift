import AppKit
import Combine
import SwiftUI

/// Hosts the format bar, the paginated editor and the status bar, and handles
/// the document-level menu and toolbar actions that reach it through the
/// responder chain.
final class DocumentViewController: NSViewController, NSMenuItemValidation {
    let editor: EditorController
    private(set) weak var document: WiredPaperDocument?

    let scrollView = DocumentScrollView(frame: .zero)
    private(set) var formatBar: BarContainer!
    private(set) var statusBar: BarContainer!
    private var noticeBar: BarContainer!
    private let columns = NSStackView()
    private var leftPane: NSView!
    private var rightPane: NSView!
    private var subscriptions = Set<AnyCancellable>()
    private var hasAppeared = false
    let ribbon = RibbonModel()
    var focusModeState: FocusModeState?
    var onModeChange: ((DocumentMode) -> Void)?

    init(document: WiredPaperDocument) {
        self.document = document
        self.editor = EditorController(document: document)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View lifecycle

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 820))

        let ribbonRoot = RibbonView(model: ribbon, editor: editor, document: document ?? WiredPaperDocument(),
                                    isFocusMode: { [weak self] in self?.isInFocusMode ?? false })
        formatBar = makeBar(NSHostingView(rootView: ribbonRoot), separatorEdge: .minY, height: ribbon.height)
        ribbon.onCollapseChange = { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                self.formatBar.setBarHeight(self.ribbon.height)
                self.view.layoutSubtreeIfNeeded()
            }
        }
        statusBar = makeBar(NSHostingView(rootView: StatusBar(editor: editor)), separatorEdge: .maxY, height: 28)
        noticeBar = makeBar(NSHostingView(rootView: NoticeBar(editor: editor)), separatorEdge: .minY, height: 32)
        noticeBar.isHidden = true

        // The editor column: bars above and below the pages. Plain constraints,
        // not a vertical NSStackView: the stack view pulled the window down to its
        // minimum width (e.g. in full screen the content stayed 720 pt wide).
        let stack = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        let rows: [NSView] = [formatBar, noticeBar, scrollView, statusBar]
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            formatBar.topAnchor.constraint(equalTo: stack.topAnchor),
            noticeBar.topAnchor.constraint(equalTo: formatBar.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: noticeBar.bottomAnchor),
            statusBar.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            statusBar.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
        ])
        stack.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Sidebars either side of the editor column.
        let leftHost = NSHostingView(rootView: NavigationPane(editor: editor, sidebar: editor.sidebar))
        leftHost.sizingOptions = []
        let rightHost = NSHostingView(rootView: RightSidebar(editor: editor, sidebar: editor.sidebar))
        rightHost.sizingOptions = []
        leftPane = leftHost
        rightPane = rightHost
        leftPane.isHidden = true
        rightPane.isHidden = true

        // Panes | editor | panes, with fixed-width sidebars. Hidden panes detach.
        columns.orientation = .horizontal
        columns.spacing = 0
        columns.distribution = .fill
        columns.alignment = .height
        columns.detachesHiddenViews = true
        columns.translatesAutoresizingMaskIntoConstraints = false
        columns.setHuggingPriority(.defaultLow, for: .horizontal)
        columns.setHuggingPriority(.defaultLow, for: .vertical)
        for view in [leftPane!, stack as NSView, rightPane!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            columns.addArrangedSubview(view)
        }
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftPane.widthAnchor.constraint(equalToConstant: Self.leftPaneWidth).isActive = true
        rightPane.widthAnchor.constraint(equalToConstant: Self.rightPaneWidth).isActive = true
        root.addSubview(columns)

        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            columns.topAnchor.constraint(equalTo: root.topAnchor),
            columns.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        // Preferred size just below the window's "keep size" priority (500): the
        // window opens large instead of shrinking to its fitting size, yet the
        // user can still resize it freely.
        let preferredWidth = root.widthAnchor.constraint(equalToConstant: 1120)
        preferredWidth.priority = NSLayoutConstraint.Priority(490)
        let preferredHeight = root.heightAnchor.constraint(equalToConstant: 820)
        preferredHeight.priority = NSLayoutConstraint.Priority(490)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 720),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 460),
            preferredWidth,
            preferredHeight,
        ])

        view = root
    }

    /// Wraps a SwiftUI bar in a fixed-height container with a hairline separator.
    private func makeBar<Content: View>(_ host: NSHostingView<Content>, separatorEdge: NSRectEdge, height: CGFloat) -> BarContainer {
        host.sizingOptions = []
        let separator = NSBox()
        separator.boxType = .separator
        return BarContainer(height: height, content: host, separator: separator, separatorAtBottom: separatorEdge == .minY)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        editor.attach(to: scrollView)
        let settings = AppSettings.shared
        formatBar.isHidden = !settings.showFormatBar
        statusBar.isHidden = !settings.showStatusBar
        setRulerVisible(settings.showRuler)
        editor.onEditObject = { [weak self] object, location in self?.presentObjectEditor(object, location: location) }

        editor.sidebar.$left
            .receive(on: RunLoop.main)
            .sink { [weak self] pane in self?.setPane(self?.leftPane, visible: pane != nil, width: 250, leading: true) }
            .store(in: &subscriptions)
        editor.sidebar.$right
            .receive(on: RunLoop.main)
            .sink { [weak self] pane in self?.setPane(self?.rightPane, visible: pane != nil, width: 320, leading: false) }
            .store(in: &subscriptions)
        // Keep the title bar's mode menu in step with Track Changes and Viewing.
        (document?.objectWillChange.map { _ in () }.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher())
            .merge(with: editor.$isViewing.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.onModeChange?(self.documentMode)
            }
            .store(in: &subscriptions)
        editor.$protectionNotice
            .combineLatest(document?.objectWillChange.map { _ in () }.prepend(()).eraseToAnyPublisher() ?? Just(()).eraseToAnyPublisher())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateNoticeBar() }
            .store(in: &subscriptions)
    }

    private func setPane(_ pane: NSView?, visible: Bool, width: CGFloat, leading: Bool) {
        guard let pane, pane.isHidden == visible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            pane.isHidden = !visible
            view.layoutSubtreeIfNeeded()
        }
    }

    private static let leftPaneWidth: CGFloat = 250
    private static let rightPaneWidth: CGFloat = 320

    private func updateNoticeBar() {
        let protection = document?.metadata.protection
        let show = editor.protectionNotice != nil || protection?.markedFinal == true || (protection?.restriction ?? .none) != .none
        if noticeBar.isHidden == show { noticeBar.isHidden = !show }
    }

    /// Page text views share an "is ruler visible" flag and re-apply it to the
    /// scroll view whenever one becomes first responder, so set it through them.
    func setRulerVisible(_ visible: Bool) {
        editor.textView.isRulerVisible = visible
        scrollView.rulersVisible = visible
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppeared else { return }
        hasAppeared = true
        editor.scrollToTop()
        editor.focusTextView()
        editor.textView.updateRuler()
    }

    // MARK: - Character formatting

    @objc func formatBold(_ sender: Any?) { editor.toggleBold() }
    @objc func formatItalic(_ sender: Any?) { editor.toggleItalic() }
    @objc func formatUnderline(_ sender: Any?) { editor.toggleUnderline() }
    @objc func formatStrikethrough(_ sender: Any?) { editor.toggleStrikethrough() }
    @objc func increaseFontSize(_ sender: Any?) { editor.adjustFontSize(larger: true) }
    @objc func decreaseFontSize(_ sender: Any?) { editor.adjustFontSize(larger: false) }
    @objc func clearAllFormatting(_ sender: Any?) { editor.clearFormatting() }

    @objc func setTextColorFromMenu(_ sender: NSMenuItem) {
        editor.setTextColor(sender.representedObject as? NSColor)
    }

    @objc func setHighlightFromMenu(_ sender: NSMenuItem) {
        editor.setHighlight(sender.representedObject as? NSColor)
    }

    @objc func applyStyleFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        editor.applyStyle(id: id)
    }

    // MARK: - Paragraph formatting

    @objc func toggleBulletList(_ sender: Any?) { editor.toggleList(.bullet) }
    @objc func toggleNumberList(_ sender: Any?) { editor.toggleList(.numbered) }
    @objc func indentMore(_ sender: Any?) { editor.changeIndent(by: 36) }
    @objc func indentLess(_ sender: Any?) { editor.changeIndent(by: -36) }

    @objc func setLineSpacingFromMenu(_ sender: NSMenuItem) {
        editor.setLineSpacing(CGFloat(sender.tag) / 100)
    }

    @objc func showParagraphOptions(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let unit = AppSettings.shared.measurementUnit
        SheetPresenter.present(in: window) { dismiss in
            ParagraphSheet(settings: editor.currentParagraphSettings(), unit: unit, onApply: { settings in
                editor.applyParagraphSettings(settings)
                dismiss()
            }, onCancel: dismiss)
        }
    }

    // MARK: - Insert

    @objc func insertImageFromFile(_ sender: Any?) { editor.insertImage() }
    @objc func insertPageBreakAction(_ sender: Any?) { editor.insertPageBreak() }
    @objc func insertHorizontalRule(_ sender: Any?) { editor.insertHorizontalRule() }
    @objc func insertCurrentDate(_ sender: Any?) { editor.insertCurrentDate() }
    @objc func addTableRow(_ sender: Any?) { editor.addTableRow() }

    @objc func showInsertTableSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            InsertTableSheet(onInsert: { rows, columns in
                dismiss()
                editor.insertTable(rows: rows, columns: columns)
            }, onCancel: dismiss)
        }
    }

    @objc func showLinkSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let context = editor.linkContext()
        SheetPresenter.present(in: window) { dismiss in
            LinkSheet(text: context.text, url: context.url, isEditingExisting: !context.url.isEmpty, onApply: { text, url in
                dismiss()
                editor.applyLink(text: text, urlString: url, range: context.range)
            }, onRemove: {
                dismiss()
                editor.applyLink(text: context.text, urlString: "", range: context.range)
            }, onCancel: dismiss)
        }
    }

    // MARK: - File

    @objc func exportDocument(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        ExportController.beginExport(for: document, in: window)
    }

    @objc func showDocumentSetup(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let unit = AppSettings.shared.measurementUnit
        SheetPresenter.present(in: window) { dismiss in
            DocumentSetupSheet(setup: document.pageSetup, unit: unit, onApply: { setup in
                dismiss()
                document.updatePageSetup(setup)
            }, onCancel: dismiss)
        }
    }

    // MARK: - View

    @objc func zoomInDocument(_ sender: Any?) { editor.zoomIn() }
    @objc func zoomOutDocument(_ sender: Any?) { editor.zoomOut() }
    @objc func zoomDocumentToActualSize(_ sender: Any?) { editor.setZoom(1) }
    @objc func zoomDocumentToPageWidth(_ sender: Any?) { editor.zoomToPageWidth() }

    @objc func toggleFormatBar(_ sender: Any?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            formatBar.isHidden.toggle()
            view.layoutSubtreeIfNeeded()
        }
        AppSettings.shared.showFormatBar = !formatBar.isHidden
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        statusBar.isHidden.toggle()
        AppSettings.shared.showStatusBar = !statusBar.isHidden
    }

    @objc func toggleRulerVisibility(_ sender: Any?) {
        let visible = !scrollView.rulersVisible
        setRulerVisible(visible)
        AppSettings.shared.showRuler = visible
        if visible { editor.textView.updateRuler() }
    }

    // MARK: - Find (fallback when a page isn't first responder)

    @objc override func performTextFinderAction(_ sender: Any?) {
        editor.performFindAction(sender)
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let state = editor.formatting
        func check(_ on: Bool) { item.state = on ? .on : .off }

        switch item.action {
        case #selector(formatBold(_:)): check(state.isBold)
        case #selector(formatItalic(_:)): check(state.isItalic)
        case #selector(formatUnderline(_:)): check(state.isUnderlined)
        case #selector(formatStrikethrough(_:)): check(state.isStruckThrough)
        case #selector(toggleBulletList(_:)): check(state.listKind == .bullet)
        case #selector(toggleNumberList(_:)): check(state.listKind == .numbered)
        case #selector(setLineSpacingFromMenu(_:)):
            check(abs(state.lineHeightMultiple * 100 - CGFloat(item.tag)) < 1)
        case #selector(applyStyleFromMenu(_:)):
            check(state.styleID == item.representedObject as? String)
        case #selector(addTableRow(_:)):
            return state.isInTable
        case #selector(toggleRulerVisibility(_:)):
            item.title = scrollView.rulersVisible ? "Hide Ruler" : "Show Ruler"
        case #selector(toggleFormatBar(_:)):
            item.title = formatBar.isHidden ? "Show Ribbon" : "Hide Ribbon"
        case #selector(toggleStatusBar(_:)):
            item.title = statusBar.isHidden ? "Show Status Bar" : "Hide Status Bar"
        case #selector(zoomInDocument(_:)):
            return editor.zoom < EditorController.maxZoom - 0.001
        case #selector(zoomOutDocument(_:)):
            return editor.zoom > EditorController.minZoom + 0.001
        case #selector(performTextFinderAction(_:)):
            return editor.validateFindAction(item.tag)
        default:
            return validateDocumentMenuItem(item)
        }
        return true
    }
}

/// A fixed-height bar that collapses to zero height when hidden.
///
/// The SwiftUI content is laid out by frame, not by constraints: SwiftUI's
/// embedded AppKit controls add constraints that otherwise leak into the
/// window's layout and pulled the whole window down to its minimum width
/// (e.g. a full-screen window stayed 720 pt wide with black margins).
final class BarContainer: NSView {
    private var barHeight: CGFloat
    private var heightConstraint: NSLayoutConstraint!
    private let content: NSView
    private let separator: NSView
    private let separatorAtBottom: Bool

    init(height: CGFloat, content: NSView, separator: NSView, separatorAtBottom: Bool) {
        barHeight = height
        self.content = content
        self.separator = separator
        self.separatorAtBottom = separatorAtBottom
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: height))
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        for view in [content, separator] {
            view.translatesAutoresizingMaskIntoConstraints = true
            view.autoresizingMask = []
            addSubview(view)
        }
        heightConstraint = heightAnchor.constraint(equalToConstant: height)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHidden: Bool {
        didSet { heightConstraint.constant = isHidden ? 0 : barHeight }
    }

    /// Changes the bar's height (e.g. collapsing the ribbon to its tabs).
    func setBarHeight(_ height: CGFloat) {
        barHeight = height
        if !isHidden { heightConstraint.constant = height }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let contentHeight = max(bounds.height - 1, 0)
        // Not flipped: y = 0 is the bottom edge.
        if separatorAtBottom {
            separator.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            content.frame = NSRect(x: 0, y: 1, width: width, height: contentHeight)
        } else {
            separator.frame = NSRect(x: 0, y: contentHeight, width: width, height: 1)
            content.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)
        }
    }
}

extension NSLayoutConstraint {
    func withPriority(_ value: Float) -> NSLayoutConstraint {
        priority = NSLayoutConstraint.Priority(value)
        return self
    }
}
