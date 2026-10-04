import AppKit

/// How tracked changes look: colored underline for insertions, colored
/// strikethrough for deletions, one color per author.
enum RevisionMarkup {
    private static let palette: [NSColor] = [
        NSColor(srgbRed: 0.80, green: 0.15, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.40, blue: 0.80, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.25, blue: 0.70, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.50, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.45, blue: 0.05, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.50, blue: 0.55, alpha: 1),
    ]

    static func color(forAuthor author: String) -> NSColor {
        let hash = author.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    /// Parses "ins:<id>" / "del:<id>".
    static func parse(_ value: Any?) -> (kind: RevisionKind, id: String)? {
        guard let string = value as? String, string.count > 4 else { return nil }
        let id = String(string.dropFirst(4))
        if string.hasPrefix("ins:") { return (.insertion, id) }
        if string.hasPrefix("del:") { return (.deletion, id) }
        if string.hasPrefix("fmt:") { return (.formatting, id) }
        return nil
    }

    /// Display attributes for a revision (used as temporary attributes on
    /// screen and as real attributes when printing with markup).
    static func attributes(kind: RevisionKind, author: String) -> [NSAttributedString.Key: Any] {
        let color = color(forAuthor: author)
        switch kind {
        case .insertion:
            return [.foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: color]
        case .deletion:
            return [.foregroundColor: color, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: color]
        case .formatting:
            return [.underlineStyle: NSUnderlineStyle.double.rawValue, .underlineColor: color]
        }
    }

    /// Makes revisions visible in a copy of the text used for printing.
    static func applyPrintMarkup(to storage: NSTextStorage, mode: MarkupMode, authors: [String: String] = [:]) {
        guard mode == .all else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.wpRevision, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let (kind, id) = parse(value) else { return }
            storage.addAttributes(attributes(kind: kind, author: authors[id] ?? ""), range: range)
        }
        storage.endEditing()
    }

    /// Shows revisions and comment anchors on screen without changing the text.
    static func applyScreenMarkup(
        to layoutManager: NSLayoutManager,
        range: NSRange,
        mode: MarkupMode,
        authors: [String: String],
        activeComment: String?
    ) {
        guard let storage = layoutManager.textStorage, range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let keys: [NSAttributedString.Key] = [.foregroundColor, .underlineStyle, .underlineColor, .strikethroughStyle, .strikethroughColor, .backgroundColor]
        for key in keys { layoutManager.removeTemporaryAttribute(key, forCharacterRange: range) }

        if mode == .all {
            storage.enumerateAttribute(.wpRevision, in: range) { value, run, _ in
                guard let (kind, id) = parse(value) else { return }
                layoutManager.addTemporaryAttributes(attributes(kind: kind, author: authors[id] ?? ""), forCharacterRange: run)
            }
        }
        storage.enumerateAttribute(.wpComment, in: range) { value, run, _ in
            guard let ids = value as? String, !ids.isEmpty else { return }
            let isActive = activeComment.map { ids.split(separator: " ").contains(Substring($0)) } ?? false
            let color = isActive
                ? NSColor(srgbRed: 1.0, green: 0.82, blue: 0.35, alpha: 0.75)
                : NSColor(srgbRed: 1.0, green: 0.92, blue: 0.62, alpha: 0.6)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: run)
        }
        storage.enumerateAttribute(.wpHidden, in: range) { value, run, _ in
            guard value != nil else { return }
            layoutManager.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue, .underlineColor: NSColor.gray], forCharacterRange: run)
        }
    }
}
