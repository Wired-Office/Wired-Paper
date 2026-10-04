import Foundation

struct DocumentStatistics: Equatable {
    var words = 0
    var characters = 0
    var charactersExcludingSpaces = 0
    var paragraphs = 0

    static let empty = DocumentStatistics()

    /// Counts like a word processor: paragraph marks, page breaks and image
    /// placeholders are not characters, and list markers are not words.
    static func compute(_ string: String) -> DocumentStatistics {
        var stats = DocumentStatistics()
        let text = string as NSString
        let full = NSRange(location: 0, length: text.length)

        text.enumerateSubstrings(in: full, options: [.byParagraphs]) { paragraph, _, _, _ in
            guard let paragraph else { return }
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed != "\u{FFFC}" { stats.paragraphs += 1 }
        }

        text.enumerateSubstrings(in: full, options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            stats.words += 1
        }
        stats.words -= listMarkerCount(in: text)

        for character in string {
            switch character {
            case "\n", "\r", "\r\n", "\u{2028}", "\u{2029}", "\u{0C}", "\u{FFFC}":
                continue
            default:
                stats.characters += 1
                if !character.isWhitespace { stats.charactersExcludingSpaces += 1 }
            }
        }
        stats.words = max(stats.words, 0)
        return stats
    }

    /// Numbered list markers ("\t12.\t") would otherwise count as words.
    private static func listMarkerCount(in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs]) { paragraph, _, _, _ in
            guard let paragraph, paragraph.hasPrefix("\t") else { return }
            let parts = paragraph.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return }
            let marker = parts[1]
            if !marker.isEmpty, marker.count <= 6, marker.contains(where: { $0.isNumber }) { count += 1 }
        }
        return count
    }
}
