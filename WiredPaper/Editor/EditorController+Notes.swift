import AppKit

struct NoteEntry: Identifiable, Equatable {
    let id: String
    let number: Int
    let isEndnote: Bool
    let text: String
    let location: Int?
}

/// Footnotes, endnotes, page thumbnails and page navigation.
extension EditorController {
    // MARK: Pages

    func scrollToPage(_ index: Int) {
        guard let pagesView, let frame = pagesView.frameOfPage(index) else { return }
        pagesView.scroll(NSPoint(x: frame.minX, y: max(frame.minY - 16, 0)))
        let range = engine.characterRange(onPage: index)
        if range.length > 0 {
            focusTextView()
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }

    /// A small image of a page as it looks on screen.
    func pageThumbnail(_ index: Int, width: CGFloat) -> NSImage? {
        guard let pagesView, index < pagesView.pages.count else { return nil }
        let page = pagesView.pages[index]
        guard let rep = page.bitmapImageRepForCachingDisplay(in: page.bounds) else { return nil }
        page.cacheDisplay(in: page.bounds, to: rep)
        let scale = width / page.bounds.width
        let size = NSSize(width: width, height: page.bounds.height * scale)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.size = size
        return image
    }

    // MARK: Footnotes & endnotes

    func noteEntries() -> [NoteEntry] {
        guard let document else { return [] }
        var locations: [String: Int] = [:]
        textStorage.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let object = DocumentObject.decode(value), object.kind == .footnote || object.kind == .endnote else { return }
            locations[object.id] = range.location
        }
        let numbers = layoutManager.noteNumbers
        return document.metadata.footnotes
            .map { NoteEntry(id: $0.id, number: numbers[$0.id] ?? 0, isEndnote: $0.isEndnote, text: $0.text.string, location: locations[$0.id]) }
            .sorted { ($0.isEndnote ? 1 : 0, $0.location ?? .max) < ($1.isEndnote ? 1 : 0, $1.location ?? .max) }
    }

    /// Inserts a reference mark at the insertion point and a new note.
    func insertNote(isEndnote: Bool, text: String = "") {
        guard let document else { return }
        let record = FootnoteRecord.make(NSAttributedString(string: text), isEndnote: isEndnote)
        let textView = self.textView
        var attributes = TextFormatter.baseAttributes(for: textView)
        attributes.removeValue(forKey: .wpRevision)
        let mark = ObjectFactory.string(for: .footnote(isEndnote: isEndnote, id: record.id), image: nil, attributes: attributes)
        let insertion = textView.selectedRange()
        document.undoManager?.beginUndoGrouping()
        document.updateMetadata(isEndnote ? "Insert Endnote" : "Insert Footnote") { $0.footnotes.append(record) }
        textView.setSelectedRange(NSRange(location: NSMaxRange(insertion), length: 0))
        TextFormatter.replaceSelection(in: textView, with: mark, actionName: isEndnote ? "Insert Endnote" : "Insert Footnote")
        document.undoManager?.endUndoGrouping()
        updateFields()
        if isEndnote { rebuildEndnotes() }
        sidebar.right = .notes
        sidebar.editingCommentID = record.id
    }

    func setNoteText(_ id: String, text: String) {
        guard let document else { return }
        let bodyFont = FontResolver.font(family: styleSheet.theme.bodyFont, size: 9)
        let rich = NSAttributedString(string: text, attributes: [.font: bodyFont])
        document.updateMetadata("Edit Note") { metadata in
            guard let index = metadata.footnotes.firstIndex(where: { $0.id == id }) else { return }
            let isEndnote = metadata.footnotes[index].isEndnote
            var updated = FootnoteRecord.make(rich, isEndnote: isEndnote)
            updated.id = id
            metadata.footnotes[index] = updated
        }
        if document.metadata.footnotes.first(where: { $0.id == id })?.isEndnote == true {
            rebuildEndnotes()
        }
    }

    func deleteNote(_ id: String) {
        guard let document else { return }
        var markRange: NSRange?
        textStorage.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            if DocumentObject.decode(value)?.id == id { markRange = range; stop.pointee = true }
        }
        let wasEndnote = document.metadata.footnotes.first { $0.id == id }?.isEndnote ?? false
        document.undoManager?.beginUndoGrouping()
        if let markRange {
            let textView = self.textView
            revisionTracker.applying {
                if textView.shouldChangeText(in: markRange, replacementString: "") {
                    textStorage.replaceCharacters(in: markRange, with: "")
                    textView.didChangeText()
                }
            }
        }
        document.updateMetadata("Delete Note") { $0.footnotes.removeAll { $0.id == id } }
        document.undoManager?.endUndoGrouping()
        updateFields()
        if wasEndnote { rebuildEndnotes() }
    }

    func goToNoteReference(_ id: String) {
        textStorage.enumerateAttribute(.wpObject, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            if DocumentObject.decode(value)?.id == id {
                reveal(range)
                stop.pointee = true
            }
        }
    }

    /// Endnotes are listed in a generated "Notes" section at the end of the document.
    func rebuildEndnotes() {
        guard let document else { return }
        let endnotes = noteEntries().filter(\.isEndnote)
        let generated = GeneratedContent.range(of: "endnotes", in: textStorage)
        let content = NSMutableAttributedString()
        if !endnotes.isEmpty {
            let sheet = styleSheet
            content.append(NSAttributedString(string: "\u{0C}", attributes: sheet.attributes(for: "normal")))
            content.append(NSAttributedString(string: "Notes\n", attributes: sheet.attributes(for: "heading1")))
            let records = Dictionary(document.metadata.footnotes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for entry in endnotes {
                var attributes = sheet.attributes(for: "normal")
                if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                    style.headIndent = 24
                    style.firstLineHeadIndent = 0
                    style.tabStops = [NSTextTab(textAlignment: .left, location: 24)]
                    attributes[.paragraphStyle] = style
                }
                let line = NSMutableAttributedString(string: PageNumberFormat.lowerRoman.format(entry.number) + ".\t", attributes: attributes)
                let body = NSMutableAttributedString(attributedString: records[entry.id]?.text ?? NSAttributedString(string: entry.text))
                body.addAttributes(attributes, range: NSRange(location: 0, length: body.length))
                line.append(body)
                line.append(NSAttributedString(string: "\n", attributes: attributes))
                content.append(line)
            }
        }
        GeneratedContent.replace(kind: "endnotes", existing: generated, with: content, atEnd: true, in: self)
    }
}

/// Regions of text generated by the app (table of contents, bibliography,
/// endnotes, index), marked with `.wpGenerated` so they can be rebuilt.
enum GeneratedContent {
    static func range(of kind: String, in storage: NSAttributedString) -> NSRange? {
        var result: NSRange?
        storage.enumerateAttribute(.wpGenerated, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value as? String == kind else { return }
            result = result.map { NSUnionRange($0, range) } ?? range
        }
        return result
    }

    /// Replaces an existing generated region, or inserts at the insertion point / document end.
    static func replace(kind: String, existing: NSRange?, with content: NSAttributedString, atEnd: Bool = false, in editor: EditorController) {
        let marked = NSMutableAttributedString(attributedString: content)
        if marked.length > 0 {
            marked.addAttribute(.wpGenerated, value: kind, range: NSRange(location: 0, length: marked.length))
        }
        let textView = editor.textView
        let storage = editor.textStorage
        var target: NSRange
        if let existing {
            target = existing
        } else if atEnd {
            target = NSRange(location: storage.length, length: 0)
        } else {
            let location = textView.selectedRange().location
            let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            target = NSRange(location: paragraph.location, length: 0)
        }
        if existing == nil && marked.length == 0 { return }
        editor.withProtectionBypassed {
            editor.revisionTracker.applying {
                guard textView.shouldChangeText(in: target, replacementString: marked.string) else { return }
                storage.replaceCharacters(in: target, with: marked)
                textView.didChangeText()
            }
        }
        textView.undoManager?.setActionName("Update")
        editor.updateFields()
    }
}
