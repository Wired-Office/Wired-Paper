import AppKit

// MARK: - Tolerant decoding

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `defaultValue` when the key is missing or
    /// malformed, so documents written by other app versions always open.
    func value<T: Decodable>(_ key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? defaultValue
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()), b = Int((rgb.blueComponent * 255).rounded())
        if rgb.alphaComponent < 0.999 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, Int((rgb.alphaComponent * 255).rounded()))
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Properties

struct DocumentProperties: Codable, Equatable {
    var title = ""
    var subject = ""
    var author = ""
    var company = ""
    var keywords = ""
    var category = ""
    var comments = ""
    /// Sensitivity label raw value ("" = none).
    var sensitivity = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.value(.title, default: "")
        subject = c.value(.subject, default: "")
        author = c.value(.author, default: "")
        company = c.value(.company, default: "")
        keywords = c.value(.keywords, default: "")
        category = c.value(.category, default: "")
        comments = c.value(.comments, default: "")
        sensitivity = c.value(.sensitivity, default: "")
    }

    /// Cocoa document attributes understood by the RTF/DOCX/ODT writers.
    var documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] {
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [:]
        if !title.isEmpty { attributes[.title] = title }
        if !subject.isEmpty { attributes[.subject] = subject }
        if !author.isEmpty { attributes[.author] = author }
        if !company.isEmpty { attributes[.company] = company }
        if !keywords.isEmpty {
            attributes[.keywords] = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if !comments.isEmpty { attributes[.comment] = comments }
        return attributes
    }

    init(documentAttributes: NSDictionary?) {
        func string(_ key: NSAttributedString.DocumentAttributeKey) -> String {
            documentAttributes?[key.rawValue] as? String ?? ""
        }
        title = string(.title)
        subject = string(.subject)
        author = string(.author)
        company = string(.company)
        comments = string(.comment)
        keywords = (documentAttributes?[NSAttributedString.DocumentAttributeKey.keywords.rawValue] as? [String])?.joined(separator: ", ") ?? ""
    }
}

// MARK: - Headers & footers

enum PageNumberFormat: String, Codable, CaseIterable, Identifiable {
    case arabic, lowerRoman, upperRoman, lowerLetter, upperLetter
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arabic: "1, 2, 3"
        case .lowerRoman: "i, ii, iii"
        case .upperRoman: "I, II, III"
        case .lowerLetter: "a, b, c"
        case .upperLetter: "A, B, C"
        }
    }

    func format(_ number: Int) -> String {
        switch self {
        case .arabic: return String(number)
        case .lowerRoman: return Self.roman(number).lowercased()
        case .upperRoman: return Self.roman(number)
        case .lowerLetter: return Self.letters(number).lowercased()
        case .upperLetter: return Self.letters(number)
        }
    }

    static func roman(_ number: Int) -> String {
        guard number > 0 else { return String(number) }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = number
        var result = ""
        for (value, symbol) in table {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }

    static func letters(_ number: Int) -> String {
        guard number > 0 else { return String(number) }
        var remaining = number
        var result = ""
        while remaining > 0 {
            remaining -= 1
            result = String(UnicodeScalar(UInt8(65 + remaining % 26))) + result
            remaining /= 26
        }
        return result
    }
}

/// One header or footer: three aligned slots containing text with field tokens
/// such as `{PAGE}`, `{PAGES}`, `{DATE}`, `{TITLE}`.
struct HeaderFooterText: Codable, Equatable {
    var left = ""
    var center = ""
    var right = ""

    var isEmpty: Bool { left.isEmpty && center.isEmpty && right.isEmpty }

    init(left: String = "", center: String = "", right: String = "") {
        self.left = left
        self.center = center
        self.right = right
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = c.value(.left, default: "")
        center = c.value(.center, default: "")
        right = c.value(.right, default: "")
    }
}

struct HeaderFooterSettings: Codable, Equatable {
    var header = HeaderFooterText()
    var footer = HeaderFooterText()
    var firstHeader = HeaderFooterText()
    var firstFooter = HeaderFooterText()
    var evenHeader = HeaderFooterText()
    var evenFooter = HeaderFooterText()
    var differentFirstPage = false
    var differentOddEven = false
    var headerDistance: CGFloat = 36
    var footerDistance: CGFloat = 36
    var fontSize: CGFloat = 9
    var colorHex = "#5C6369"
    var showSeparators = false
    var startingPageNumber = 1
    var numberFormat: PageNumberFormat = .arabic

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = c.value(.header, default: HeaderFooterText())
        footer = c.value(.footer, default: HeaderFooterText())
        firstHeader = c.value(.firstHeader, default: HeaderFooterText())
        firstFooter = c.value(.firstFooter, default: HeaderFooterText())
        evenHeader = c.value(.evenHeader, default: HeaderFooterText())
        evenFooter = c.value(.evenFooter, default: HeaderFooterText())
        differentFirstPage = c.value(.differentFirstPage, default: false)
        differentOddEven = c.value(.differentOddEven, default: false)
        headerDistance = c.value(.headerDistance, default: 36)
        footerDistance = c.value(.footerDistance, default: 36)
        fontSize = c.value(.fontSize, default: 9)
        colorHex = c.value(.colorHex, default: "#5C6369")
        showSeparators = c.value(.showSeparators, default: false)
        startingPageNumber = c.value(.startingPageNumber, default: 1)
        numberFormat = c.value(.numberFormat, default: .arabic)
    }

    var isEmpty: Bool {
        [header, footer, firstHeader, firstFooter, evenHeader, evenFooter].allSatisfy(\.isEmpty)
    }

    /// The header (or footer) for a zero-based page index.
    func content(forPage index: Int, header isHeader: Bool) -> HeaderFooterText {
        if differentFirstPage && index == 0 { return isHeader ? firstHeader : firstFooter }
        let pageNumber = index + startingPageNumber
        if differentOddEven && pageNumber % 2 == 0 { return isHeader ? evenHeader : evenFooter }
        return isHeader ? header : footer
    }
}

// MARK: - Page decoration & layout

enum BorderLineStyle: String, Codable, CaseIterable, Identifiable {
    case single, double, dashed, dotted, thick
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct WatermarkSettings: Codable, Equatable {
    var text = "DRAFT"
    var colorHex = "#9AA3AA"
    var opacity: CGFloat = 0.28
    var diagonal = true
    var fontFamily = "Helvetica Neue"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.value(.text, default: "DRAFT")
        colorHex = c.value(.colorHex, default: "#9AA3AA")
        opacity = c.value(.opacity, default: 0.28)
        diagonal = c.value(.diagonal, default: true)
        fontFamily = c.value(.fontFamily, default: "Helvetica Neue")
    }
}

struct PageBorderSettings: Codable, Equatable {
    var style: BorderLineStyle = .single
    var width: CGFloat = 1
    var colorHex = "#4A5560"
    var inset: CGFloat = 24

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.value(.style, default: .single)
        width = c.value(.width, default: 1)
        colorHex = c.value(.colorHex, default: "#4A5560")
        inset = c.value(.inset, default: 24)
    }
}

struct LineNumberSettings: Codable, Equatable {
    var countBy = 1
    var restartEachPage = true
    var distance: CGFloat = 16

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countBy = max(c.value(.countBy, default: 1), 1)
        restartEachPage = c.value(.restartEachPage, default: true)
        distance = c.value(.distance, default: 16)
    }
}

enum VerticalPageAlignment: String, Codable, CaseIterable, Identifiable {
    case top, center, bottom, justified
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct PageDecoration: Codable, Equatable {
    var columns = 1
    var columnSpacing: CGFloat = 18
    var columnSeparator = false
    var gutter: CGFloat = 0
    var pageColorHex: String?
    var watermark: WatermarkSettings?
    var border: PageBorderSettings?
    var lineNumbers: LineNumberSettings?
    var hyphenation = false
    var widowControl = true
    var verticalAlignment: VerticalPageAlignment = .top

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = min(max(c.value(.columns, default: 1), 1), 6)
        columnSpacing = c.value(.columnSpacing, default: 18)
        columnSeparator = c.value(.columnSeparator, default: false)
        gutter = c.value(.gutter, default: 0)
        pageColorHex = c.value(.pageColorHex, default: nil)
        watermark = c.value(.watermark, default: nil)
        border = c.value(.border, default: nil)
        lineNumbers = c.value(.lineNumbers, default: nil)
        hyphenation = c.value(.hyphenation, default: false)
        widowControl = c.value(.widowControl, default: true)
        verticalAlignment = c.value(.verticalAlignment, default: .top)
    }

    var pageColor: NSColor { pageColorHex.flatMap(NSColor.init(hex:)) ?? .white }
}

// MARK: - Comments

struct CommentReply: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var author: String
    var date = Date()
    var text: String
}

struct CommentThread: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var author: String
    var date = Date()
    var text: String
    var replies: [CommentReply] = []
    var resolved = false
    /// Emoji → people who reacted.
    var reactions: [String: [String]] = [:]

    init(author: String, text: String) {
        self.author = author
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID().uuidString)
        author = c.value(.author, default: "")
        date = c.value(.date, default: Date())
        text = c.value(.text, default: "")
        replies = c.value(.replies, default: [])
        resolved = c.value(.resolved, default: false)
        reactions = c.value(.reactions, default: [:])
    }

    /// Names mentioned with @Name in the thread.
    var mentions: [String] {
        let all = ([text] + replies.map(\.text)).joined(separator: " ")
        return all.split(separator: " ").filter { $0.hasPrefix("@") && $0.count > 1 }.map { String($0.dropFirst()).trimmingCharacters(in: .punctuationCharacters) }
    }
}

// MARK: - Revisions (Track Changes)

enum RevisionKind: String, Codable {
    case insertion, deletion, formatting
}

struct RevisionRecord: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var kind: RevisionKind
    var author: String
    var date = Date()
}

enum MarkupMode: String, Codable, CaseIterable, Identifiable {
    case simple, all, none, original
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simple: "Simple Markup"
        case .all: "All Markup"
        case .none: "No Markup"
        case .original: "Original"
        }
    }
}

struct TrackingSettings: Codable, Equatable {
    var isTracking = false
    var markupMode: MarkupMode = .all

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isTracking = c.value(.isTracking, default: false)
        markupMode = c.value(.markupMode, default: .all)
    }
}

// MARK: - Notes & references

struct FootnoteRecord: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var isEndnote = false
    /// The note's rich text as RTF.
    var rtf: Data

    var text: NSAttributedString {
        (try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))
            ?? NSAttributedString(string: "")
    }

    static func make(_ text: NSAttributedString, isEndnote: Bool) -> FootnoteRecord {
        let data = (try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
        return FootnoteRecord(isEndnote: isEndnote, rtf: data)
    }
}

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case book, journalArticle, website, report, chapter, conference
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .book: "Book"
        case .journalArticle: "Journal Article"
        case .website: "Website"
        case .report: "Report"
        case .chapter: "Book Chapter"
        case .conference: "Conference Paper"
        }
    }
}

struct CitationSource: Codable, Equatable, Identifiable, Hashable {
    var id = UUID().uuidString
    var type: SourceType = .book
    /// "Last, First" per author.
    var authors: [String] = []
    var title = ""
    var containerTitle = ""
    var publisher = ""
    var place = ""
    var year = ""
    var volume = ""
    var issue = ""
    var pages = ""
    var url = ""
    var doi = ""
    var accessed = ""
    var edition = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID().uuidString)
        type = c.value(.type, default: .book)
        authors = c.value(.authors, default: [])
        title = c.value(.title, default: "")
        containerTitle = c.value(.containerTitle, default: "")
        publisher = c.value(.publisher, default: "")
        place = c.value(.place, default: "")
        year = c.value(.year, default: "")
        volume = c.value(.volume, default: "")
        issue = c.value(.issue, default: "")
        pages = c.value(.pages, default: "")
        url = c.value(.url, default: "")
        doi = c.value(.doi, default: "")
        accessed = c.value(.accessed, default: "")
        edition = c.value(.edition, default: "")
    }
}

enum CitationStyle: String, Codable, CaseIterable, Identifiable {
    case apa, mla, chicago, ieee
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apa: "APA (7th)"
        case .mla: "MLA (9th)"
        case .chicago: "Chicago (author-date)"
        case .ieee: "IEEE"
        }
    }
}

// MARK: - Protection & signatures

enum EditingRestriction: String, Codable, CaseIterable, Identifiable {
    case none, readOnly, commentsOnly, trackedChanges, formsOnly
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Restrictions"
        case .readOnly: "Read Only"
        case .commentsOnly: "Comments Only"
        case .trackedChanges: "Tracked Changes Only"
        case .formsOnly: "Filling in Forms Only"
        }
    }
}

struct ProtectionSettings: Codable, Equatable {
    var restriction: EditingRestriction = .none
    /// SHA-256 of salt + password, hex. Protects the restriction, not the content.
    var passwordHash: String?
    var salt: String?
    var markedFinal = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restriction = c.value(.restriction, default: .none)
        passwordHash = c.value(.passwordHash, default: nil)
        salt = c.value(.salt, default: nil)
        markedFinal = c.value(.markedFinal, default: false)
    }
}

struct DigitalSignature: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var signer: String
    var reason: String
    var date = Date()
    /// SHA-256 of the signed content, hex.
    var contentHash: String
    /// P-256 ECDSA signature (DER), base64.
    var signature: String
    /// P-256 public key (raw), base64.
    var publicKey: String
}
