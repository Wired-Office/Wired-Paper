import AppKit

/// Wired Paper's own text attributes. All have String values so they can be
/// stored as runs in `Document.json` (RTF has no place for them) and archived
/// on the pasteboard.
extension NSAttributedString.Key {
    /// "1" — hidden text.
    static let wpHidden = NSAttributedString.Key("WPHidden")
    /// Space-separated comment thread ids anchored to this text.
    static let wpComment = NSAttributedString.Key("WPComment")
    /// "ins:<id>" or "del:<id>" — a tracked change.
    static let wpRevision = NSAttributedString.Key("WPRevision")
    /// Bookmark name.
    static let wpBookmark = NSAttributedString.Key("WPBookmark")
    /// JSON describing a live object (chart, equation, field, form control…) on an attachment character.
    static let wpObject = NSAttributedString.Key("WPObject")
    /// Leader drawn across a tab character: "dot", "dash", "line".
    static let wpTabLeader = NSAttributedString.Key("WPTabLeader")
    /// Paragraph flags: space-separated `ParagraphFlags` tokens.
    static let wpParaFlags = NSAttributedString.Key("WPParaFlags")
    /// Character flags: space-separated `CharacterFlags` tokens.
    static let wpCharFlags = NSAttributedString.Key("WPCharFlags")
    /// Comma-separated citation source ids.
    static let wpCitation = NSAttributedString.Key("WPCitation")
    /// Caption label ("Figure", "Table", "Equation") on caption paragraphs.
    static let wpCaption = NSAttributedString.Key("WPCaption")
    /// Mail-merge field name.
    static let wpMergeField = NSAttributedString.Key("WPMergeField")
    /// Form text field name (editable region in protected forms).
    static let wpFormField = NSAttributedString.Key("WPFormField")
    /// "column" marks a form feed as a column break (default: page break).
    static let wpBreakKind = NSAttributedString.Key("WPBreakKind")
    /// Index entry text ("Main" or "Main:Sub").
    static let wpIndexEntry = NSAttributedString.Key("WPIndexEntry")
    /// Alternative text for images.
    static let wpAltText = NSAttributedString.Key("WPAltText")
    /// Marks generated content (table of contents, bibliography, index…): "toc", "bibliography"…
    static let wpGenerated = NSAttributedString.Key("WPGenerated")
}

/// Tokens stored in `.wpParaFlags`.
enum ParagraphFlags {
    static let keepWithNext = "kwn"
    static let keepTogether = "klt"
    static let pageBreakBefore = "pbb"
    static let noWidowControl = "nowidow"
}

/// Token-set helpers for the space-separated flag attributes.
enum FlagTokens {
    static func set(_ value: Any?) -> Set<String> {
        guard let string = value as? String else { return [] }
        return Set(string.split(separator: " ").map(String.init))
    }

    static func string(_ tokens: Set<String>) -> String? {
        tokens.isEmpty ? nil : tokens.sorted().joined(separator: " ")
    }

    static func contains(_ value: Any?, _ token: String) -> Bool {
        set(value).contains(token)
    }
}

enum CharacterFlags {
    static let allCaps = "caps"
    static let smallCaps = "smallcaps"
}

struct AttributeRun: Codable, Equatable {
    var location: Int
    var length: Int
    var value: String
}

enum PersistentAttributes {
    static let keys: [NSAttributedString.Key] = [
        .wpParagraphStyle, .wpHidden, .wpComment, .wpRevision, .wpBookmark, .wpObject, .wpTabLeader,
        .wpParaFlags, .wpCharFlags, .wpCitation, .wpCaption, .wpMergeField, .wpFormField, .wpBreakKind,
        .wpIndexEntry, .wpAltText, .wpGenerated,
    ]

    static func collect(from text: NSAttributedString) -> [String: [AttributeRun]] {
        var result: [String: [AttributeRun]] = [:]
        let full = NSRange(location: 0, length: text.length)
        for key in keys {
            var runs: [AttributeRun] = []
            text.enumerateAttribute(key, in: full) { value, range, _ in
                guard let string = value as? String, !string.isEmpty else { return }
                if key == .wpParagraphStyle && string == ParagraphStyleKind.normal.rawValue { return }
                runs.append(AttributeRun(location: range.location, length: range.length, value: string))
            }
            if !runs.isEmpty { result[key.rawValue] = runs }
        }
        return result
    }

    static func restore(_ runs: [String: [AttributeRun]], into text: NSMutableAttributedString) {
        for (name, list) in runs {
            let key = NSAttributedString.Key(name)
            for run in list where run.length > 0 && run.location >= 0 && run.location + run.length <= text.length {
                text.addAttribute(key, value: run.value, range: NSRange(location: run.location, length: run.length))
            }
        }
    }

    // MARK: Pasteboard

    /// Private pasteboard type carrying the full attributed string, including
    /// custom attributes that RTFD would drop.
    static let pasteboardType = NSPasteboard.PasteboardType("com.wiredpaper.rich-text")

    static func archive(_ text: NSAttributedString) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: text, requiringSecureCoding: false)
    }

    static func unarchive(_ data: Data) -> NSAttributedString? {
        let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver?.requiresSecureCoding = false
        defer { unarchiver?.finishDecoding() }
        return unarchiver?.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString
    }
}
