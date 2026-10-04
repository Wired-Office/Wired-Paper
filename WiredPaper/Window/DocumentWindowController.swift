import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let contentController: DocumentViewController
    private let toolbarController = DocumentToolbarController()

    var editor: EditorController { contentController.editor }

    init(document: WiredPaperDocument) {
        contentController = DocumentViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentController
        window.setContentSize(NSSize(width: 1120, height: 820))
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.tabbingIdentifier = "com.wiredpaper.document-window"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = true
        window.backgroundColor = Theme.barBackground

        super.init(window: window)
        window.delegate = self
        toolbarController.contentController = contentController
        window.toolbar = toolbarController.makeToolbar()
        window.titleVisibility = .hidden
        contentController.onModeChange = { [weak self] mode in self?.toolbarController.updateMode(mode) }
        shouldCascadeWindows = true
        window.center()
        lockContentSize(window.contentLayoutRect.size)
    }

    // MARK: - Initial size

    /// AppKit's first constraint pass resizes a new window to its fitting (minimum)
    /// size. Hold the intended size with required constraints until that pass has
    /// run, then release them so the window resizes freely.
    private var sizeLock: [NSLayoutConstraint] = []

    private func lockContentSize(_ size: NSSize) {
        NSLayoutConstraint.deactivate(sizeLock)
        guard let content = window?.contentView else { return }
        sizeLock = [
            content.widthAnchor.constraint(equalToConstant: size.width),
            content.heightAnchor.constraint(equalToConstant: size.height),
        ]
        NSLayoutConstraint.activate(sizeLock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.releaseSizeLock() }
    }

    private func releaseSizeLock() {
        guard !sizeLock.isEmpty else { return }
        NSLayoutConstraint.deactivate(sizeLock)
        sizeLock = []
        fillScreenIfFullScreen()
    }

    /// A full-screen window whose size was held while it entered full screen
    /// doesn't grow afterwards on its own; size it to the screen explicitly.
    private func fillScreenIfFullScreen() {
        guard let window, window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
        if window.frame.size != screen.frame.size {
            window.setFrame(screen.frame, display: true)
        }
    }

    // MARK: - Full screen

    func windowWillEnterFullScreen(_ notification: Notification) {
        // The size lock must never constrain the full-screen size.
        releaseSizeLock()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        fillScreenIfFullScreen()
    }

    func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
        releaseSizeLock()
        return proposedSize
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // The first display cycle has now been scheduled; release right after it.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { self?.releaseSizeLock() }
        }
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        // Keep a restored window at its restored size (full-screen windows size to the screen).
        if !sizeLock.isEmpty && !window.styleMask.contains(.fullScreen) && !state.decodeBool(forKey: "NSIsFullScreen") {
            lockContentSize(window.contentLayoutRect.size)
        } else {
            releaseSizeLock()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var document: AnyObject? {
        didSet { updateStatusSubtitle() }
    }

    /// Shows the document's format and save state under the title.
    func updateStatusSubtitle() {
        guard let window, let document = document as? WiredPaperDocument else { return }
        var parts: [String] = []
        if let format = document.format, !format.isNative {
            parts.append(format.shortName)
        }
        // AppKit appends "— Edited" itself while there are unsaved changes.
        if document.fileURL == nil {
            parts.append("Not saved")
        } else if !document.isDocumentEdited {
            parts.append("Saved")
        }
        window.subtitle = parts.joined(separator: " · ")
        var status = parts
        if document.isDocumentEdited && document.fileURL != nil { status.append("Edited") }
        toolbarController.updateTitle(document.displayName, subtitle: status.joined(separator: " · "))
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? NSDocument)?.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        editor.tearDown()
    }
}
