import AppKit

extension NSAttributedString.Key {
    /// Id of the paragraph style (Normal, Heading 1, a custom style…) applied to a run.
    static let wpParagraphStyle = NSAttributedString.Key("WPParagraphStyle")
}

/// The built-in paragraph styles. Their raw values are the style ids used in
/// documents; custom styles use generated ids.
enum ParagraphStyleKind: String, CaseIterable, Identifiable {
    case normal, noSpacing, title, subtitle
    case heading1, heading2, heading3, heading4, heading5, heading6, heading7, heading8, heading9
    case quote, caption, code

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .noSpacing: "No Spacing"
        case .title: "Title"
        case .subtitle: "Subtitle"
        case .quote: "Quote"
        case .caption: "Caption"
        case .code: "Code"
        default: "Heading \(headingLevel ?? 0)"
        }
    }

    var headingLevel: Int? {
        guard rawValue.hasPrefix("heading") else { return nil }
        return Int(rawValue.dropFirst("heading".count))
    }

    static func heading(_ level: Int) -> ParagraphStyleKind {
        ParagraphStyleKind(rawValue: "heading\(min(max(level, 1), 9))") ?? .heading1
    }

    /// ⌥⌘ digit in the Format ▸ Styles menu.
    var keyEquivalent: String? {
        if self == .normal { return "0" }
        return headingLevel.map(String.init)
    }
}

enum FontResolver {
    static func font(family: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let manager = NSFontManager.shared
        if let font = manager.font(withFamily: family, traits: traits, weight: 5, size: size) {
            return font
        }
        if let base = manager.font(withFamily: family, traits: [], weight: 5, size: size) {
            return manager.convert(base, toHaveTrait: traits)
        }
        let system = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        return italic ? manager.convert(system, toHaveTrait: .italicFontMask) : system
    }
}

/// Convenience access to the default style sheet (new documents, templates,
/// imports). Documents with their own theme or edited styles use
/// `WiredPaperDocument.styleSheet` instead.
enum StyleCatalog {
    static var standard: StyleSheet { StyleSheet.standard }
    static var bodyFont: NSFont { standard.font(for: ParagraphStyleKind.normal.rawValue) }

    static func font(for kind: ParagraphStyleKind) -> NSFont { standard.font(for: kind.rawValue) }
    static func color(for kind: ParagraphStyleKind) -> NSColor { standard.color(for: kind.rawValue) }
    static func paragraphStyle(for kind: ParagraphStyleKind) -> NSParagraphStyle { standard.paragraphStyle(for: kind.rawValue) }
    static func attributes(for kind: ParagraphStyleKind) -> [NSAttributedString.Key: Any] { standard.attributes(for: kind.rawValue) }
}
