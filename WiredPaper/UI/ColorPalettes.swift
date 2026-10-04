import AppKit
import SwiftUI

struct NamedColor {
    let name: String
    let color: NSColor
}

enum ColorPalettes {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static let neutrals: [UInt32] = [0x000000, 0x262626, 0x404040, 0x595959, 0x7F7F7F, 0xA6A6A6, 0xBFBFBF, 0xD9D9D9, 0xF2F2F2, 0xFFFFFF]
    private static let hues: [UInt32] = [0x9C1C1C, 0xD32F2F, 0xE8710A, 0xE0A100, 0x2E8B57, 0x13787F, 0x1F63C6, 0x1B3A6B, 0x6A3FA0, 0xB0307A]

    /// Rows of swatches for the text color popover.
    static let textGrid: [[NSColor]] = {
        let base = hues.map(hex)
        return [
            neutrals.map(hex),
            base,
            base.map { $0.blended(withFraction: 0.5, of: .white) ?? $0 },
            base.map { $0.blended(withFraction: 0.35, of: .black) ?? $0 },
        ]
    }()

    static let highlightGrid: [[NSColor]] = [
        [0xFFF176, 0xB9F6CA, 0x84FFFF, 0xFF9ED8, 0xAECBFA].map(hex),
        [0xFFD180, 0xFF8A80, 0xD7CCFF, 0xC8E6C9, 0xDDDDDD].map(hex),
    ]

    static let namedTextColors: [NamedColor] = [
        NamedColor(name: "Black", color: hex(0x000000)),
        NamedColor(name: "Dark Gray", color: hex(0x404040)),
        NamedColor(name: "Gray", color: hex(0x7F7F7F)),
        NamedColor(name: "Red", color: hex(0xD32F2F)),
        NamedColor(name: "Orange", color: hex(0xE8710A)),
        NamedColor(name: "Gold", color: hex(0xE0A100)),
        NamedColor(name: "Green", color: hex(0x2E8B57)),
        NamedColor(name: "Teal", color: hex(0x13787F)),
        NamedColor(name: "Blue", color: hex(0x1F63C6)),
        NamedColor(name: "Navy", color: hex(0x1B3A6B)),
        NamedColor(name: "Purple", color: hex(0x6A3FA0)),
    ]

    static let namedHighlightColors: [NamedColor] = [
        NamedColor(name: "Yellow", color: hex(0xFFF176)),
        NamedColor(name: "Green", color: hex(0xB9F6CA)),
        NamedColor(name: "Aqua", color: hex(0x84FFFF)),
        NamedColor(name: "Pink", color: hex(0xFF9ED8)),
        NamedColor(name: "Blue", color: hex(0xAECBFA)),
        NamedColor(name: "Orange", color: hex(0xFFD180)),
        NamedColor(name: "Gray", color: hex(0xDDDDDD)),
    ]

    static let defaultTextColor = hex(0xD32F2F)
    static let defaultHighlightColor = hex(0xFFF176)
}

/// Routes the shared color panel's selection to highlight instead of text color.
final class HighlightColorRelay: NSObject {
    static let shared = HighlightColorRelay()
    private weak var editor: EditorController?

    func begin(for editor: EditorController) {
        self.editor = editor
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        editor?.setHighlight(panel.color)
    }

    /// Restores the default behavior (color changes go to the focused text view).
    static func beginTextColor(for editor: EditorController) {
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        editor.focusTextView()
        panel.orderFront(nil)
    }
}

struct ColorPaletteView: View {
    enum Kind { case text, highlight }

    let kind: Kind
    let onPick: (NSColor?) -> Void
    let onMore: () -> Void

    private var grid: [[NSColor]] { kind == .text ? ColorPalettes.textGrid : ColorPalettes.highlightGrid }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onPick(nil)
            } label: {
                Label(kind == .text ? "Automatic" : "No Highlight",
                      systemImage: kind == .text ? "circle.lefthalf.filled" : "nosign")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                ForEach(grid.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(grid[row].indices, id: \.self) { column in
                            SwatchButton(color: grid[row][column]) { onPick(grid[row][column]) }
                        }
                    }
                }
            }

            Divider()

            Button {
                onMore()
            } label: {
                Label("More Colors…", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .padding(12)
        .fixedSize()
    }
}

private struct SwatchButton: View {
    let color: NSColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(hovering ? Theme.accentColor : Color.primary.opacity(0.18), lineWidth: hovering ? 2 : 0.5)
                )
                .scaleEffect(hovering ? 1.12 : 1)
                .animation(.easeOut(duration: 0.1), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
