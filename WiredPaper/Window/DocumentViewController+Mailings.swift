import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Mailings, word count, accessibility and focus mode.
extension DocumentViewController {
    // MARK: Envelopes & labels

    @objc func showEnvelopes(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let selected = editor.textView.selectedRange()
        let delivery = selected.length > 0 ? (editor.textStorage.string as NSString).substring(with: selected) : ""
        SheetPresenter.present(in: window) { dismiss in
            EnvelopeSheet(delivery: delivery, returnAddress: AppSettings.shared.authorName, onCreate: { delivery, returnAddress, size in
                dismiss()
                let (text, setup) = MailingsBuilder.envelope(delivery: delivery, returnAddress: returnAddress, size: size)
                (NSDocumentController.shared as? WiredPaperDocumentController)?.newDocument(text: text, pageSetup: setup)
            }, onCancel: dismiss)
        }
    }

    @objc func showLabels(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let data = editor.mailMerge
        let selected = editor.textView.selectedRange()
        let initial = selected.length > 0 ? (editor.textStorage.string as NSString).substring(with: selected) : ""
        SheetPresenter.present(in: window) { dismiss in
            LabelsSheet(text: initial, hasRecipients: !data.records.isEmpty, onCreate: { text, layout, useRecipients in
                dismiss()
                let base = StyleCatalog.attributes(for: .normal)
                let texts: [NSAttributedString]
                if useRecipients {
                    let lines = data.addressFields
                    texts = data.includedIndices.map { index in
                        let record = data.record(index)
                        let address = lines.map { fields in fields.map { record[$0] ?? "" }.filter { !$0.isEmpty }.joined(separator: " ") }
                            .filter { !$0.isEmpty }
                        let fallback = data.headers.map { record[$0] ?? "" }.filter { !$0.isEmpty }
                        return NSAttributedString(string: (address.isEmpty ? fallback : address).joined(separator: "\n"), attributes: base)
                    }
                } else {
                    texts = Array(repeating: NSAttributedString(string: text, attributes: base), count: layout.rows * layout.columns)
                }
                let (content, setup) = MailingsBuilder.labels(texts: texts, layout: layout)
                (NSDocumentController.shared as? WiredPaperDocumentController)?.newDocument(text: content, pageSetup: setup)
            }, onCancel: dismiss)
        }
    }

    // MARK: Recipients

    @objc func selectRecipientsFromFile(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText, UTType(filenameExtension: "tsv") ?? .plainText]
        panel.message = "Choose a recipient list (CSV or tab-separated, with a header row)."
        panel.prompt = "Use List"
        let editor = self.editor
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try editor.loadRecipients(from: url)
            } catch {
                window.presentError(error)
            }
        }
    }

    @objc func editRecipients(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        var data = editor.mailMerge
        if data.isEmpty {
            data.headers = ["First Name", "Last Name", "Company", "Address", "City", "Postal Code", "Country", "Email"]
            data.records = [Array(repeating: "", count: data.headers.count)]
            data.sourceName = "Typed list"
        }
        SheetPresenter.present(in: window) { dismiss in
            RecipientsSheet(data: data, onSave: { updated in
                dismiss()
                editor.setMailMerge(updated)
            }, onCancel: dismiss)
        }
    }

    @objc func clearMailMerge(_ sender: Any?) {
        editor.previewMergeRecord(nil)
        editor.setMailMerge(nil)
    }

    // MARK: Finish & merge

    private func mergedDocument() -> WiredPaperDocument? {
        guard let text = editor.mergedDocumentText(), let document else {
            let alert = NSAlert()
            alert.messageText = "No recipients to merge"
            alert.informativeText = "Select or type a recipient list first (Mailings ▸ Select Recipients)."
            if let window = view.window { alert.beginSheetModal(for: window) }
            return nil
        }
        return (NSDocumentController.shared as? WiredPaperDocumentController)?.newDocument(text: text, pageSetup: document.pageSetup, metadata: editor.generatedMetadata)
    }

    @objc func finishMergeEditDocuments(_ sender: Any?) {
        _ = mergedDocument()
    }

    @objc func finishMergePrint(_ sender: Any?) {
        mergedDocument()?.printDocument(nil)
    }

    @objc func finishMergePDF(_ sender: Any?) {
        mergedDocument()?.saveToPDF(nil)
    }

    // MARK: Review helpers

    @objc func showWordCount(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            WordCountSheet(statistics: editor.statistics, selection: editor.selectionStatistics, pages: editor.pageCount, onClose: dismiss)
        }
    }

    @objc func checkAccessibility(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let issues = editor.checkAccessibility()
        SheetPresenter.present(in: window) { dismiss in
            AccessibilitySheet(issues: issues, onSelect: { issue in
                dismiss()
                if let range = issue.range { editor.reveal(range) }
            }, onClose: dismiss)
        }
    }

    @objc func lookUpSelection(_ sender: Any?) { editor.lookUpSelection() }

    // MARK: Focus mode

    /// Hides the ribbon, ruler, status bar and panes (and enters full screen).
    @objc func toggleFocusMode(_ sender: Any?) {
        if let saved = focusModeState {
            formatBar.isHidden = !saved.ribbon
            statusBar.isHidden = !saved.status
            setRulerVisible(saved.ruler)
            if saved.enteredFullScreen, view.window?.styleMask.contains(.fullScreen) == true { view.window?.toggleFullScreen(nil) }
            focusModeState = nil
        } else {
            let fullScreen = view.window?.styleMask.contains(.fullScreen) == true
            focusModeState = FocusModeState(ribbon: !formatBar.isHidden, status: !statusBar.isHidden, ruler: scrollView.rulersVisible,
                                            enteredFullScreen: !fullScreen)
            formatBar.isHidden = true
            statusBar.isHidden = true
            setRulerVisible(false)
            editor.sidebar.left = nil
            editor.sidebar.right = nil
            if !fullScreen { view.window?.toggleFullScreen(nil) }
        }
        editor.focusTextView()
    }

    var isInFocusMode: Bool { focusModeState != nil }

    // MARK: Menu equivalents of ribbon commands

    @objc func toggleRibbonCollapsed(_ sender: Any?) { ribbon.isCollapsed.toggle() }
    @objc func toggleFormattingMarks(_ sender: Any?) { editor.toggleFormattingMarks() }
    @objc func showStylesPane(_ sender: Any?) { editor.sidebar.toggleRight(.styles) }
    @objc func showEditorPane(_ sender: Any?) { editor.sidebar.toggleRight(.editor) }
    @objc func insertAddressBlock(_ sender: Any?) { editor.insertAddressBlock() }
    @objc func insertGreetingLine(_ sender: Any?) { editor.insertGreetingLine() }
    @objc func toggleMergePreview(_ sender: Any?) { editor.previewMergeRecord(editor.mergePreviewIndex == nil ? 0 : nil) }

    // MARK: Editing mode (title bar)

    var documentMode: DocumentMode {
        if editor.isViewing { return .viewing }
        return editor.isTrackingChanges ? .reviewing : .editing
    }

    @objc func setDocumentModeFromMenu(_ sender: NSMenuItem) {
        guard let mode = DocumentMode(rawValue: sender.tag) else { return }
        setDocumentMode(mode)
    }

    func setDocumentMode(_ mode: DocumentMode) {
        switch mode {
        case .editing:
            editor.isViewing = false
            if editor.isTrackingChanges { editor.setTracking(false) }
        case .reviewing:
            editor.isViewing = false
            if !editor.isTrackingChanges { editor.setTracking(true) }
        case .viewing:
            editor.isViewing = true
        }
        editor.protectionNotice = mode == .viewing ? "Viewing — the document can't be changed. Choose Editing in the title bar to edit." : nil
        onModeChange?(documentMode)
    }
}

struct FocusModeState {
    let ribbon: Bool
    let status: Bool
    let ruler: Bool
    let enteredFullScreen: Bool
}
