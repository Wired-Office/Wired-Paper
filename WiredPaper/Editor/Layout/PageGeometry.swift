import AppKit

/// Where text goes on a sheet: paper, margins, gutter and columns.
struct PageGeometry: Equatable {
    var setup: PageSetup
    var columns = 1
    var columnSpacing: CGFloat = 18
    var gutter: CGFloat = 0

    init(setup: PageSetup, decoration: PageDecoration = PageDecoration()) {
        self.setup = setup
        columns = min(max(decoration.columns, 1), 6)
        columnSpacing = max(decoration.columnSpacing, 0)
        gutter = max(decoration.gutter, 0)
    }

    var paperSize: CGSize { setup.paperSize }
    var margins: Margins { setup.margins }

    /// The text block, in flipped page coordinates.
    var textArea: CGRect {
        let left = margins.left + gutter
        return CGRect(
            x: left,
            y: margins.top,
            width: max(paperSize.width - left - margins.right, 72),
            height: max(paperSize.height - margins.top - margins.bottom, 72)
        )
    }

    func columnRects() -> [CGRect] {
        let area = textArea
        let count = CGFloat(columns)
        let width = max((area.width - columnSpacing * (count - 1)) / count, 36)
        return (0..<columns).map { index in
            CGRect(x: area.minX + CGFloat(index) * (width + columnSpacing), y: area.minY, width: width, height: area.height)
        }
    }

    var columnWidth: CGFloat { columnRects().first?.width ?? textArea.width }

    /// Largest size an inline image may occupy so it always fits in a column.
    var maxAttachmentSize: CGSize {
        CGSize(width: columnWidth - 10, height: textArea.height * 0.9)
    }
}
