import AppKit

struct Margins: Codable, Equatable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    static let oneInch = Margins(top: 72, left: 72, bottom: 72, right: 72)
}

enum PaperPreset: String, CaseIterable, Identifiable, Codable {
    case letter, legal, a4, a5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: "US Letter"
        case .legal: "US Legal"
        case .a4: "A4"
        case .a5: "A5"
        }
    }

    var dimensionsDescription: String {
        switch self {
        case .letter: "8.5 × 11 in"
        case .legal: "8.5 × 14 in"
        case .a4: "210 × 297 mm"
        case .a5: "148 × 210 mm"
        }
    }

    /// Portrait size in points.
    var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .legal: CGSize(width: 612, height: 1008)
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .a5: CGSize(width: 419.53, height: 595.28)
        }
    }

    static func matching(_ size: CGSize) -> PaperPreset? {
        let portrait = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))
        return allCases.first { abs($0.size.width - portrait.width) < 2 && abs($0.size.height - portrait.height) < 2 }
    }
}

enum PageOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
}

/// Paper size and margins for a document. Pages on screen, printing and PDF
/// export are all derived from this single value.
struct PageSetup: Codable, Equatable {
    /// Paper size in points, already oriented (landscape means width > height).
    var paperSize: CGSize
    var margins: Margins

    static func standard(_ preset: PaperPreset) -> PageSetup {
        PageSetup(paperSize: preset.size, margins: .oneInch)
    }

    var orientation: PageOrientation {
        paperSize.width > paperSize.height ? .landscape : .portrait
    }

    var contentSize: CGSize {
        CGSize(
            width: max(paperSize.width - margins.left - margins.right, 72),
            height: max(paperSize.height - margins.top - margins.bottom, 72)
        )
    }

    /// Largest size an inline image may occupy so it always fits on a page.
    var maxAttachmentSize: CGSize {
        CGSize(width: contentSize.width - 10, height: contentSize.height * 0.9)
    }

    func oriented(_ orientation: PageOrientation) -> PageSetup {
        guard orientation != self.orientation else { return self }
        var copy = self
        copy.paperSize = CGSize(width: paperSize.height, height: paperSize.width)
        return copy
    }

    var isValid: Bool {
        paperSize.width >= 144 && paperSize.height >= 144
            && [margins.top, margins.left, margins.bottom, margins.right].allSatisfy { $0 >= 0 }
            && paperSize.width - margins.left - margins.right >= 72
            && paperSize.height - margins.top - margins.bottom >= 72
    }

    // MARK: - Cocoa document attributes (RTF, DOCX, ODT…)

    var documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] {
        [
            .paperSize: NSValue(size: paperSize),
            .topMargin: margins.top,
            .leftMargin: margins.left,
            .bottomMargin: margins.bottom,
            .rightMargin: margins.right,
        ]
    }

    init(paperSize: CGSize, margins: Margins) {
        self.paperSize = paperSize
        self.margins = margins
    }

    /// Reads page geometry from the attributes returned by NSAttributedString's
    /// importers. Returns nil when the file doesn't specify a usable page size.
    init?(documentAttributes: NSDictionary?) {
        guard let attributes = documentAttributes,
              let sizeValue = attributes[NSAttributedString.DocumentAttributeKey.paperSize.rawValue] as? NSValue
        else { return nil }

        func margin(_ key: NSAttributedString.DocumentAttributeKey) -> CGFloat {
            (attributes[key.rawValue] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 72
        }

        let candidate = PageSetup(
            paperSize: sizeValue.sizeValue,
            margins: Margins(
                top: margin(.topMargin),
                left: margin(.leftMargin),
                bottom: margin(.bottomMargin),
                right: margin(.rightMargin)
            )
        )
        guard candidate.isValid else { return nil }
        self = candidate
    }

    // MARK: - NSPrintInfo

    func apply(to printInfo: NSPrintInfo) {
        printInfo.orientation = orientation == .landscape ? .landscape : .portrait
        printInfo.paperSize = paperSize
        printInfo.topMargin = margins.top
        printInfo.leftMargin = margins.left
        printInfo.bottomMargin = margins.bottom
        printInfo.rightMargin = margins.right
    }
}
