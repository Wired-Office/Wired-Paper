import AppKit
import SwiftUI

// MARK: - Icon buttons

struct FormatButtonStyle: ButtonStyle {
    var isOn = false
    var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Theme.accentColor : Color.primary.opacity(0.85))
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isOn)
    }

    private func background(pressed: Bool) -> Color {
        if pressed { return Color.primary.opacity(0.14) }
        if isOn { return Theme.accentColor.opacity(hovering ? 0.22 : 0.16) }
        if hovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

struct FormatIconButton: View {
    let symbol: String
    let help: String
    var isOn = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle(isOn: isOn, hovering: hovering))
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct FormatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 5)
    }
}

// MARK: - Color split button

struct ColorSplitButton: View {
    let symbol: String
    let help: String
    let color: NSColor
    let kind: ColorPaletteView.Kind
    let onApply: (NSColor?) -> Void
    let onMore: () -> Void

    @State private var showingPalette = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onApply(color)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                    Capsule()
                        .fill(Color(nsColor: color))
                        .frame(width: 16, height: 3.5)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .help(help)

            Button {
                showingPalette.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 12, height: 26)
                    .contentShape(Rectangle())
            }
            .help("\(help) Options")
            .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
                ColorPaletteView(kind: kind, onPick: { picked in
                    showingPalette = false
                    onApply(picked)
                }, onMore: {
                    showingPalette = false
                    onMore()
                })
            }
        }
        .buttonStyle(FormatButtonStyle(hovering: hovering))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(help)
    }
}

// MARK: - Font family pop-up (AppKit, for per-item font previews)

struct FontFamilyPicker: NSViewRepresentable {
    var family: String
    var onSelect: (String) -> Void

    private static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.controlSize = .regular
        popUp.font = .systemFont(ofSize: 12)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.selectionChanged(_:))
        popUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popUp.toolTip = "Font"
        let menu = NSMenu()
        menu.delegate = context.coordinator
        for family in Self.families {
            menu.addItem(withTitle: family, action: nil, keyEquivalent: "")
        }
        popUp.menu = menu
        return popUp
    }

    func updateNSView(_ popUp: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        guard popUp.titleOfSelectedItem != family else { return }
        // Fonts not installed on this Mac still show their name.
        if let placeholder = popUp.menu?.items.first(where: { $0.tag == Coordinator.missingFontTag }) {
            popUp.menu?.removeItem(placeholder)
        }
        if popUp.item(withTitle: family) == nil {
            let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            item.tag = Coordinator.missingFontTag
            popUp.menu?.insertItem(item, at: 0)
        }
        popUp.selectItem(withTitle: family)
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        static let missingFontTag = -1
        var parent: FontFamilyPicker
        private var styled = false

        init(_ parent: FontFamilyPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let title = sender.titleOfSelectedItem else { return }
            parent.onSelect(title)
        }

        /// Render each family in its own typeface the first time the menu opens.
        func menuNeedsUpdate(_ menu: NSMenu) {
            guard !styled else { return }
            styled = true
            for item in menu.items {
                guard let font = NSFontManager.shared.font(withFamily: item.title, traits: [], weight: 5, size: 13) else { continue }
                // Symbol fonts can't render their own names legibly.
                guard font.coveredCharacterSet.isSuperset(of: CharacterSet(charactersIn: item.title)) else { continue }
                item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: font])
            }
        }
    }
}

// MARK: - Font size combo box

struct FontSizeField: NSViewRepresentable {
    static let standardSizes: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 48, 60, 72, 96]

    var size: CGFloat
    var onCommit: (CGFloat) -> Void

    static func format(_ size: CGFloat) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.addItems(withObjectValues: Self.standardSizes.map(Self.format))
        box.numberOfVisibleItems = 14
        box.completes = false
        box.isEditable = true
        box.controlSize = .regular
        box.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        box.target = context.coordinator
        box.action = #selector(Coordinator.commit(_:))
        box.toolTip = "Font Size"
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if box.currentEditor() == nil {
            box.stringValue = Self.format(size)
        }
    }

    final class Coordinator: NSObject {
        var parent: FontSizeField

        init(_ parent: FontSizeField) {
            self.parent = parent
        }

        @objc func commit(_ sender: NSComboBox) {
            let text = sender.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            guard let value = Double(text), value >= 1, value <= 1638 else {
                sender.stringValue = FontSizeField.format(parent.size)
                return
            }
            if abs(CGFloat(value) - parent.size) > 0.01 {
                parent.onCommit(CGFloat(value))
            }
        }
    }
}
