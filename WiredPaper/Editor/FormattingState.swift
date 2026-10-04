import AppKit

enum ListKind: String, CaseIterable {
    case bullet, numbered

    var markerFormat: NSTextList.MarkerFormat {
        switch self {
        case .bullet: .disc
        case .numbered: NSTextList.MarkerFormat(rawValue: "{decimal}.")
        }
    }

    init?(markerFormat: NSTextList.MarkerFormat) {
        let raw = markerFormat.rawValue
        if raw.contains("decimal") || raw.contains("alpha") || raw.contains("roman") {
            self = .numbered
        } else if raw.contains("disc") || raw.contains("circle") || raw.contains("square")
                    || raw.contains("hyphen") || raw.contains("check") || raw.contains("diamond") || raw.contains("box") {
            self = .bullet
        } else {
            return nil
        }
    }
}

struct LineSpacingOption: Identifiable {
    let multiple: CGFloat
    var id: Int { tag }
    var tag: Int { Int((multiple * 100).rounded()) }
    var title: String {
        multiple == multiple.rounded() ? String(format: "%.1f", multiple) : String(format: "%g", multiple)
    }

    static let all: [LineSpacingOption] = [1.0, 1.15, 1.5, 2.0, 2.5, 3.0].map(LineSpacingOption.init(multiple:))
}

/// Formatting at the insertion point or the start of the selection, used to
/// reflect state in the format bar and menu check marks.
struct FormattingState: Equatable {
    var fontFamily = "Helvetica Neue"
    var fontSize: CGFloat = 12
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStruckThrough = false
    var textColor: NSColor?
    var highlightColor: NSColor?
    var alignment: NSTextAlignment = .natural
    var lineHeightMultiple: CGFloat = 1
    var listKind: ListKind?
    var styleID = ParagraphStyleKind.normal.rawValue
    var styleName = "Normal"
    var isInTable = false
    var hasLink = false
    var isAllCaps = false
    var isSmallCaps = false
    var isHidden = false
    var isDoubleUnderline = false
    var isSuperscript = false
    var isSubscript = false
    var paragraphFlags = Set<String>()

    var styleKind: ParagraphStyleKind? { ParagraphStyleKind(rawValue: styleID) }

    /// Natural alignment renders as left in left-to-right text.
    var effectiveAlignment: NSTextAlignment {
        alignment == .natural ? .left : alignment
    }
}

/// Paragraph measurements shown in the Paragraph sheet (all in points).
struct ParagraphSettings: Equatable {
    var alignment: NSTextAlignment = .left
    var leftIndent: CGFloat = 0
    var rightIndent: CGFloat = 0
    /// Offset of the first line relative to the left indent (negative = hanging).
    var firstLineOffset: CGFloat = 0
    var spacingBefore: CGFloat = 0
    var spacingAfter: CGFloat = 0
    var lineHeightMultiple: CGFloat = 1

    init() {}

    init(_ style: NSParagraphStyle) {
        alignment = style.alignment == .natural ? .left : style.alignment
        leftIndent = style.headIndent
        rightIndent = style.tailIndent <= 0 ? -style.tailIndent : 0
        firstLineOffset = style.firstLineHeadIndent - style.headIndent
        spacingBefore = style.paragraphSpacingBefore
        spacingAfter = style.paragraphSpacing
        lineHeightMultiple = style.lineHeightMultiple == 0 ? 1 : style.lineHeightMultiple
    }

    func apply(to style: NSMutableParagraphStyle) {
        style.alignment = alignment
        style.headIndent = max(leftIndent, 0)
        style.firstLineHeadIndent = max(leftIndent + firstLineOffset, 0)
        style.tailIndent = -max(rightIndent, 0)
        style.paragraphSpacingBefore = max(spacingBefore, 0)
        style.paragraphSpacing = max(spacingAfter, 0)
        style.lineHeightMultiple = max(lineHeightMultiple, 0.5)
    }
}
