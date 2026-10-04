import AppKit

/// Track Changes, comments and editing restrictions.
extension EditorController {
    // MARK: Track Changes

    var isTrackingChanges: Bool {
        guard let metadata = document?.metadata else { return false }
        return metadata.tracking.isTracking || metadata.protection.restriction == .trackedChanges
    }

    var markupMode: MarkupMode { document?.metadata.tracking.markupMode ?? .all }

    func setTracking(_ on: Bool) {
        document?.updateMetadata(on ? "Track Changes On" : "Track Changes Off") { $0.tracking.isTracking = on }
        objectWillChange.send()
    }

    func setMarkupMode(_ mode: MarkupMode) {
        document?.updateMetadata("Markup") { $0.tracking.markupMode = mode }
        objectWillChange.send()
    }

    func revisionEntries() -> [RevisionEntry] {
        revisionTracker.entries()
    }

    func acceptCurrentChange(_ accept: Bool) {
        let selection = textView.selectedRange()
        let probe = selection.length > 0 ? selection : NSRange(location: max(selection.location - (selection.location == textStorage.length ? 1 : 0), 0), length: max(min(1, textStorage.length - selection.location), 0))
        var ids = Set<String>()
        if probe.length > 0, NSMaxRange(probe) <= textStorage.length {
            textStorage.enumerateAttribute(.wpRevision, in: probe) { value, _, _ in
                if let (_, id) = RevisionMarkup.parse(value) { ids.insert(id) }
            }
        }
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        revisionTracker.resolve(accept: accept, ids: ids)
        moveToChange(forward: true)
        refreshState()
    }

    func resolveRevision(_ entry: RevisionEntry, accept: Bool) {
        revisionTracker.resolve(accept: accept, ids: [entry.id], within: entry.range)
        refreshState()
        objectWillChange.send()
    }

    func resolveAllChanges(accept: Bool, author: String? = nil) {
        if let author {
            let ids = Set(document?.metadata.revisions.filter { $0.author == author }.map(\.id) ?? [])
            revisionTracker.resolve(accept: accept, ids: ids)
        } else {
            revisionTracker.resolve(accept: accept)
        }
        refreshState()
        objectWillChange.send()
    }

    func moveToChange(forward: Bool) {
        guard let range = revisionTracker.adjacentChange(forward: forward) else {
            NSSound.beep()
            return
        }
        reveal(range)
    }

    // MARK: Comments

    /// Comment threads in document order with their anchor text.
    func commentThreads(includeResolved: Bool = true) -> [(thread: CommentThread, anchor: String, location: Int)] {
        guard let document else { return [] }
        let order = CommentPrinter.anchorOrder(in: textStorage)
        return document.metadata.comments
            .filter { includeResolved || !$0.resolved }
            .map { ($0, CommentPrinter.anchorText(for: $0.id, in: textStorage), order[$0.id] ?? Int.max) }
            .sorted { $0.location < $1.location }
    }

    /// Adds a comment on the selection (or the word at the insertion point).
    @discardableResult
    func addComment(text: String = "") -> String? {
        guard let document else { return nil }
        let textView = self.textView
        var range = textView.selectedRange()
        if range.length == 0 {
            range = (textStorage.string as NSString).rangeOfWord(at: range.location)
        }
        guard range.length > 0 else {
            NSSound.beep()
            return nil
        }
        let thread = CommentThread(author: AppSettings.shared.authorName, text: text)
        document.undoManager?.beginUndoGrouping()
        withProtectionBypassed {
            revisionTracker.applying {
                if textView.shouldChangeText(in: range, replacementString: nil) {
                    textStorage.enumerateAttribute(.wpComment, in: range) { value, run, _ in
                        let ids = (value as? String).map { $0 + " " + thread.id } ?? thread.id
                        textStorage.addAttribute(.wpComment, value: ids, range: run)
                    }
                    textView.didChangeText()
                }
            }
        }
        document.updateMetadata("Add Comment") { $0.comments.append(thread) }
        document.undoManager?.endUndoGrouping()
        document.undoManager?.setActionName("New Comment")
        sidebar.right = .comments
        sidebar.editingCommentID = thread.id
        setActiveComment(thread.id)
        return thread.id
    }

    func updateComment(_ id: String, _ change: @escaping (inout CommentThread) -> Void, actionName: String) {
        document?.updateMetadata(actionName) { metadata in
            guard let index = metadata.comments.firstIndex(where: { $0.id == id }) else { return }
            change(&metadata.comments[index])
        }
    }

    func setCommentText(_ id: String, text: String) {
        updateComment(id, { $0.text = text }, actionName: "Edit Comment")
    }

    func replyToComment(_ id: String, text: String) {
        let reply = CommentReply(author: AppSettings.shared.authorName, text: text)
        updateComment(id, { $0.replies.append(reply) }, actionName: "Reply")
    }

    func toggleCommentResolved(_ id: String) {
        updateComment(id, { $0.resolved.toggle() }, actionName: "Resolve Comment")
    }

    func toggleReaction(_ emoji: String, on id: String) {
        let me = AppSettings.shared.authorName
        updateComment(id, { thread in
            var people = thread.reactions[emoji] ?? []
            if let index = people.firstIndex(of: me) { people.remove(at: index) } else { people.append(me) }
            thread.reactions[emoji] = people.isEmpty ? nil : people
        }, actionName: "Reaction")
    }

    func deleteComment(_ id: String) {
        guard let document else { return }
        document.undoManager?.beginUndoGrouping()
        removeCommentAnchors(ids: [id])
        document.updateMetadata("Delete Comment") { $0.comments.removeAll { $0.id == id } }
        document.undoManager?.endUndoGrouping()
        document.undoManager?.setActionName("Delete Comment")
        if activeCommentID == id { setActiveComment(nil) }
    }

    func deleteAllComments(resolvedOnly: Bool = false) {
        guard let document else { return }
        let ids = Set(document.metadata.comments.filter { !resolvedOnly || $0.resolved }.map(\.id))
        guard !ids.isEmpty else { return }
        document.undoManager?.beginUndoGrouping()
        removeCommentAnchors(ids: ids)
        document.updateMetadata("Delete Comments") { $0.comments.removeAll { ids.contains($0.id) } }
        document.undoManager?.endUndoGrouping()
    }

    private func removeCommentAnchors(ids: Set<String>) {
        var changes: [(NSRange, String?)] = []
        textStorage.enumerateAttribute(.wpComment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let current = value as? String else { return }
            let remaining = current.split(separator: " ").map(String.init).filter { !ids.contains($0) }
            if remaining.count != current.split(separator: " ").count {
                changes.append((range, remaining.isEmpty ? nil : remaining.joined(separator: " ")))
            }
        }
        guard !changes.isEmpty else { return }
        let textView = self.textView
        withProtectionBypassed {
            revisionTracker.applying {
                guard textView.shouldChangeText(inRanges: changes.map { NSValue(range: $0.0) }, replacementStrings: nil) else { return }
                for (range, value) in changes {
                    if let value { textStorage.addAttribute(.wpComment, value: value, range: range) } else { textStorage.removeAttribute(.wpComment, range: range) }
                }
                textView.didChangeText()
            }
        }
        refreshMarkup()
    }

    func selectComment(_ id: String) {
        setActiveComment(id)
        if let range = CommentPrinter.anchorRange(for: id, in: textStorage) {
            reveal(range)
        }
    }

    /// Everyone who has commented or tracked changes, for @mentions and filters.
    var knownAuthors: [String] {
        guard let metadata = document?.metadata else { return [AppSettings.shared.authorName] }
        var names = [AppSettings.shared.authorName]
        for thread in metadata.comments {
            names.append(thread.author)
            names.append(contentsOf: thread.replies.map(\.author))
        }
        names.append(contentsOf: metadata.revisions.map(\.author))
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: Editing restrictions

    func withProtectionBypassed(_ body: () -> Void) {
        let previous = bypassProtection
        bypassProtection = true
        body()
        bypassProtection = previous
    }

    /// Whether the document's protection allows changing `range`.
    func allowsEdit(in range: NSRange) -> Bool {
        if isViewing && !bypassProtection {
            protectionNotice = "You're viewing this document. Switch to Editing (title bar) to make changes."
            NSSound.beep()
            return false
        }
        guard !bypassProtection, let protection = document?.metadata.protection else { return true }
        if protection.markedFinal {
            protectionNotice = "This document is marked as final. Choose Review ▸ Edit Anyway to make changes."
            NSSound.beep()
            return false
        }
        switch protection.restriction {
        case .none, .trackedChanges:
            return true
        case .readOnly:
            protectionNotice = "This document is read-only."
            NSSound.beep()
            return false
        case .commentsOnly:
            protectionNotice = "Only comments can be added to this document."
            NSSound.beep()
            return false
        case .formsOnly:
            if isInsideFormField(range) { return true }
            protectionNotice = "Only form fields can be filled in."
            NSSound.beep()
            return false
        }
    }

    func isInsideFormField(_ range: NSRange) -> Bool {
        guard textStorage.length > 0 else { return false }
        let start = min(max(range.location, 0), textStorage.length - 1)
        var effective = NSRange()
        guard textStorage.attribute(.wpFormField, at: start, longestEffectiveRange: &effective, in: NSRange(location: 0, length: textStorage.length)) != nil
                || (range.location > 0 && textStorage.attribute(.wpFormField, at: range.location - 1, longestEffectiveRange: &effective, in: NSRange(location: 0, length: textStorage.length)) != nil)
        else { return false }
        return range.location >= effective.location && NSMaxRange(range) <= NSMaxRange(effective) + 1
    }
}
