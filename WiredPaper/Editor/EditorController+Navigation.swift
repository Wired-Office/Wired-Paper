import AppKit

struct OutlineItem: Identifiable, Equatable {
    let id: Int
    let level: Int
    let title: String
    let range: NSRange
    let page: Int
}

struct SearchOptions: Equatable {
    var matchCase = false
    var wholeWords = false
    var useRegex = false
    var useWildcards = false
}

struct SearchResult: Identifiable, Equatable {
    var id: Int { range.location }
    let range: NSRange
    let before: String
    let match: String
    let after: String
    let page: Int
}

/// Document outline, section reorganizing and advanced search.
extension EditorController {
    // MARK: Outline

    /// Headings (paragraphs whose style has an outline level) in document order.
    func computeOutline() -> [OutlineItem] {
        let string = textStorage.string as NSString
        let sheet = styleSheet
        var items: [OutlineItem] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs]) { text, range, _, _ in
            guard let text, range.length > 0 else { return }
            let id = self.textStorage.attribute(.wpParagraphStyle, at: range.location, effectiveRange: nil) as? String ?? "normal"
            let level: Int?
            if id == ParagraphStyleKind.title.rawValue {
                level = 0
            } else {
                level = sheet.outlineLevel(for: id)
            }
            guard let level else { return }
            let title = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            items.append(OutlineItem(id: range.location, level: level, title: title, range: range, page: (self.engine?.page(forCharacterAt: range.location) ?? 0) + 1))
        }
        return items
    }

    func refreshOutline() {
        let outline = computeOutline()
        if outline != sidebar.outline { sidebar.outline = outline }
        let location = textView.selectedRange().location
        let current = outline.last { $0.range.location <= location }?.id
        if current != sidebar.currentOutlineID { sidebar.currentOutlineID = current }
    }

    /// The heading paragraph plus everything up to the next heading of the same or higher level.
    func sectionRange(for item: OutlineItem) -> NSRange {
        let outline = sidebar.outline.isEmpty ? computeOutline() : sidebar.outline
        let end = outline.first { $0.range.location > item.range.location && $0.level <= item.level }?.range.location ?? textStorage.length
        return NSRange(location: item.range.location, length: end - item.range.location)
    }

    func selectSection(_ item: OutlineItem) {
        reveal(sectionRange(for: item))
    }

    /// Moves a heading's whole section above the previous (or below the next) sibling section.
    func moveSection(_ item: OutlineItem, up: Bool) {
        let outline = computeOutline()
        let section = sectionRange(for: item)
        let siblings = outline.filter { $0.level == item.level }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }) else { return }
        let targetIndex = up ? index - 1 : index + 1
        guard siblings.indices.contains(targetIndex) else { NSSound.beep(); return }
        let other = sectionRange(for: siblings[targetIndex])
        // Swap two adjacent sections as one undoable replacement.
        let first = up ? other : section
        let second = up ? section : other
        guard NSMaxRange(first) == second.location else { NSSound.beep(); return }
        let combined = NSUnionRange(first, second)
        let firstText = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: first))
        let secondText = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: second))
        // Each section must end with a paragraph break once reordered.
        for text in [firstText, secondText] where !text.string.hasSuffix("\n") {
            text.append(NSAttributedString(string: "\n", attributes: text.length > 0 ? text.attributes(at: text.length - 1, effectiveRange: nil) : [:]))
        }
        let result = NSMutableAttributedString(attributedString: secondText)
        result.append(firstText)
        if !(textStorage.string as NSString).substring(with: combined).hasSuffix("\n"), result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        let textView = self.textView
        guard textView.shouldChangeText(in: combined, replacementString: result.string) else { return }
        textStorage.replaceCharacters(in: combined, with: result)
        textView.didChangeText()
        textView.undoManager?.setActionName("Move Section")
        let newStart = up ? combined.location : combined.location + secondText.length
        reveal(NSRange(location: newStart, length: 0))
        refreshOutline()
    }

    /// Changes a heading's level (and its subheadings' levels) by `delta`.
    func changeHeadingLevel(_ item: OutlineItem, by delta: Int) {
        let section = sectionRange(for: item)
        let headings = computeOutline().filter { NSLocationInRange($0.range.location, section) && $0.level > 0 }
        guard !headings.isEmpty else { return }
        let textView = self.textView
        document?.undoManager?.beginUndoGrouping()
        for heading in headings {
            let newLevel = min(max(heading.level + delta, 1), 9)
            textView.setSelectedRange(NSRange(location: heading.range.location, length: 0))
            applyStyle(id: ParagraphStyleKind.heading(newLevel).rawValue)
        }
        document?.undoManager?.endUndoGrouping()
        document?.undoManager?.setActionName(delta < 0 ? "Promote" : "Demote")
        reveal(NSRange(location: item.range.location, length: 0))
        refreshOutline()
    }

    func deleteSection(_ item: OutlineItem) {
        let section = sectionRange(for: item)
        let textView = self.textView
        textView.setSelectedRange(section)
        textView.delete(nil)
        refreshOutline()
    }

    // MARK: Advanced search

    func regex(for query: String, options: SearchOptions) -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern: String
        if options.useRegex {
            pattern = query
        } else if options.useWildcards {
            // * = any run of characters, ? = one character, [..] passes through.
            pattern = NSRegularExpression.escapedPattern(for: query)
                .replacingOccurrences(of: "\\*", with: ".*?")
                .replacingOccurrences(of: "\\?", with: ".")
                .replacingOccurrences(of: "\\[", with: "[")
                .replacingOccurrences(of: "\\]", with: "]")
        } else {
            pattern = NSRegularExpression.escapedPattern(for: query)
        }
        if options.wholeWords { pattern = "\\b(?:" + pattern + ")\\b" }
        return try? NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive])
    }

    func search(_ query: String, options: SearchOptions) -> [SearchResult] {
        guard let expression = regex(for: query, options: options) else {
            clearSearchHighlights()
            return []
        }
        let string = textStorage.string as NSString
        var results: [SearchResult] = []
        expression.enumerateMatches(in: textStorage.string, range: NSRange(location: 0, length: string.length)) { match, _, stop in
            guard let range = match?.range, range.length > 0 else { return }
            let beforeStart = max(range.location - 30, 0)
            let afterEnd = min(NSMaxRange(range) + 40, string.length)
            func clean(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{FFFC}", with: "") }
            results.append(SearchResult(
                range: range,
                before: clean(string.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))),
                match: clean(string.substring(with: range)),
                after: clean(string.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range)))),
                page: (engine?.page(forCharacterAt: range.location) ?? 0) + 1
            ))
            if results.count >= 2000 { stop.pointee = true }
        }
        highlightSearchResults(results)
        return results
    }

    func highlightSearchResults(_ results: [SearchResult]) {
        clearSearchHighlights()
        let color = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.35, alpha: 0.55)
        for result in results {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: result.range)
        }
    }

    func clearSearchHighlights() {
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: textStorage.length))
        refreshMarkup()
    }

    /// Replaces every match; with regular expressions, `$1` etc. refer to groups.
    @discardableResult
    func replaceAll(_ query: String, with template: String, options: SearchOptions) -> Int {
        guard let expression = regex(for: query, options: options) else { return 0 }
        let matches = expression.matches(in: textStorage.string, range: NSRange(location: 0, length: textStorage.length))
        guard !matches.isEmpty else { return 0 }
        let replacements = matches.map { match in
            options.useRegex ? expression.replacementString(for: match, in: textStorage.string, offset: 0, template: template) : template
        }
        let textView = self.textView
        guard textView.shouldChangeText(inRanges: matches.map { NSValue(range: $0.range) }, replacementStrings: replacements) else { return 0 }
        textStorage.beginEditing()
        for (match, replacement) in zip(matches, replacements).reversed() {
            textStorage.replaceCharacters(in: match.range, with: replacement)
        }
        textStorage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName("Replace All")
        return matches.count
    }
}
