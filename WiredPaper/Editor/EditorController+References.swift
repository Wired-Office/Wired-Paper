import AppKit

/// Citations, bibliography, table of contents, captions, table of figures,
/// cross-references, bookmarks and the index.
extension EditorController {
    static let bookmarkLinkScheme = "wp-bookmark"

    // MARK: Sources & citations

    var citationStyle: CitationStyle { document?.metadata.citationStyle ?? .apa }

    func saveSource(_ source: CitationSource) {
        document?.updateMetadata("Edit Source") { metadata in
            if let index = metadata.sources.firstIndex(where: { $0.id == source.id }) {
                metadata.sources[index] = source
            } else {
                metadata.sources.append(source)
            }
        }
        refreshCitations()
    }

    func deleteSource(_ id: String) {
        document?.updateMetadata("Delete Source") { $0.sources.removeAll { $0.id == id } }
        refreshCitations()
    }

    func setCitationStyle(_ style: CitationStyle) {
        document?.updateMetadata("Citation Style") { $0.citationStyle = style }
        refreshCitations()
        if GeneratedContent.range(of: "bibliography", in: textStorage) != nil { insertBibliography() }
    }

    /// IEEE numbers sources by first citation in the text.
    func citationNumbers() -> [String: Int] {
        var numbers: [String: Int] = [:]
        textStorage.enumerateAttribute(.wpCitation, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            for id in (value as? String ?? "").split(separator: ",").map(String.init) where numbers[id] == nil {
                numbers[id] = numbers.count + 1
            }
        }
        return numbers
    }

    func insertCitation(sourceIDs: [String]) {
        guard let document, !sourceIDs.isEmpty else { return }
        let sources = sourceIDs.compactMap { id in document.metadata.sources.first { $0.id == id } }
        guard !sources.isEmpty else { return }
        let textView = self.textView
        var attributes = TextFormatter.baseAttributes(for: textView)
        attributes[.wpCitation] = sourceIDs.joined(separator: ",")
        // IEEE numbers depend on position; insert, then refresh everything.
        let text = CitationFormatter.inText(sources, style: citationStyle, numbers: citationNumbers())
        let needsSpace = textView.selectedRange().location > 0
            && !(textStorage.string as NSString).substring(with: NSRange(location: textView.selectedRange().location - 1, length: 1)).trimmingCharacters(in: .whitespaces).isEmpty
        let content = NSMutableAttributedString()
        if needsSpace && citationStyle != .ieee {
            content.append(NSAttributedString(string: " ", attributes: TextFormatter.baseAttributes(for: textView)))
        }
        content.append(NSAttributedString(string: text, attributes: attributes))
        TextFormatter.replaceSelection(in: textView, with: content, actionName: "Insert Citation")
        refreshCitations()
    }

    /// Rewrites every citation for the current style and numbering.
    func refreshCitations() {
        guard let document else { return }
        let sources = Dictionary(document.metadata.sources.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let numbers = citationNumbers()
        var changes: [(NSRange, String)] = []
        textStorage.enumerateAttribute(.wpCitation, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let ids = value as? String else { return }
            let cited = ids.split(separator: ",").compactMap { sources[String($0)] }
            let text = cited.isEmpty ? "[source removed]" : CitationFormatter.inText(cited, style: citationStyle, numbers: numbers)
            if (textStorage.string as NSString).substring(with: range) != text { changes.append((range, text)) }
        }
        guard !changes.isEmpty else { return }
        let textView = self.textView
        withProtectionBypassed {
            revisionTracker.applying {
                guard textView.shouldChangeText(inRanges: changes.map { NSValue(range: $0.0) }, replacementStrings: changes.map(\.1)) else { return }
                textStorage.beginEditing()
                for (range, text) in changes.reversed() {
                    let attributes = textStorage.attributes(at: range.location, effectiveRange: nil)
                    textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
                }
                textStorage.endEditing()
                textView.didChangeText()
            }
        }
    }

    /// Inserts (or updates) the reference list.
    func insertBibliography() {
        guard let document else { return }
        let numbers = citationNumbers()
        let cited = Set(numbers.keys)
        let pool = document.metadata.sources.filter { citationStyle == .ieee ? cited.contains($0.id) : true }
        let sources = CitationFormatter.sorted(pool.isEmpty ? document.metadata.sources : pool, style: citationStyle, numbers: numbers)
        let sheet = styleSheet
        let content = NSMutableAttributedString()
        let heading = citationStyle == .mla ? "Works Cited" : "References"
        content.append(NSAttributedString(string: heading + "\n", attributes: sheet.attributes(for: "heading1")))
        var entryAttributes = sheet.attributes(for: "normal")
        if let style = (entryAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            // Hanging indent (numbered indent for IEEE).
            style.headIndent = 36
            style.firstLineHeadIndent = citationStyle == .ieee ? 0 : 0
            if citationStyle == .ieee { style.tabStops = [NSTextTab(textAlignment: .left, location: 36)] } else { style.firstLineHeadIndent = 0; style.headIndent = 36 }
            entryAttributes[.paragraphStyle] = style
        }
        for (index, source) in sources.enumerated() {
            content.append(CitationFormatter.attributedEntry(source, style: citationStyle, number: numbers[source.id] ?? index + 1, attributes: entryAttributes))
            content.append(NSAttributedString(string: "\n", attributes: entryAttributes))
        }
        GeneratedContent.replace(kind: "bibliography", existing: GeneratedContent.range(of: "bibliography", in: textStorage), with: content, in: self)
    }

    // MARK: Table of contents

    /// Inserts or rebuilds the table of contents with dot leaders, page numbers and links.
    func insertTableOfContents(maxLevel: Int = 3) {
        guard document != nil else { return }
        ensureHeadingBookmarks()
        // Page numbers need up-to-date layout.
        if let last = layoutManager.textContainers.last { layoutManager.ensureLayout(for: last) }
        let headings = computeOutline().filter { $0.level >= 1 && $0.level <= maxLevel && !isGenerated($0.range.location) }
        let sheet = styleSheet
        let content = NSMutableAttributedString()
        content.append(NSAttributedString(string: "Contents\n", attributes: sheet.attributes(for: "heading1").merging([.wpParaFlags: ""]) { _, new in new }))
        let width = geometry.columnWidth
        for heading in headings {
            var attributes = sheet.attributes(for: "normal")
            if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                let indent = CGFloat(heading.level - 1) * 18
                style.headIndent = indent
                style.firstLineHeadIndent = indent
                style.tailIndent = 0
                style.paragraphSpacing = heading.level == 1 ? 4 : 2
                style.tabStops = [NSTextTab(textAlignment: .right, location: width - 12)]
                attributes[.paragraphStyle] = style
            }
            if heading.level == 1, let font = attributes[.font] as? NSFont {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            attributes[.wpTabLeader] = "dot"
            let bookmark = textStorage.attribute(.wpBookmark, at: heading.range.location, effectiveRange: nil) as? String ?? ""
            var linkAttributes = attributes
            if let url = URL(string: "\(Self.bookmarkLinkScheme):\(bookmark)") { linkAttributes[.link] = url }
            content.append(NSAttributedString(string: heading.title, attributes: linkAttributes))
            content.append(NSAttributedString(string: "\t\(heading.page)\n", attributes: attributes))
        }
        if headings.isEmpty {
            content.append(NSAttributedString(string: "No headings found. Apply Heading styles, then update the table.\n", attributes: sheet.attributes(for: "normal")))
        }
        let existing = GeneratedContent.range(of: "toc", in: textStorage)
        GeneratedContent.replace(kind: "toc", existing: existing, with: content, in: self)
        // Inserting the table can shift pages; refresh numbers once more.
        if existing == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.updateTableOfContentsPageNumbers() }
        }
    }

    /// Updates only the page numbers of an existing table of contents.
    func updateTableOfContentsPageNumbers() {
        guard GeneratedContent.range(of: "toc", in: textStorage) != nil else { return }
        insertTableOfContents()
    }

    func isGenerated(_ location: Int) -> Bool {
        location < textStorage.length && textStorage.attribute(.wpGenerated, at: location, effectiveRange: nil) != nil
    }

    /// Gives every heading a hidden bookmark (`_Toc…`) that TOC links can target.
    private func ensureHeadingBookmarks() {
        var changes: [(NSRange, String)] = []
        for heading in computeOutline() where heading.level >= 1 && !isGenerated(heading.range.location) {
            if textStorage.attribute(.wpBookmark, at: heading.range.location, effectiveRange: nil) == nil {
                changes.append((heading.range, "_Toc\(UUID().uuidString.prefix(8))"))
            }
        }
        guard !changes.isEmpty else { return }
        let textView = self.textView
        withProtectionBypassed {
            revisionTracker.applying {
                guard textView.shouldChangeText(inRanges: changes.map { NSValue(range: $0.0) }, replacementStrings: nil) else { return }
                for (range, name) in changes { textStorage.addAttribute(.wpBookmark, value: name, range: range) }
                textView.didChangeText()
            }
        }
        updateFields()
    }

    /// Handles clicks on internal links (TOC entries, cross-references).
    func followInternalLink(_ link: Any) -> Bool {
        let string = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
        guard string.hasPrefix(Self.bookmarkLinkScheme + ":") else { return false }
        goToBookmark(named: String(string.dropFirst(Self.bookmarkLinkScheme.count + 1)))
        return true
    }

    // MARK: Captions & table of figures

    static let captionLabels = ["Figure", "Table", "Equation", "Chart", "Listing"]

    /// Inserts a caption paragraph ("Figure 3: text") after the current paragraph.
    func insertCaption(label: String, text: String, bookmarkName: String? = nil) {
        let textView = self.textView
        let sheet = styleSheet
        var attributes = sheet.attributes(for: ParagraphStyleKind.caption.rawValue)
        attributes[.wpCaption] = label
        let string = textStorage.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: min(textView.selectedRange().location, string.length), length: 0))
        let content = NSMutableAttributedString()
        let insertionPoint = NSMaxRange(paragraph)
        if insertionPoint > 0 && !TextFormatter.isAtParagraphStart(insertionPoint, in: string) {
            content.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        let captionStart = content.length
        content.append(NSAttributedString(string: label + " ", attributes: attributes))
        var sequence = FieldSpec(kind: .sequence, argument: label)
        sequence.display = .number
        content.append(ObjectFactory.string(for: .field(sequence), image: nil, attributes: attributes))
        content.append(NSAttributedString(string: text.isEmpty ? "" : ": " + text, attributes: attributes))
        let captionEnd = content.length
        content.append(NSAttributedString(string: "\n", attributes: attributes))
        let name = bookmarkName ?? "_Ref\(UUID().uuidString.prefix(8))"
        content.addAttribute(.wpBookmark, value: name, range: NSRange(location: captionStart, length: captionEnd - captionStart))
        textView.setSelectedRange(NSRange(location: insertionPoint, length: 0))
        TextFormatter.replaceSelection(in: textView, with: content, actionName: "Insert Caption")
        updateFields()
    }

    struct CaptionEntry: Identifiable {
        let id: Int
        let label: String
        let text: String
        let bookmark: String?
        let page: Int
    }

    func captions(label: String? = nil) -> [CaptionEntry] {
        var entries: [CaptionEntry] = []
        let string = textStorage.string as NSString
        textStorage.enumerateAttribute(.wpCaption, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let captionLabel = value as? String, label == nil || captionLabel == label, !isGenerated(range.location) else { return }
            let paragraph = string.paragraphRange(for: NSRange(location: range.location, length: 0))
            if entries.last?.id == paragraph.location { return }
            let display = displayText(of: paragraph)
            entries.append(CaptionEntry(
                id: paragraph.location,
                label: captionLabel,
                text: display,
                bookmark: textStorage.attribute(.wpBookmark, at: range.location, effectiveRange: nil) as? String,
                page: (engine?.page(forCharacterAt: range.location) ?? 0) + 1
            ))
        }
        return entries
    }

    /// Paragraph text with live fields replaced by their current values.
    func displayText(of range: NSRange) -> String {
        var result = ""
        textStorage.enumerateAttributes(in: range) { attributes, run, _ in
            if let object = DocumentObject.decode(attributes[.wpObject]), let field = object.field {
                result += FieldEvaluator.text(for: field, objectID: object.id, characterIndex: run.location, layoutManager: layoutManager, container: nil)
            } else {
                result += (textStorage.string as NSString).substring(with: run)
            }
        }
        return result.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func insertTableOfFigures(label: String) {
        let entries = captions(label: label)
        let sheet = styleSheet
        let content = NSMutableAttributedString()
        content.append(NSAttributedString(string: "List of \(label == "Figure" ? "Figures" : label + "s")\n", attributes: sheet.attributes(for: "heading2")))
        let width = geometry.columnWidth
        for entry in entries {
            var attributes = sheet.attributes(for: "normal")
            if let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                style.tabStops = [NSTextTab(textAlignment: .right, location: width - 12)]
                style.paragraphSpacing = 2
                attributes[.paragraphStyle] = style
            }
            attributes[.wpTabLeader] = "dot"
            var linkAttributes = attributes
            if let bookmark = entry.bookmark, let url = URL(string: "\(Self.bookmarkLinkScheme):\(bookmark)") { linkAttributes[.link] = url }
            content.append(NSAttributedString(string: entry.text, attributes: linkAttributes))
            content.append(NSAttributedString(string: "\t\(entry.page)\n", attributes: attributes))
        }
        if entries.isEmpty {
            content.append(NSAttributedString(string: "No \(label.lowercased()) captions found.\n", attributes: sheet.attributes(for: "normal")))
        }
        let kind = "tof-" + label
        GeneratedContent.replace(kind: kind, existing: GeneratedContent.range(of: kind, in: textStorage), with: content, in: self)
    }

    // MARK: Cross-references

    enum CrossReferenceTarget: Hashable, Identifiable {
        case heading(OutlineItem)
        case caption(CaptionEntry)
        case bookmark(String)

        var id: String {
            switch self {
            case .heading(let item): "h\(item.id)"
            case .caption(let entry): "c\(entry.id)"
            case .bookmark(let name): "b" + name
            }
        }

        var title: String {
            switch self {
            case .heading(let item): item.title
            case .caption(let entry): entry.text
            case .bookmark(let name): name
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    func crossReferenceTargets() -> [CrossReferenceTarget] {
        computeOutline().filter { $0.level >= 1 }.map(CrossReferenceTarget.heading)
            + captions().map(CrossReferenceTarget.caption)
            + bookmarkNames.filter { !$0.hasPrefix("_") }.map(CrossReferenceTarget.bookmark)
    }

    func insertCrossReference(to target: CrossReferenceTarget, display: CrossReferenceDisplay, asLink: Bool) {
        var name: String
        switch target {
        case .heading(let item):
            ensureHeadingBookmarks()
            name = textStorage.attribute(.wpBookmark, at: item.range.location, effectiveRange: nil) as? String ?? ""
        case .caption(let entry):
            name = entry.bookmark ?? ""
        case .bookmark(let bookmark):
            name = bookmark
        }
        guard !name.isEmpty else { NSSound.beep(); return }
        var spec = FieldSpec(kind: .crossReference, argument: name)
        spec.display = display
        let textView = self.textView
        var attributes = TextFormatter.baseAttributes(for: textView)
        if asLink, let url = URL(string: "\(Self.bookmarkLinkScheme):\(name)") { attributes[.link] = url }
        let content = NSMutableAttributedString(attributedString: ObjectFactory.string(for: .field(spec), image: nil, attributes: attributes))
        if asLink, let url = URL(string: "\(Self.bookmarkLinkScheme):\(name)") {
            content.addAttribute(.link, value: url, range: NSRange(location: 0, length: content.length))
        }
        TextFormatter.replaceSelection(in: textView, with: content, actionName: "Cross-reference")
        updateFields()
    }

    // MARK: Index

    func markIndexEntry(_ entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        TextFormatter.setAttribute(.wpIndexEntry, to: trimmed, in: textView, actionName: "Mark Index Entry")
    }

    func insertIndex() {
        var entries: [String: Set<Int>] = [:]
        textStorage.enumerateAttribute(.wpIndexEntry, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let term = value as? String, !isGenerated(range.location) else { return }
            entries[term, default: []].insert((engine?.page(forCharacterAt: range.location) ?? 0) + 1)
        }
        let sheet = styleSheet
        let content = NSMutableAttributedString()
        content.append(NSAttributedString(string: "Index\n", attributes: sheet.attributes(for: "heading1")))
        let normal = sheet.attributes(for: "noSpacing")
        var subAttributes = normal
        if let style = (normal[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.headIndent = 18
            style.firstLineHeadIndent = 18
            subAttributes[.paragraphStyle] = style
        }
        var letterAttributes = sheet.attributes(for: "heading3")
        letterAttributes[.wpParaFlags] = nil
        var lastLetter = ""
        var lastMain = ""
        for term in entries.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let parts = term.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let main = parts[0]
            let letter = String(main.prefix(1)).uppercased()
            if letter != lastLetter {
                content.append(NSAttributedString(string: letter + "\n", attributes: letterAttributes))
                lastLetter = letter
            }
            let pages = entries[term]!.sorted().map(String.init).joined(separator: ", ")
            if parts.count == 2 {
                if main != lastMain {
                    content.append(NSAttributedString(string: main + "\n", attributes: normal))
                }
                content.append(NSAttributedString(string: "\(parts[1]), \(pages)\n", attributes: subAttributes))
            } else {
                content.append(NSAttributedString(string: "\(main), \(pages)\n", attributes: normal))
            }
            lastMain = main
        }
        if entries.isEmpty {
            content.append(NSAttributedString(string: "No index entries. Select a term and choose Mark Index Entry.\n", attributes: normal))
        }
        GeneratedContent.replace(kind: "index", existing: GeneratedContent.range(of: "index", in: textStorage), with: content, in: self)
    }

    /// Rebuilds every generated table (contents, figures, bibliography, index, endnotes).
    func updateAllTables() {
        if GeneratedContent.range(of: "toc", in: textStorage) != nil { insertTableOfContents() }
        for label in Self.captionLabels where GeneratedContent.range(of: "tof-" + label, in: textStorage) != nil {
            insertTableOfFigures(label: label)
        }
        if GeneratedContent.range(of: "bibliography", in: textStorage) != nil { insertBibliography() }
        if GeneratedContent.range(of: "index", in: textStorage) != nil { insertIndex() }
        refreshCitations()
        updateFields()
    }
}
