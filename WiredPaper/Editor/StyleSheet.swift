import AppKit

/// Theme fonts and colors. Styles refer to them symbolically ("+heading",
/// "+body", "+accent"…), so switching the theme restyles the whole document.
struct DocumentTheme: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var headingFont: String
    var bodyFont: String
    var headingColorHex: String
    var secondaryColorHex: String
    var accentColorHex: String
    var textColorHex = "#000000"

    init(id: String, name: String, headingFont: String, bodyFont: String, headingColorHex: String, secondaryColorHex: String, accentColorHex: String) {
        self.id = id
        self.name = name
        self.headingFont = headingFont
        self.bodyFont = bodyFont
        self.headingColorHex = headingColorHex
        self.secondaryColorHex = secondaryColorHex
        self.accentColorHex = accentColorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DocumentTheme.paper(bodyFont: "Helvetica Neue")
        id = c.value(.id, default: fallback.id)
        name = c.value(.name, default: fallback.name)
        headingFont = c.value(.headingFont, default: fallback.headingFont)
        bodyFont = c.value(.bodyFont, default: fallback.bodyFont)
        headingColorHex = c.value(.headingColorHex, default: fallback.headingColorHex)
        secondaryColorHex = c.value(.secondaryColorHex, default: fallback.secondaryColorHex)
        accentColorHex = c.value(.accentColorHex, default: fallback.accentColorHex)
        textColorHex = c.value(.textColorHex, default: "#000000")
    }

    var headingColor: NSColor { NSColor(hex: headingColorHex) ?? .black }
    var secondaryColor: NSColor { NSColor(hex: secondaryColorHex) ?? .darkGray }
    var accentColor: NSColor { NSColor(hex: accentColorHex) ?? .systemTeal }
    var textColor: NSColor { NSColor(hex: textColorHex) ?? .black }

    static func paper(bodyFont: String) -> DocumentTheme {
        DocumentTheme(id: "paper", name: "Wired Paper", headingFont: "Helvetica Neue", bodyFont: bodyFont,
                      headingColorHex: "#124A59", secondaryColorHex: "#5C636A", accentColorHex: "#13787F")
    }

    static var presets: [DocumentTheme] {
        [
            .paper(bodyFont: AppSettings.shared.defaultFontFamily),
            DocumentTheme(id: "classic", name: "Classic", headingFont: "Georgia", bodyFont: "Georgia",
                          headingColorHex: "#1F3A5F", secondaryColorHex: "#555B61", accentColorHex: "#8B1E3F"),
            DocumentTheme(id: "modern", name: "Modern", headingFont: "Avenir Next", bodyFont: "Avenir Next",
                          headingColorHex: "#2B2D42", secondaryColorHex: "#6C757D", accentColorHex: "#5A4FCF"),
            DocumentTheme(id: "elegant", name: "Elegant", headingFont: "Didot", bodyFont: "Baskerville",
                          headingColorHex: "#3B2F2F", secondaryColorHex: "#6D5D5D", accentColorHex: "#A0522D"),
            DocumentTheme(id: "technical", name: "Technical", headingFont: "Menlo", bodyFont: "Helvetica Neue",
                          headingColorHex: "#1E293B", secondaryColorHex: "#475569", accentColorHex: "#0284C7"),
            DocumentTheme(id: "fresh", name: "Fresh", headingFont: "Gill Sans", bodyFont: "Optima",
                          headingColorHex: "#1B5E20", secondaryColorHex: "#4E6E58", accentColorHex: "#2E7D32"),
        ]
    }
}

/// A paragraph style. Unset (nil) properties inherit from `basedOn`, ending at
/// Normal. Built-in styles can be edited per document; custom styles are added.
struct StyleDefinition: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var basedOn: String?
    var isBuiltIn = false
    /// A family name, or "+heading" / "+body" for the theme fonts.
    var fontFamily: String?
    var fontSize: CGFloat?
    /// Size relative to the body size (used when fontSize is nil).
    var sizeScale: CGFloat?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    /// A hex color, or "+text" / "+heading" / "+secondary" / "+accent".
    var color: String?
    /// "left", "center", "right" or "justified".
    var alignment: String?
    var spaceBefore: CGFloat?
    var spaceAfter: CGFloat?
    var lineHeight: CGFloat?
    var leftIndent: CGFloat?
    var rightIndent: CGFloat?
    var firstLineIndent: CGFloat?
    var keepWithNext: Bool?
    var outlineLevel: Int?
    /// Style applied to the paragraph that follows when pressing Return.
    var nextStyle: String?

    init(id: String, name: String, basedOn: String? = "normal", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.basedOn = basedOn
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.value(.name, default: id)
        basedOn = c.value(.basedOn, default: nil)
        isBuiltIn = c.value(.isBuiltIn, default: false)
        fontFamily = c.value(.fontFamily, default: nil)
        fontSize = c.value(.fontSize, default: nil)
        sizeScale = c.value(.sizeScale, default: nil)
        bold = c.value(.bold, default: nil)
        italic = c.value(.italic, default: nil)
        underline = c.value(.underline, default: nil)
        color = c.value(.color, default: nil)
        alignment = c.value(.alignment, default: nil)
        spaceBefore = c.value(.spaceBefore, default: nil)
        spaceAfter = c.value(.spaceAfter, default: nil)
        lineHeight = c.value(.lineHeight, default: nil)
        leftIndent = c.value(.leftIndent, default: nil)
        rightIndent = c.value(.rightIndent, default: nil)
        firstLineIndent = c.value(.firstLineIndent, default: nil)
        keepWithNext = c.value(.keepWithNext, default: nil)
        outlineLevel = c.value(.outlineLevel, default: nil)
        nextStyle = c.value(.nextStyle, default: nil)
    }

    /// Returns a copy with every property that `other` sets applied on top.
    func merging(_ other: StyleDefinition) -> StyleDefinition {
        var result = self
        result.fontFamily = other.fontFamily ?? fontFamily
        if other.fontSize != nil { result.fontSize = other.fontSize; result.sizeScale = nil }
        if other.sizeScale != nil { result.sizeScale = other.sizeScale; if other.fontSize == nil { result.fontSize = nil } }
        result.bold = other.bold ?? bold
        result.italic = other.italic ?? italic
        result.underline = other.underline ?? underline
        result.color = other.color ?? color
        result.alignment = other.alignment ?? alignment
        result.spaceBefore = other.spaceBefore ?? spaceBefore
        result.spaceAfter = other.spaceAfter ?? spaceAfter
        result.lineHeight = other.lineHeight ?? lineHeight
        result.leftIndent = other.leftIndent ?? leftIndent
        result.rightIndent = other.rightIndent ?? rightIndent
        result.firstLineIndent = other.firstLineIndent ?? firstLineIndent
        result.keepWithNext = other.keepWithNext ?? keepWithNext
        result.outlineLevel = other.outlineLevel ?? outlineLevel
        result.nextStyle = other.nextStyle ?? nextStyle
        return result
    }
}

struct ResolvedStyle {
    let font: NSFont
    let color: NSColor
    let paragraph: NSParagraphStyle
    let underline: Bool
    let keepWithNext: Bool
    let outlineLevel: Int?
}

/// Resolves styles for one document: built-in definitions, the document's
/// edits and custom styles, and the theme.
final class StyleSheet {
    let theme: DocumentTheme
    let bodySize: CGFloat
    private var definitions: [String: StyleDefinition] = [:]
    private(set) var orderedIDs: [String] = []
    private var cache: [String: ResolvedStyle] = [:]

    static var standard: StyleSheet {
        let settings = AppSettings.shared
        return StyleSheet(theme: .paper(bodyFont: settings.defaultFontFamily), overrides: [], bodySize: CGFloat(settings.defaultFontSize))
    }

    init(theme: DocumentTheme, overrides: [StyleDefinition], bodySize: CGFloat) {
        self.theme = theme
        self.bodySize = bodySize
        for definition in Self.builtIns {
            definitions[definition.id] = definition
            orderedIDs.append(definition.id)
        }
        for override in overrides {
            if definitions[override.id] == nil { orderedIDs.append(override.id) }
            definitions[override.id] = override
        }
    }

    var allStyles: [StyleDefinition] { orderedIDs.compactMap { definitions[$0] } }
    var customStyles: [StyleDefinition] { allStyles.filter { !$0.isBuiltIn } }

    func definition(_ id: String) -> StyleDefinition? { definitions[id] }
    func displayName(_ id: String) -> String { definitions[id]?.name ?? id }

    // MARK: Resolution

    func resolve(_ id: String) -> ResolvedStyle {
        if let cached = cache[id] { return cached }

        var chain: [StyleDefinition] = []
        var current: String? = definitions[id] == nil ? "normal" : id
        var visited = Set<String>()
        while let next = current, let definition = definitions[next], !visited.contains(next), chain.count < 12 {
            chain.insert(definition, at: 0)
            visited.insert(next)
            current = definition.basedOn
        }
        var merged = StyleDefinition(id: id, name: id, basedOn: nil)
        for definition in chain { merged = merged.merging(definition) }

        let size = merged.fontSize ?? (merged.sizeScale ?? 1) * bodySize
        let font = FontResolver.font(
            family: resolveFamily(merged.fontFamily),
            size: max(size.rounded(), 1),
            bold: merged.bold ?? false,
            italic: merged.italic ?? false
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = 36
        paragraph.tabStops = []
        paragraph.alignment = Self.alignment(merged.alignment)
        paragraph.paragraphSpacingBefore = merged.spaceBefore ?? 0
        paragraph.paragraphSpacing = merged.spaceAfter ?? 0
        paragraph.lineHeightMultiple = merged.lineHeight ?? 1
        let left = merged.leftIndent ?? 0
        paragraph.headIndent = left
        paragraph.firstLineHeadIndent = max(left + (merged.firstLineIndent ?? 0), 0)
        paragraph.tailIndent = -(merged.rightIndent ?? 0)

        let resolved = ResolvedStyle(
            font: font,
            color: resolveColor(merged.color),
            paragraph: paragraph,
            underline: merged.underline ?? false,
            keepWithNext: merged.keepWithNext ?? false,
            outlineLevel: merged.outlineLevel
        )
        cache[id] = resolved
        return resolved
    }

    func font(for id: String) -> NSFont { resolve(id).font }
    func color(for id: String) -> NSColor { resolve(id).color }
    func paragraphStyle(for id: String) -> NSParagraphStyle { resolve(id).paragraph }
    func outlineLevel(for id: String) -> Int? { resolve(id).outlineLevel }
    func nextStyleID(for id: String) -> String? { definitions[id]?.nextStyle }

    func attributes(for id: String) -> [NSAttributedString.Key: Any] {
        let style = resolve(id)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.color,
            .paragraphStyle: style.paragraph,
            .wpParagraphStyle: definitions[id] == nil ? "normal" : id,
        ]
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.keepWithNext { attributes[.wpParaFlags] = ParagraphFlags.keepWithNext }
        return attributes
    }

    func resolveFamily(_ token: String?) -> String {
        switch token {
        case nil, "+body": theme.bodyFont
        case "+heading": theme.headingFont
        case let family?: family
        }
    }

    func resolveColor(_ token: String?) -> NSColor {
        switch token {
        case nil, "+text": theme.textColor
        case "+heading": theme.headingColor
        case "+secondary": theme.secondaryColor
        case "+accent": theme.accentColor
        case let hex?: NSColor(hex: hex) ?? theme.textColor
        }
    }

    static func alignment(_ name: String?) -> NSTextAlignment {
        switch name {
        case "center": .center
        case "right": .right
        case "justified": .justified
        default: .natural
        }
    }

    static func alignmentName(_ alignment: NSTextAlignment) -> String? {
        switch alignment {
        case .center: "center"
        case .right: "right"
        case .justified: "justified"
        default: nil
        }
    }

    // MARK: Built-in definitions

    static let builtIns: [StyleDefinition] = {
        func style(_ kind: ParagraphStyleKind, basedOn: String? = "normal", _ configure: (inout StyleDefinition) -> Void) -> StyleDefinition {
            var definition = StyleDefinition(id: kind.rawValue, name: kind.displayName, basedOn: basedOn, isBuiltIn: true)
            configure(&definition)
            return definition
        }
        func heading(_ level: Int, scale: CGFloat, bold: Bool, italic: Bool, color: String, before: CGFloat, after: CGFloat) -> StyleDefinition {
            style(.heading(level)) {
                $0.fontFamily = "+heading"
                $0.sizeScale = scale
                $0.bold = bold
                $0.italic = italic
                $0.color = color
                $0.spaceBefore = before
                $0.spaceAfter = after
                $0.lineHeight = 1
                $0.keepWithNext = true
                $0.outlineLevel = level
                $0.nextStyle = "normal"
            }
        }
        return [
            style(.normal, basedOn: nil) {
                $0.fontFamily = "+body"
                $0.sizeScale = 1
                $0.color = "+text"
                $0.lineHeight = 1.15
                $0.spaceAfter = 8
            },
            style(.noSpacing) { $0.lineHeight = 1; $0.spaceAfter = 0 },
            style(.title) {
                $0.fontFamily = "+heading"; $0.sizeScale = 2.3; $0.bold = true; $0.color = "+heading"
                $0.lineHeight = 1; $0.spaceAfter = 4; $0.nextStyle = "subtitle"
            },
            style(.subtitle) {
                $0.fontFamily = "+heading"; $0.sizeScale = 1.25; $0.color = "+secondary"
                $0.lineHeight = 1; $0.spaceAfter = 16; $0.nextStyle = "normal"
            },
            heading(1, scale: 1.5, bold: true, italic: false, color: "+heading", before: 18, after: 6),
            heading(2, scale: 1.25, bold: true, italic: false, color: "+heading", before: 14, after: 4),
            heading(3, scale: 1.08, bold: true, italic: false, color: "+secondary", before: 12, after: 4),
            heading(4, scale: 1, bold: true, italic: true, color: "+heading", before: 10, after: 3),
            heading(5, scale: 1, bold: true, italic: false, color: "+secondary", before: 10, after: 2),
            heading(6, scale: 1, bold: false, italic: true, color: "+secondary", before: 8, after: 2),
            heading(7, scale: 0.95, bold: true, italic: false, color: "+text", before: 8, after: 2),
            heading(8, scale: 0.92, bold: false, italic: true, color: "+text", before: 6, after: 2),
            heading(9, scale: 0.9, bold: false, italic: true, color: "+secondary", before: 6, after: 2),
            style(.quote) {
                $0.italic = true; $0.color = "+secondary"
                $0.leftIndent = 36; $0.rightIndent = 36; $0.spaceBefore = 4
            },
            style(.caption) {
                $0.sizeScale = 0.85; $0.italic = true; $0.color = "+secondary"
                $0.lineHeight = 1; $0.spaceAfter = 10
            },
            style(.code) {
                $0.fontFamily = "Menlo"; $0.sizeScale = 0.9; $0.lineHeight = 1.1; $0.spaceAfter = 0
            },
        ]
    }()
}
