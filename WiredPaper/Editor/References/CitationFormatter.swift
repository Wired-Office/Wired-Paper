import AppKit

/// Formats in-text citations and bibliography entries in APA, MLA, Chicago
/// (author-date) and IEEE styles.
enum CitationFormatter {
    struct Name {
        let last: String
        let given: String

        init(_ raw: String) {
            let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                last = parts[0]
                given = parts[1]
            } else {
                let words = raw.split(separator: " ")
                last = words.last.map(String.init) ?? raw
                given = words.dropLast().joined(separator: " ")
            }
        }

        var initials: String {
            given.split(whereSeparator: { $0 == " " || $0 == "-" }).compactMap(\.first).map { "\($0)." }.joined(separator: " ")
        }

        var fullGivenFirst: String { given.isEmpty ? last : "\(given) \(last)" }
    }

    // MARK: In-text

    static func inText(_ sources: [CitationSource], style: CitationStyle, numbers: [String: Int]) -> String {
        guard !sources.isEmpty else { return "[?]" }
        switch style {
        case .ieee:
            return sources.map { "[\(numbers[$0.id] ?? 0)]" }.joined(separator: ", ")
        case .apa:
            return "(" + sources.map { "\(authorShort($0, conjunction: "&")), \(year($0))" }.joined(separator: "; ") + ")"
        case .mla:
            return "(" + sources.map { source in
                let author = authorShort(source, conjunction: "and")
                return source.pages.isEmpty ? author : "\(author) \(source.pages)"
            }.joined(separator: "; ") + ")"
        case .chicago:
            return "(" + sources.map { "\(authorShort($0, conjunction: "and")) \(year($0))" }.joined(separator: "; ") + ")"
        }
    }

    private static func year(_ source: CitationSource) -> String { source.year.isEmpty ? "n.d." : source.year }

    private static func authorShort(_ source: CitationSource, conjunction: String) -> String {
        let names = source.authors.map(Name.init)
        switch names.count {
        case 0: return shortTitle(source)
        case 1: return names[0].last
        case 2: return "\(names[0].last) \(conjunction) \(names[1].last)"
        default: return "\(names[0].last) et al."
        }
    }

    private static func shortTitle(_ source: CitationSource) -> String {
        let words = source.title.split(separator: " ").prefix(4).joined(separator: " ")
        return words.isEmpty ? "Anonymous" : "“\(words)”"
    }

    // MARK: Bibliography

    /// Segments of an entry; italic segments are titles of containers or books.
    typealias Segment = (text: String, italic: Bool)

    static func entry(_ source: CitationSource, style: CitationStyle, number: Int) -> [Segment] {
        switch style {
        case .apa: return apa(source)
        case .mla: return mla(source)
        case .chicago: return chicago(source)
        case .ieee: return ieee(source, number: number)
        }
    }

    static func attributedEntry(_ source: CitationSource, style: CitationStyle, number: Int, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = attributes[.font] as? NSFont ?? StyleCatalog.bodyFont
        for segment in entry(source, style: style, number: number) {
            var segmentAttributes = attributes
            if segment.italic { segmentAttributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            result.append(NSAttributedString(string: segment.text, attributes: segmentAttributes))
        }
        return result
    }

    /// Sort order for the reference list.
    static func sorted(_ sources: [CitationSource], style: CitationStyle, numbers: [String: Int]) -> [CitationSource] {
        if style == .ieee {
            return sources.sorted { (numbers[$0.id] ?? .max) < (numbers[$1.id] ?? .max) }
        }
        return sources.sorted {
            let a = ($0.authors.first.map { Name($0).last } ?? $0.title).lowercased()
            let b = ($1.authors.first.map { Name($0).last } ?? $1.title).lowercased()
            return a == b ? $0.year < $1.year : a < b
        }
    }

    private static func joined(_ items: [String], conjunction: String, serialComma: Bool = true) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(conjunction) \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + (serialComma ? ", " : " ") + "\(conjunction) \(items.last!)"
        }
    }

    private static func ensurePeriod(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".?!".contains(last) ? text : text + "."
    }

    private static func link(_ source: CitationSource) -> String {
        if !source.doi.isEmpty { return source.doi.hasPrefix("http") ? source.doi : "https://doi.org/\(source.doi)" }
        return source.url
    }

    private static func apa(_ source: CitationSource) -> [Segment] {
        let names = source.authors.map(Name.init).map { "\($0.last), \($0.initials)".trimmingCharacters(in: .whitespaces) }
        let authors = names.isEmpty ? "" : joined(names, conjunction: "&") + " "
        var segments: [Segment] = [("\(authors)(\(year(source))). ", false)]
        switch source.type {
        case .journalArticle, .conference:
            segments.append((ensurePeriod(source.title) + " ", false))
            if !source.containerTitle.isEmpty {
                segments.append((source.containerTitle, true))
                if !source.volume.isEmpty { segments.append((", ", false)); segments.append((source.volume, true)) }
                if !source.issue.isEmpty { segments.append(("(\(source.issue))", false)) }
                if !source.pages.isEmpty { segments.append((", \(source.pages)", false)) }
                segments.append((". ", false))
            }
        case .chapter:
            segments.append((ensurePeriod(source.title) + " In ", false))
            segments.append((source.containerTitle, true))
            if !source.pages.isEmpty { segments.append((" (pp. \(source.pages))", false)) }
            segments.append((". \(source.publisher.isEmpty ? "" : ensurePeriod(source.publisher) + " ")", false))
        case .website:
            segments.append((ensurePeriod(source.title), true))
            segments.append((" " + (source.containerTitle.isEmpty ? "" : ensurePeriod(source.containerTitle) + " "), false))
        case .book, .report:
            segments.append((source.title, true))
            if !source.edition.isEmpty { segments.append((" (\(source.edition) ed.)", false)) }
            segments.append((". " + (source.publisher.isEmpty ? "" : ensurePeriod(source.publisher) + " "), false))
        }
        let url = link(source)
        if !url.isEmpty { segments.append((url, false)) }
        return segments
    }

    private static func mla(_ source: CitationSource) -> [Segment] {
        let names = source.authors.map(Name.init)
        var authors = ""
        if let first = names.first {
            authors = "\(first.last), \(first.given)"
            if names.count == 2 { authors += ", and \(names[1].fullGivenFirst)" }
            if names.count > 2 { authors += ", et al" }
            authors = ensurePeriod(authors) + " "
        }
        var segments: [Segment] = [(authors, false)]
        switch source.type {
        case .journalArticle, .conference, .chapter, .website:
            segments.append(("“\(ensurePeriod(source.title))” ", false))
            if !source.containerTitle.isEmpty { segments.append((source.containerTitle, true)); segments.append((", ", false)) }
            var details: [String] = []
            if !source.volume.isEmpty { details.append("vol. \(source.volume)") }
            if !source.issue.isEmpty { details.append("no. \(source.issue)") }
            if !source.publisher.isEmpty && source.type != .journalArticle { details.append(source.publisher) }
            if !source.year.isEmpty { details.append(source.year) }
            if !source.pages.isEmpty { details.append("pp. \(source.pages)") }
            if !source.url.isEmpty { details.append(source.url) }
            segments.append((ensurePeriod(details.joined(separator: ", ")), false))
        case .book, .report:
            segments.append((ensurePeriod(source.title), true))
            let details = [source.publisher, source.year].filter { !$0.isEmpty }.joined(separator: ", ")
            if !details.isEmpty { segments.append((" " + ensurePeriod(details), false)) }
        }
        return segments
    }

    private static func chicago(_ source: CitationSource) -> [Segment] {
        let names = source.authors.map(Name.init)
        var list: [String] = []
        for (index, name) in names.enumerated() {
            list.append(index == 0 ? "\(name.last), \(name.given)" : name.fullGivenFirst)
        }
        let authors = list.isEmpty ? "" : ensurePeriod(joined(list, conjunction: "and")) + " "
        var segments: [Segment] = [("\(authors)\(year(source)). ", false)]
        switch source.type {
        case .journalArticle, .conference, .chapter, .website:
            segments.append(("“\(ensurePeriod(source.title))” ", false))
            if !source.containerTitle.isEmpty {
                segments.append((source.containerTitle, true))
                var tail = ""
                if !source.volume.isEmpty { tail += " \(source.volume)" }
                if !source.issue.isEmpty { tail += " (\(source.issue))" }
                if !source.pages.isEmpty { tail += ": \(source.pages)" }
                segments.append((tail + ". ", false))
            }
        case .book, .report:
            segments.append((ensurePeriod(source.title), true))
            let publisher = [source.place, source.publisher].filter { !$0.isEmpty }.joined(separator: ": ")
            if !publisher.isEmpty { segments.append((" " + ensurePeriod(publisher) + " ", false)) }
        }
        let url = link(source)
        if !url.isEmpty { segments.append((ensurePeriod(url), false)) }
        return segments
    }

    private static func ieee(_ source: CitationSource, number: Int) -> [Segment] {
        let names = source.authors.map(Name.init).map { "\($0.initials) \($0.last)".trimmingCharacters(in: .whitespaces) }
        let authors = names.count > 6 ? "\(names[0]) et al." : joined(names, conjunction: "and")
        var segments: [Segment] = [("[\(number)]\t", false)]
        if !authors.isEmpty { segments.append(("\(authors), ", false)) }
        switch source.type {
        case .journalArticle, .conference, .chapter:
            segments.append(("“\(source.title),” ", false))
            if !source.containerTitle.isEmpty { segments.append((source.containerTitle, true)) }
            var details: [String] = []
            if !source.volume.isEmpty { details.append("vol. \(source.volume)") }
            if !source.issue.isEmpty { details.append("no. \(source.issue)") }
            if !source.pages.isEmpty { details.append("pp. \(source.pages)") }
            if !source.year.isEmpty { details.append(source.year) }
            segments.append(((details.isEmpty ? "" : ", ") + ensurePeriod(details.joined(separator: ", ")), false))
        case .website:
            segments.append(("“\(source.title).” ", false))
            if !source.containerTitle.isEmpty { segments.append((source.containerTitle + ". ", true)) }
            if !source.url.isEmpty { segments.append(("[Online]. Available: \(source.url)", false)) }
        case .book, .report:
            segments.append((source.title, true))
            let publisher = [source.place, source.publisher].filter { !$0.isEmpty }.joined(separator: ": ")
            segments.append((". " + ensurePeriod([publisher, source.year].filter { !$0.isEmpty }.joined(separator: ", ")), false))
        }
        return segments
    }
}
