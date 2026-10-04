import AppKit

/// A tracked change as shown in the Review pane.
struct RevisionEntry: Identifiable, Equatable {
    let id: String
    let kind: RevisionKind
    let author: String
    let date: Date
    let range: NSRange
    let excerpt: String
}

/// Records edits as tracked changes while Track Changes is on.
///
/// All user edits reach NSTextView's `shouldChangeText`. When tracking, the
/// page text view forwards them here instead: deletions are kept in the text
/// and marked `del:<id>`, insertions are marked `ins:<id>`. Deleting your own
/// tracked insertion really deletes it, as in other word processors.
final class RevisionTracker {
    private unowned let editor: EditorController
    /// True while applying our own edits (marking, accepting, rejecting).
    private(set) var isApplying = false
    /// Range inserted by the current edit, marked after the storage processes it.
    var pendingInsertion: (range: NSRange, id: String)?

    init(editor: EditorController) {
        self.editor = editor
    }

    private var document: WiredPaperDocument? { editor.document }
    private var author: String { AppSettings.shared.authorName }

    /// Performs `body` without tracking (for internal edits).
    func applying(_ body: () -> Void) {
        let previous = isApplying
        isApplying = true
        body()
        isApplying = previous
    }

    // MARK: Recording

    private func revisionID(kind: RevisionKind, adjacentTo location: Int, author: String) -> String {
        let storage = editor.textStorage
        let prefix = kind == .insertion ? "ins:" : "del:"
        // Continue an adjacent revision by the same author so a typed word is one change.
        for probe in [location - 1, location] where probe >= 0 && probe < storage.length {
            if let value = storage.attribute(.wpRevision, at: probe, effectiveRange: nil) as? String, value.hasPrefix(prefix) {
                let id = String(value.dropFirst(4))
                if document?.metadata.revisions.first(where: { $0.id == id })?.author == author { return id }
            }
        }
        let record = RevisionRecord(kind: kind, author: author)
        document?.setMetadataSilently { $0.revisions.append(record) }
        return record.id
    }

    private func isOwnInsertion(_ value: Any?) -> Bool {
        guard let (kind, id) = RevisionMarkup.parse(value), kind == .insertion else { return false }
        return document?.metadata.revisions.first(where: { $0.id == id })?.author == author
    }

    /// Handles one edit while tracking. Returns true to let NSTextView perform
    /// it normally (a plain insertion, marked afterwards), false when handled here.
    func handleEdit(in range: NSRange, replacement: String, textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()

        if range.length == 0 {
            guard !replacement.isEmpty else { return false }
            let id = revisionID(kind: .insertion, adjacentTo: range.location, author: author)
            pendingInsertion = (NSRange(location: range.location, length: (replacement as NSString).length), id)
            return true
        }

        textView.breakUndoCoalescing()
        let isBackward = selection.length == 0 && NSMaxRange(range) == selection.location
        let deletionID = revisionID(kind: .deletion, adjacentTo: range.location, author: author)

        // Walk the range from the end: remove own insertions, mark the rest deleted.
        var runs: [(NSRange, Bool)] = []
        storage.enumerateAttribute(.wpRevision, in: range) { value, run, _ in
            runs.append((run, isOwnInsertion(value)))
        }
        var removed = 0
        applying {
            for (run, own) in runs.reversed() {
                if own {
                    if textView.shouldChangeText(in: run, replacementString: "") {
                        storage.replaceCharacters(in: run, with: "")
                        textView.didChangeText()
                        removed += run.length
                    }
                } else if textView.shouldChangeText(in: run, replacementString: nil) {
                    storage.enumerateAttribute(.wpRevision, in: run) { value, sub, _ in
                        // Already-deleted text stays as it is.
                        if (value as? String)?.hasPrefix("del:") == true { return }
                        storage.addAttribute(.wpRevision, value: "del:" + deletionID, range: sub)
                    }
                    textView.didChangeText()
                }
            }
        }

        let end = NSMaxRange(range) - removed
        if replacement.isEmpty {
            textView.setSelectedRange(NSRange(location: isBackward ? range.location : end, length: 0))
        } else {
            // Typed over a selection: insert the new text after the deleted text.
            let insertionID = revisionID(kind: .insertion, adjacentTo: end, author: author)
            var attributes = textView.typingAttributes
            attributes[.wpRevision] = "ins:" + insertionID
            let inserted = NSAttributedString(string: replacement, attributes: attributes)
            applying {
                let target = NSRange(location: end, length: 0)
                if textView.shouldChangeText(in: target, replacementString: replacement) {
                    storage.replaceCharacters(in: target, with: inserted)
                    textView.didChangeText()
                }
            }
            textView.setSelectedRange(NSRange(location: end + inserted.length, length: 0))
        }
        textView.undoManager?.setActionName(replacement.isEmpty ? "Tracked Deletion" : "Tracked Replacement")
        return false
    }

    /// Marks text inserted by a normal (non-typing) insertion, e.g. paste.
    func markPendingInsertion(in storage: NSTextStorage) {
        guard let pending = pendingInsertion else { return }
        pendingInsertion = nil
        let range = NSIntersectionRange(pending.range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        storage.addAttribute(.wpRevision, value: "ins:" + pending.id, range: range)
    }

    // MARK: Review

    func entries() -> [RevisionEntry] {
        let storage = editor.textStorage
        let records = Dictionary((document?.metadata.revisions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [RevisionEntry] = []
        storage.enumerateAttribute(.wpRevision, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let (kind, id) = RevisionMarkup.parse(value) else { return }
            let record = records[id]
            let text = (storage.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\u{FFFC}", with: "▢")
                .replacingOccurrences(of: "\n", with: "¶ ")
            if let last = entries.last, last.id == id, NSMaxRange(last.range) == range.location {
                entries[entries.count - 1] = RevisionEntry(id: id, kind: kind, author: last.author, date: last.date,
                                                           range: NSUnionRange(last.range, range), excerpt: String((last.excerpt + text).prefix(140)))
            } else {
                entries.append(RevisionEntry(id: id, kind: kind, author: record?.author ?? "Unknown", date: record?.date ?? Date(),
                                             range: range, excerpt: String(text.prefix(140))))
            }
        }
        return entries
    }

    /// Accepts or rejects the given revisions (all when `ids` is nil), optionally limited to a range.
    func resolve(accept: Bool, ids: Set<String>? = nil, within limit: NSRange? = nil) {
        let textView = editor.textView
        let storage = editor.textStorage
        let full = NSRange(location: 0, length: storage.length)
        let scope = limit.map { NSIntersectionRange($0, full) } ?? full
        var targets: [(NSRange, RevisionKind)] = []
        storage.enumerateAttribute(.wpRevision, in: scope) { value, run, _ in
            guard let (kind, id) = RevisionMarkup.parse(value), ids?.contains(id) ?? true else { return }
            targets.append((run, kind))
        }
        guard !targets.isEmpty else { return }

        document?.undoManager?.beginUndoGrouping()
        applying {
            for (run, kind) in targets.reversed() {
                let removeText = (accept && kind == .deletion) || (!accept && kind == .insertion)
                if removeText {
                    if textView.shouldChangeText(in: run, replacementString: "") {
                        storage.replaceCharacters(in: run, with: "")
                        textView.didChangeText()
                    }
                } else if textView.shouldChangeText(in: run, replacementString: nil) {
                    storage.removeAttribute(.wpRevision, range: run)
                    textView.didChangeText()
                }
            }
        }
        pruneRecords()
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(accept ? "Accept Changes" : "Reject Changes")
        editor.refreshMarkup()
    }

    /// Drops records no longer referenced by any text.
    func pruneRecords() {
        let storage = editor.textStorage
        var used = Set<String>()
        storage.enumerateAttribute(.wpRevision, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let (_, id) = RevisionMarkup.parse(value) { used.insert(id) }
        }
        guard let document, document.metadata.revisions.contains(where: { !used.contains($0.id) }) else { return }
        document.updateMetadata("Review") { $0.revisions.removeAll { !used.contains($0.id) } }
    }

    /// The next (or previous) change after the selection.
    func adjacentChange(forward: Bool) -> NSRange? {
        let location = editor.textView.selectedRange()
        let changes = entries().map(\.range)
        if forward {
            return changes.first { $0.location >= NSMaxRange(location) && $0 != location } ?? changes.first
        }
        return changes.last { NSMaxRange($0) <= location.location && $0 != location } ?? changes.last
    }
}
