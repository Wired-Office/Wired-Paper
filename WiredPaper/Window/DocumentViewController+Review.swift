import AppKit
import CryptoKit
import SwiftUI

/// Review (Track Changes, comments, protection), references and sidebar commands.
extension DocumentViewController {
    // MARK: Sidebars

    @objc func toggleNavigationPane(_ sender: Any?) { editor.sidebar.toggleLeft(.navigation) }
    @objc func showCommentsPane(_ sender: Any?) { editor.sidebar.toggleRight(.comments) }
    @objc func showReviewPane(_ sender: Any?) { editor.sidebar.toggleRight(.review) }
    @objc func showNotesPane(_ sender: Any?) { editor.sidebar.toggleRight(.notes) }
    @objc func showCitationsPane(_ sender: Any?) { editor.sidebar.toggleRight(.references) }

    @objc func showSearchResults(_ sender: Any?) {
        editor.sidebar.left = .navigation
        editor.sidebar.navigationTab = .results
        let selection = editor.textView.selectedRange()
        if selection.length > 0, selection.length < 200 {
            editor.sidebar.searchQuery = (editor.textStorage.string as NSString).substring(with: selection)
        }
    }

    // MARK: Track Changes

    @objc func toggleTrackChanges(_ sender: Any?) { editor.setTracking(!editor.isTrackingChanges) }

    @objc func setMarkupModeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = MarkupMode(rawValue: raw) else { return }
        editor.setMarkupMode(mode)
    }

    @objc func acceptChange(_ sender: Any?) { editor.acceptCurrentChange(true) }
    @objc func rejectChange(_ sender: Any?) { editor.acceptCurrentChange(false) }
    @objc func acceptAllChanges(_ sender: Any?) { editor.resolveAllChanges(accept: true) }
    @objc func rejectAllChanges(_ sender: Any?) { editor.resolveAllChanges(accept: false) }
    @objc func nextChange(_ sender: Any?) { editor.moveToChange(forward: true) }
    @objc func previousChange(_ sender: Any?) { editor.moveToChange(forward: false) }

    // MARK: Comments

    @objc func newComment(_ sender: Any?) { editor.addComment() }

    @objc func deleteCurrentComment(_ sender: Any?) {
        if let id = editor.activeCommentID { editor.deleteComment(id) } else { NSSound.beep() }
    }

    @objc func nextComment(_ sender: Any?) { moveComment(forward: true) }
    @objc func previousComment(_ sender: Any?) { moveComment(forward: false) }

    private func moveComment(forward: Bool) {
        let threads = editor.commentThreads()
        guard !threads.isEmpty else { NSSound.beep(); return }
        let location = editor.textView.selectedRange().location
        let target = forward
            ? threads.first { $0.location > location } ?? threads.first
            : threads.last { $0.location < location } ?? threads.last
        if let target {
            editor.sidebar.right = .comments
            editor.selectComment(target.thread.id)
        }
    }

    // MARK: Protection

    @objc func markAsFinal(_ sender: Any?) {
        document?.updateMetadata("Mark as Final") { $0.protection.markedFinal.toggle() }
        editor.protectionNotice = nil
    }

    @objc func editAnyway(_ sender: Any?) {
        document?.updateMetadata("Edit Anyway") { $0.protection.markedFinal = false }
        editor.protectionNotice = nil
    }

    @objc func showRestrictEditing(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let current = document.metadata.protection
        SheetPresenter.present(in: window) { dismiss in
            RestrictEditingSheet(current: current, onApply: { restriction, password in
                dismiss()
                document.updateMetadata("Restrict Editing") { metadata in
                    metadata.protection.restriction = restriction
                    if let password, !password.isEmpty {
                        let salt = UUID().uuidString
                        metadata.protection.salt = salt
                        metadata.protection.passwordHash = Self.hash(password, salt: salt)
                    } else if restriction == .none {
                        metadata.protection.salt = nil
                        metadata.protection.passwordHash = nil
                    }
                }
                self.editor.protectionNotice = nil
            }, onCancel: dismiss)
        }
    }

    @objc func stopProtection(_ sender: Any?) {
        guard let window = view.window, let document else { return }
        let protection = document.metadata.protection
        guard let hash = protection.passwordHash, let salt = protection.salt else {
            document.updateMetadata("Stop Protection") { $0.protection.restriction = .none }
            editor.protectionNotice = nil
            return
        }
        SheetPresenter.present(in: window) { dismiss in
            PasswordPromptSheet(title: "Stop Protection", message: "Enter the password to remove editing restrictions.", onSubmit: { password in
                guard Self.hash(password, salt: salt) == hash else { return false }
                dismiss()
                document.updateMetadata("Stop Protection") { metadata in
                    metadata.protection.restriction = .none
                    metadata.protection.passwordHash = nil
                    metadata.protection.salt = nil
                }
                self.editor.protectionNotice = nil
                return true
            }, onCancel: dismiss)
        }
    }

    static func hash(_ password: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + password).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: References

    @objc func insertFootnote(_ sender: Any?) { editor.insertNote(isEndnote: false) }
    @objc func insertEndnote(_ sender: Any?) { editor.insertNote(isEndnote: true) }
    @objc func insertTableOfContents(_ sender: Any?) { editor.insertTableOfContents() }
    @objc func updateTableOfContents(_ sender: Any?) { editor.updateAllTables() }
    @objc func insertBibliography(_ sender: Any?) { editor.insertBibliography() }
    @objc func insertIndex(_ sender: Any?) { editor.insertIndex() }

    @objc func setCitationStyleFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = CitationStyle(rawValue: raw) else { return }
        editor.setCitationStyle(style)
    }

    @objc func insertTableOfFiguresFromMenu(_ sender: NSMenuItem) {
        editor.insertTableOfFigures(label: sender.representedObject as? String ?? "Figure")
    }

    @objc func showCaptionSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            CaptionSheet(onInsert: { label, text in
                dismiss()
                editor.insertCaption(label: label, text: text)
            }, onCancel: dismiss)
        }
    }

    @objc func showCrossReferenceSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let targets = editor.crossReferenceTargets()
        SheetPresenter.present(in: window) { dismiss in
            CrossReferenceSheet(targets: targets, onInsert: { target, display, link in
                dismiss()
                editor.insertCrossReference(to: target, display: display, asLink: link)
            }, onCancel: dismiss)
        }
    }

    @objc func showBookmarkSheet(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        SheetPresenter.present(in: window) { dismiss in
            BookmarkSheet(existing: editor.bookmarkNames, onAdd: { name in
                dismiss()
                editor.addBookmark(named: name)
            }, onGoTo: { name in
                dismiss()
                editor.goToBookmark(named: name)
            }, onDelete: { name in
                dismiss()
                editor.removeBookmark(named: name)
            }, onCancel: dismiss)
        }
    }

    @objc func showMarkIndexEntry(_ sender: Any?) {
        guard let window = view.window else { return }
        let editor = self.editor
        let selection = editor.textView.selectedRange()
        let initial = selection.length > 0 && selection.length < 80 ? (editor.textStorage.string as NSString).substring(with: selection) : ""
        guard !initial.isEmpty else { NSSound.beep(); return }
        SheetPresenter.present(in: window) { dismiss in
            TextPromptSheet(title: "Mark Index Entry", label: "Entry (Main:Subentry)", primaryTitle: "Mark", onApply: { entry in
                dismiss()
                editor.markIndexEntry(entry)
            }, onCancel: dismiss, text: initial)
        }
    }
}

// MARK: - Sheets & banner

struct RestrictEditingSheet: View {
    let onApply: (EditingRestriction, String?) -> Void
    let onCancel: () -> Void
    @State private var restriction: EditingRestriction
    @State private var password = ""
    @State private var confirmation = ""

    init(current: ProtectionSettings, onApply: @escaping (EditingRestriction, String?) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _restriction = State(initialValue: current.restriction == .none ? .readOnly : current.restriction)
    }

    var body: some View {
        SheetScaffold(title: "Restrict Editing", primaryTitle: "Start Enforcing", primaryDisabled: password != confirmation, width: 420,
                      onPrimary: { onApply(restriction, password.isEmpty ? nil : password) }, onCancel: onCancel) {
            Form {
                Picker("Allow only", selection: $restriction) {
                    ForEach(EditingRestriction.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                SecureField("Password (optional)", text: $password)
                SecureField("Confirm password", text: $confirmation)
                Text("A password stops others from removing the restriction in Wired Paper. It does not encrypt the document — use File ▸ Encrypt with Password for that.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

struct PasswordPromptSheet: View {
    let title: String
    let message: String
    /// Returns false when the password is wrong.
    let onSubmit: (String) -> Bool
    let onCancel: () -> Void
    @State private var password = ""
    @State private var failed = false

    var body: some View {
        SheetScaffold(title: title, primaryTitle: "OK", primaryDisabled: password.isEmpty, width: 360, onPrimary: {
            failed = !onSubmit(password)
            if failed { password = "" }
        }, onCancel: onCancel) {
            Form {
                Text(message).font(.callout)
                SecureField("Password", text: $password)
                if failed { Text("Incorrect password.").foregroundStyle(.red).font(.caption) }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

/// Shown above the pages when the document is protected or marked final.
struct NoticeBar: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        let protection = editor.document?.metadata.protection ?? ProtectionSettings()
        HStack(spacing: 10) {
            Image(systemName: protection.markedFinal ? "checkmark.seal" : "lock")
                .foregroundStyle(Theme.accentColor)
            Text(message(protection))
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            if protection.markedFinal {
                Button("Edit Anyway") { NSApp.sendAction(#selector(DocumentViewController.editAnyway(_:)), to: nil, from: nil) }
            } else if protection.restriction != .none {
                Button("Stop Protection") { NSApp.sendAction(#selector(DocumentViewController.stopProtection(_:)), to: nil, from: nil) }
            }
            if editor.protectionNotice != nil {
                Button { editor.protectionNotice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.accentColor.opacity(0.1))
    }

    private func message(_ protection: ProtectionSettings) -> String {
        if let notice = editor.protectionNotice { return notice }
        if protection.markedFinal { return "Marked as Final — an author has marked this document as final to discourage editing." }
        switch protection.restriction {
        case .readOnly: return "This document is protected: read only."
        case .commentsOnly: return "This document is protected: you can add comments."
        case .trackedChanges: return "This document is protected: all changes are tracked."
        case .formsOnly: return "This document is protected: you can fill in form fields."
        case .none: return ""
        }
    }
}
