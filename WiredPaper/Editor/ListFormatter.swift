import AppKit

/// Bulleted, numbered and multilevel lists built on NSTextList.
///
/// TextKit 1 represents a list item as a paragraph whose style carries the
/// NSTextList of each level it belongs to (outermost first), with the marker
/// spelled out in the text as "\t•\t" (or "\t1.\t"). NSTextView itself continues
/// a list when Return is pressed and ends it on an empty item; this type turns
/// lists on and off, changes levels and formats, and keeps numbering correct.
enum ListFormatter {
    static let levelIndent: CGFloat = 36
    static let markerLocation: CGFloat = 18
    static let textIndent: CGFloat = 36
    static let maxLevel = 8

    /// Marker formats cycled through by level.
    static let bulletFormats = ["{disc}", "{circle}", "{square}"]
    static let numberFormats = ["{decimal}.", "{lower-alpha}.", "{lower-roman}."]

    struct MarkerStyle: Identifiable, Hashable {
        let name: String
        let format: String
        var id: String { format }
        var kind: ListKind { ListKind(markerFormat: NSTextList.MarkerFormat(rawValue: format)) ?? .bullet }
    }

    static let bulletStyles: [MarkerStyle] = [
        MarkerStyle(name: "● Disc", format: "{disc}"),
        MarkerStyle(name: "○ Circle", format: "{circle}"),
        MarkerStyle(name: "■ Square", format: "{square}"),
        MarkerStyle(name: "◆ Diamond", format: "{diamond}"),
        MarkerStyle(name: "✓ Check", format: "{check}"),
        MarkerStyle(name: "– Dash", format: "{hyphen}"),
        MarkerStyle(name: "➤ Arrow", format: "➤"),
        MarkerStyle(name: "★ Star", format: "★"),
    ]

    static let numberStyles: [MarkerStyle] = [
        MarkerStyle(name: "1. 2. 3.", format: "{decimal}."),
        MarkerStyle(name: "1) 2) 3)", format: "{decimal})"),
        MarkerStyle(name: "(1) (2) (3)", format: "({decimal})"),
        MarkerStyle(name: "a. b. c.", format: "{lower-alpha}."),
        MarkerStyle(name: "A. B. C.", format: "{upper-alpha}."),
        MarkerStyle(name: "i. ii. iii.", format: "{lower-roman}."),
        MarkerStyle(name: "I. II. III.", format: "{upper-roman}."),
    ]

    static func format(for kind: ListKind, level: Int) -> NSTextList.MarkerFormat {
        let formats = kind == .bullet ? bulletFormats : numberFormats
        return NSTextList.MarkerFormat(rawValue: formats[level % formats.count])
    }

    static func listParagraphStyle(basedOn base: NSParagraphStyle?, lists: [NSTextList]) -> NSParagraphStyle {
        let style = ((base ?? .default).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let level = CGFloat(max(lists.count - 1, 0))
        style.textLists = lists
        style.headIndent = textIndent + level * levelIndent
        style.firstLineHeadIndent = 0
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: markerLocation + level * levelIndent),
            NSTextTab(textAlignment: .left, location: textIndent + level * levelIndent),
        ]
        return style
    }

    static func listParagraphStyle(basedOn base: NSParagraphStyle?, list: NSTextList) -> NSParagraphStyle {
        listParagraphStyle(basedOn: base, lists: [list])
    }

    static func marker(for list: NSTextList, number: Int) -> String {
        "\t\(list.marker(forItemNumber: number + list.startingItemNumber - 1))\t"
    }

    /// Builds a complete single-level list (used by templates and imports).
    static func makeList(_ items: [String], kind: ListKind, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let list = NSTextList(markerFormat: kind.markerFormat, options: 0)
        var itemAttributes = attributes
        itemAttributes[.paragraphStyle] = listParagraphStyle(basedOn: attributes[.paragraphStyle] as? NSParagraphStyle, list: list)
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            result.append(NSAttributedString(string: marker(for: list, number: index + 1) + item + "\n", attributes: itemAttributes))
        }
        return result
    }

    static func listKind(ofParagraphAt location: Int, in storage: NSAttributedString, typingAttributes: [NSAttributedString.Key: Any]) -> ListKind? {
        lists(ofParagraphAt: location, in: storage, typingAttributes: typingAttributes).last.flatMap { ListKind(markerFormat: $0.markerFormat) }
    }

    static func lists(ofParagraphAt location: Int, in storage: NSAttributedString, typingAttributes: [NSAttributedString.Key: Any]) -> [NSTextList] {
        let style: NSParagraphStyle?
        if location < storage.length {
            style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        } else {
            style = typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return style?.textLists ?? []
    }

    // MARK: - Paragraph helpers

    private static func paragraphRanges(for selection: NSRange, in string: NSString) -> (full: NSRange, paragraphs: [NSRange]) {
        let fullRange = string.paragraphRange(for: selection)
        var paragraphs: [NSRange] = []
        if fullRange.length > 0 {
            string.enumerateSubstrings(in: fullRange, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
                paragraphs.append(enclosing)
            }
        }
        if paragraphs.isEmpty { paragraphs = [fullRange] }
        return (fullRange, paragraphs)
    }

    /// Rebuilds a paragraph with new list membership: strips any old marker,
    /// inserts the new marker and sets the paragraph style.
    private static func rebuild(
        _ original: NSAttributedString,
        typing: [NSAttributedString.Key: Any],
        lists: [NSTextList],
        number: Int
    ) -> (NSAttributedString, delta: Int) {
        let paragraph = NSMutableAttributedString(attributedString: original)
        var baseAttributes = paragraph.length > 0 ? paragraph.attributes(at: 0, effectiveRange: nil) : typing
        baseAttributes.removeValue(forKey: .attachment)
        baseAttributes.removeValue(forKey: .link)
        baseAttributes.removeValue(forKey: .wpObject)
        let oldStyle = baseAttributes[.paragraphStyle] as? NSParagraphStyle
        var delta = -stripMarker(from: paragraph, style: oldStyle)

        let newStyle: NSParagraphStyle
        if lists.isEmpty {
            let plain = ((oldStyle ?? .default).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            plain.textLists = []
            plain.headIndent = 0
            plain.firstLineHeadIndent = 0
            plain.tabStops = []
            plain.defaultTabInterval = 36
            newStyle = plain
        } else {
            newStyle = listParagraphStyle(basedOn: oldStyle, lists: lists)
            let markerText = marker(for: lists[lists.count - 1], number: number)
            paragraph.insert(NSAttributedString(string: markerText, attributes: baseAttributes), at: 0)
            delta += (markerText as NSString).length
        }
        paragraph.addAttribute(.paragraphStyle, value: newStyle, range: NSRange(location: 0, length: paragraph.length))
        return (paragraph, delta)
    }

    private static func replace(
        _ fullRange: NSRange,
        with result: NSAttributedString,
        in textView: NSTextView,
        selection: NSRange,
        firstDelta: Int,
        singleParagraph: Bool,
        actionName: String
    ) {
        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: fullRange, replacementString: result.string) else { return }
        storage.replaceCharacters(in: fullRange, with: result)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)

        if selection.length == 0 && singleParagraph {
            let location = max(fullRange.location, min(selection.location + firstDelta, fullRange.location + result.length))
            textView.setSelectedRange(NSRange(location: location, length: 0))
        } else {
            let trailingNewline = result.string.hasSuffix("\n") ? 1 : 0
            textView.setSelectedRange(NSRange(location: fullRange.location, length: max(result.length - trailingNewline, 0)))
        }
        if result.length > 0, let style = result.attribute(.paragraphStyle, at: result.length - 1, effectiveRange: nil) {
            var typing = textView.typingAttributes
            typing[.paragraphStyle] = style
            textView.typingAttributes = typing
        }
    }

    // MARK: - Toggle

    /// Toggles a list of the given kind on every paragraph in the selection.
    static func toggle(_ kind: ListKind, in textView: NSTextView, format: NSTextList.MarkerFormat? = nil) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let selection = textView.selectedRange()
        let (fullRange, paragraphs) = paragraphRanges(for: selection, in: string)

        let removing = format == nil && paragraphs.allSatisfy {
            listKind(ofParagraphAt: $0.location, in: storage, typingAttributes: textView.typingAttributes) == kind
        }

        // Continue an adjacent list of the same kind instead of starting a new one.
        var list = NSTextList(markerFormat: format ?? kind.markerFormat, options: 0)
        if !removing, format == nil, fullRange.location > 0,
           let style = storage.attribute(.paragraphStyle, at: fullRange.location - 1, effectiveRange: nil) as? NSParagraphStyle,
           let previous = style.textLists.first, ListKind(markerFormat: previous.markerFormat) == kind, style.textLists.count == 1 {
            list = previous
        }

        let result = NSMutableAttributedString()
        var firstDelta = 0
        for (index, range) in paragraphs.enumerated() {
            let original: NSAttributedString = range.length > 0
                ? storage.attributedSubstring(from: range)
                : NSAttributedString(string: "", attributes: textView.typingAttributes)
            let (rebuilt, delta) = rebuild(original, typing: textView.typingAttributes, lists: removing ? [] : [list], number: 1)
            if index == 0 { firstDelta = delta }
            result.append(rebuilt)
        }

        replace(fullRange, with: result, in: textView, selection: selection, firstDelta: firstDelta,
                singleParagraph: paragraphs.count == 1,
                actionName: removing ? "Remove List" : (kind == .bullet ? "Bulleted List" : "Numbered List"))
        renumber(in: textView)
    }

    // MARK: - Levels

    /// Demotes (+1) or promotes (−1) the list items in the selection.
    /// Returns false when the selection isn't in a list.
    @discardableResult
    static func changeLevel(by delta: Int, in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let string = storage.string as NSString
        let selection = textView.selectedRange()
        let (fullRange, paragraphs) = paragraphRanges(for: selection, in: string)
        let currentLists = paragraphs.map { lists(ofParagraphAt: $0.location, in: storage, typingAttributes: textView.typingAttributes) }
        guard currentLists.allSatisfy({ !$0.isEmpty }) else { return false }

        // The paragraph before the selection lets new sublists join an existing one.
        let previousLists: [NSTextList] = fullRange.location > 0
            ? (storage.attribute(.paragraphStyle, at: fullRange.location - 1, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []
            : []

        let result = NSMutableAttributedString()
        var firstDelta = 0
        var created: [Int: NSTextList] = [:]
        for (index, range) in paragraphs.enumerated() {
            var lists = currentLists[index]
            let kind = ListKind(markerFormat: lists[lists.count - 1].markerFormat) ?? .bullet
            let newLevel = min(max(lists.count - 1 + delta, 0), maxLevel)
            if newLevel < lists.count - 1 {
                lists = Array(lists.prefix(newLevel + 1))
            } else {
                while lists.count - 1 < newLevel {
                    let level = lists.count
                    if previousLists.count > level, Array(previousLists.prefix(level)).elementsEqual(lists, by: ===) {
                        lists.append(previousLists[level])
                    } else if let existing = created[level] {
                        lists.append(existing)
                    } else {
                        let list = NSTextList(markerFormat: format(for: kind, level: level), options: 0)
                        created[level] = list
                        lists.append(list)
                    }
                }
            }
            let original = range.length > 0 ? storage.attributedSubstring(from: range) : NSAttributedString(string: "", attributes: textView.typingAttributes)
            let (rebuilt, change) = rebuild(original, typing: textView.typingAttributes, lists: lists, number: 1)
            if index == 0 { firstDelta = change }
            result.append(rebuilt)
        }
        replace(fullRange, with: result, in: textView, selection: selection, firstDelta: firstDelta,
                singleParagraph: paragraphs.count == 1, actionName: delta > 0 ? "Increase List Level" : "Decrease List Level")
        renumber(in: textView)
        return true
    }

    /// Whether the insertion point is at the start of a list item's text (Tab changes level there).
    static func isAtItemStart(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        let string = storage.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
        guard !lists(ofParagraphAt: paragraph.location, in: storage, typingAttributes: textView.typingAttributes).isEmpty else { return false }
        if selection.length > 0 { return true }
        let prefix = string.substring(with: NSRange(location: paragraph.location, length: selection.location - paragraph.location))
        return prefix.hasPrefix("\t") && prefix.filter { $0 == "\t" }.count == 2 && prefix.hasSuffix("\t")
    }

    // MARK: - Formats and numbering

    /// Changes the marker format of the lists in the selection (at their current level).
    static func applyMarkerFormat(_ format: String, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let selection = textView.selectedRange()
        let (_, paragraphs) = paragraphRanges(for: selection, in: string)
        let markerFormat = NSTextList.MarkerFormat(rawValue: format)
        let kind = ListKind(markerFormat: markerFormat) ?? .bullet

        let inList = paragraphs.contains { !lists(ofParagraphAt: $0.location, in: storage, typingAttributes: textView.typingAttributes).isEmpty }
        guard inList else {
            toggle(kind, in: textView, format: markerFormat)
            return
        }
        // Replace each affected list object everywhere it's used, so the whole list changes.
        var targets: [ObjectIdentifier: NSTextList] = [:]
        for range in paragraphs {
            guard let list = lists(ofParagraphAt: range.location, in: storage, typingAttributes: textView.typingAttributes).last else { continue }
            if targets[ObjectIdentifier(list)] == nil {
                let replacement = NSTextList(markerFormat: markerFormat, options: 0)
                replacement.startingItemNumber = list.startingItemNumber
                targets[ObjectIdentifier(list)] = replacement
            }
        }
        replaceLists(targets, in: textView, actionName: "List Style")
    }

    /// Starts numbering again at the item containing the insertion point.
    static func restartNumbering(in textView: NSTextView, at start: Int = 1) {
        guard let storage = textView.textStorage else { return }
        let location = textView.selectedRange().location
        guard let list = lists(ofParagraphAt: location, in: storage, typingAttributes: textView.typingAttributes).last else { return }
        let replacement = NSTextList(markerFormat: list.markerFormat, options: 0)
        replacement.startingItemNumber = max(start, 0)
        let paragraphStart = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0)).location
        replaceLists([ObjectIdentifier(list): replacement], in: textView, from: paragraphStart, actionName: "Restart Numbering")
    }

    /// Joins the list at the insertion point to the previous list of the same kind.
    static func continueNumbering(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let location = textView.selectedRange().location
        let current = lists(ofParagraphAt: location, in: storage, typingAttributes: textView.typingAttributes)
        guard let list = current.last else { return }
        let level = current.count - 1
        let kind = ListKind(markerFormat: list.markerFormat)
        let string = storage.string as NSString
        var index = string.paragraphRange(for: NSRange(location: location, length: 0)).location - 1
        while index >= 0 {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            if let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
               style.textLists.count == level + 1, let previous = style.textLists.last, previous !== list,
               ListKind(markerFormat: previous.markerFormat) == kind {
                replaceLists([ObjectIdentifier(list): previous], in: textView, actionName: "Continue Numbering")
                return
            }
            index = paragraph.location - 1
        }
    }

    private static func replaceLists(_ map: [ObjectIdentifier: NSTextList], in textView: NSTextView, from start: Int = 0, actionName: String) {
        guard let storage = textView.textStorage, !map.isEmpty else { return }
        let range = NSRange(location: start, length: storage.length - start)
        var changes: [(NSRange, NSParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
            guard let style = value as? NSParagraphStyle, style.textLists.contains(where: { map[ObjectIdentifier($0)] != nil }),
                  let updated = style.mutableCopy() as? NSMutableParagraphStyle else { return }
            updated.textLists = style.textLists.map { map[ObjectIdentifier($0)] ?? $0 }
            changes.append((run, updated))
        }
        guard !changes.isEmpty, textView.shouldChangeText(inRanges: changes.map { NSValue(range: $0.0) }, replacementStrings: nil) else { return }
        storage.beginEditing()
        for (run, style) in changes { storage.addAttribute(.paragraphStyle, value: style, range: run) }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        renumber(in: textView)
    }

    /// Rewrites list markers so numbering is sequential. Sublists restart
    /// after an item of a higher level. Returns true if anything changed.
    @discardableResult
    static func renumber(in textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let string = storage.string as NSString
        var counters: [ObjectIdentifier: Int] = [:]
        var ranges: [NSValue] = []
        var replacements: [String] = []

        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, content, _, _ in
            guard content.length > 0,
                  let style = storage.attribute(.paragraphStyle, at: content.location, effectiveRange: nil) as? NSParagraphStyle,
                  let list = style.textLists.last else { return }
            let active = Set(style.textLists.map(ObjectIdentifier.init))
            counters = counters.filter { active.contains($0.key) }
            let number = (counters[ObjectIdentifier(list)] ?? 0) + 1
            counters[ObjectIdentifier(list)] = number

            let expected = marker(for: list, number: number)
            // Current marker: "\t…\t" at the start of the paragraph.
            guard string.character(at: content.location) == 0x09 else { return }
            let search = NSRange(location: content.location + 1, length: min(content.length - 1, 24))
            let secondTab = string.range(of: "\t", options: [], range: search)
            guard secondTab.location != NSNotFound else { return }
            let markerRange = NSRange(location: content.location, length: secondTab.location + 1 - content.location)
            if string.substring(with: markerRange) != expected {
                ranges.append(NSValue(range: markerRange))
                replacements.append(expected)
            }
        }
        guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges, replacementStrings: replacements) else { return false }
        storage.beginEditing()
        for (value, replacement) in zip(ranges, replacements).reversed() {
            let range = value.rangeValue
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        storage.endEditing()
        textView.didChangeText()
        return true
    }

    /// Removes a leading "\t<marker>\t" from a list paragraph. Returns the number
    /// of UTF-16 units removed.
    @discardableResult
    static func stripMarker(from paragraph: NSMutableAttributedString, style: NSParagraphStyle?) -> Int {
        guard let style, !style.textLists.isEmpty else { return 0 }
        let text = paragraph.string as NSString
        guard text.length >= 2, text.character(at: 0) == 0x09 else { return 0 }
        let searchRange = NSRange(location: 1, length: min(text.length - 1, 24))
        let secondTab = text.range(of: "\t", options: [], range: searchRange)
        guard secondTab.location != NSNotFound else { return 0 }
        let markerLength = secondTab.location + 1
        paragraph.deleteCharacters(in: NSRange(location: 0, length: markerLength))
        return markerLength
    }
}
