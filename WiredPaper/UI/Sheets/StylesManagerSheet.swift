import AppKit
import SwiftUI

/// Create, edit and delete paragraph styles and choose the document theme.
struct StylesManagerSheet: View {
    let onApply: (_ theme: DocumentTheme, _ styles: [StyleDefinition]) -> Void
    let onCancel: () -> Void
    let currentParagraphStyleID: String

    @State private var theme: DocumentTheme
    @State private var styles: [StyleDefinition]
    @State private var selection: String
    private let unit = AppSettings.shared.measurementUnit
    private static let families = NSFontManager.shared.availableFontFamilies.sorted()

    init(theme: DocumentTheme, overrides: [StyleDefinition], currentParagraphStyleID: String,
         onApply: @escaping (DocumentTheme, [StyleDefinition]) -> Void, onCancel: @escaping () -> Void) {
        var merged: [StyleDefinition] = StyleSheet.builtIns
        for override in overrides {
            if let index = merged.firstIndex(where: { $0.id == override.id }) {
                merged[index] = override
            } else {
                merged.append(override)
            }
        }
        _theme = State(initialValue: theme)
        _styles = State(initialValue: merged)
        _selection = State(initialValue: merged.contains { $0.id == currentParagraphStyleID } ? currentParagraphStyleID : "normal")
        self.currentParagraphStyleID = currentParagraphStyleID
        self.onApply = onApply
        self.onCancel = onCancel
    }

    private var selectedIndex: Int? { styles.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(width: 210)
                Divider()
                ScrollView {
                    if let index = selectedIndex {
                        StyleEditor(style: $styles[index], allStyles: styles, families: Self.families, unit: unit)
                            .padding(18)
                    }
                }
                .frame(width: 420)
            }
            .frame(height: 470)
            Divider()
            HStack {
                Picker("Theme", selection: $theme) {
                    ForEach(DocumentTheme.presets) { preset in
                        Text("\(preset.name) — \(preset.headingFont) / \(preset.bodyFont)").tag(preset)
                    }
                    if !DocumentTheme.presets.contains(theme) {
                        Text(theme.name).tag(theme)
                    }
                }
                .frame(width: 330)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply to Document") { onApply(theme, overrides) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 632)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Built-in") {
                    ForEach(styles.filter(\.isBuiltIn)) { style in
                        StylePreviewRow(style: style, sheet: previewSheet).tag(style.id)
                    }
                }
                if styles.contains(where: { !$0.isBuiltIn }) {
                    Section("Custom") {
                        ForEach(styles.filter { !$0.isBuiltIn }) { style in
                            StylePreviewRow(style: style, sheet: previewSheet).tag(style.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            HStack(spacing: 4) {
                Button { addStyle() } label: { Image(systemName: "plus") }
                    .help("New style based on the selected style")
                Button { deleteStyle() } label: { Image(systemName: "minus") }
                    .help("Delete custom style")
                    .disabled(selectedIndex.map { styles[$0].isBuiltIn } ?? true)
                Spacer()
                Button("Reset") { resetStyle() }
                    .help("Restore the built-in definition")
                    .disabled(!(selectedIndex.map { styles[$0].isBuiltIn && styles[$0] != StyleSheet.builtIns.first { $0.id == selection } } ?? false))
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private var previewSheet: StyleSheet {
        StyleSheet(theme: theme, overrides: overrides, bodySize: CGFloat(AppSettings.shared.defaultFontSize))
    }

    /// Only store styles that differ from the built-in definitions.
    private var overrides: [StyleDefinition] {
        styles.filter { style in
            guard style.isBuiltIn else { return true }
            return style != StyleSheet.builtIns.first { $0.id == style.id }
        }
    }

    private func addStyle() {
        let base = selection
        var style = StyleDefinition(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: "New Style", basedOn: base)
        var number = 1
        while styles.contains(where: { $0.name == style.name }) {
            number += 1
            style.name = "New Style \(number)"
        }
        styles.append(style)
        selection = style.id
    }

    private func deleteStyle() {
        guard let index = selectedIndex, !styles[index].isBuiltIn else { return }
        let removed = styles[index].id
        let parent = styles[index].basedOn ?? "normal"
        styles.remove(at: index)
        // Children of the deleted style inherit from its parent instead.
        for child in styles.indices where styles[child].basedOn == removed {
            styles[child].basedOn = parent
        }
        selection = parent
    }

    private func resetStyle() {
        guard let index = selectedIndex, let original = StyleSheet.builtIns.first(where: { $0.id == selection }) else { return }
        styles[index] = original
    }
}

private struct StylePreviewRow: View {
    let style: StyleDefinition
    let sheet: StyleSheet

    var body: some View {
        let resolved = sheet.resolve(style.id)
        Text(style.name)
            .font(Font(NSFontManager.shared.convert(resolved.font, toSize: min(max(resolved.font.pointSize, 11), 17))))
            .foregroundStyle(Color(nsColor: resolved.color))
            .lineLimit(1)
    }
}

private struct StyleEditor: View {
    @Binding var style: StyleDefinition
    let allStyles: [StyleDefinition]
    let families: [String]
    let unit: MeasurementUnit

    var body: some View {
        Form {
            Section("Style") {
                TextField("Name", text: $style.name)
                    .disabled(style.isBuiltIn)
                if style.id != "normal" {
                    Picker("Based on", selection: Binding(get: { style.basedOn ?? "normal" }, set: { style.basedOn = $0 })) {
                        ForEach(allStyles.filter { $0.id != style.id }) { Text($0.name).tag($0.id) }
                    }
                }
                Picker("Next paragraph", selection: Binding(get: { style.nextStyle ?? "" }, set: { style.nextStyle = $0.isEmpty ? nil : $0 })) {
                    Text("Same style").tag("")
                    ForEach(allStyles) { Text($0.name).tag($0.id) }
                }
            }
            Section("Font") {
                Picker("Family", selection: optional(\.fontFamily, fallback: "")) {
                    Text("Inherit").tag("")
                    Text("Theme heading font").tag("+heading")
                    Text("Theme body font").tag("+body")
                    Divider()
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        TextField("Size", value: Binding(
                            get: { style.fontSize.map(Double.init) },
                            set: { style.fontSize = $0.map { CGFloat($0) }; if $0 != nil { style.sizeScale = nil } }
                        ), format: .number)
                        .labelsHidden()
                        .frame(width: 60)
                        Text(style.fontSize == nil ? (style.sizeScale.map { "× \(String(format: "%.2g", $0)) body" } ?? "inherit") : "pt")
                            .foregroundStyle(.secondary)
                    }
                }
                TriStateToggle(title: "Bold", value: $style.bold)
                TriStateToggle(title: "Italic", value: $style.italic)
                TriStateToggle(title: "Underline", value: $style.underline)
                Picker("Color", selection: optional(\.color, fallback: "")) {
                    Text("Inherit").tag("")
                    Text("Text").tag("+text")
                    Text("Theme heading").tag("+heading")
                    Text("Theme secondary").tag("+secondary")
                    Text("Theme accent").tag("+accent")
                    if let color = style.color, !color.hasPrefix("+") { Text(color).tag(color) }
                }
                ColorPicker("Custom color", selection: Binding(
                    get: { Color(nsColor: style.color.flatMap { $0.hasPrefix("+") ? nil : NSColor(hex: $0) } ?? .black) },
                    set: { style.color = NSColor($0).hexString }
                ), supportsOpacity: false)
            }
            Section("Paragraph") {
                Picker("Alignment", selection: optional(\.alignment, fallback: "")) {
                    Text("Inherit").tag("")
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                    Text("Justified").tag("justified")
                }
                number("Space before", \.spaceBefore, suffix: "pt", scale: 1)
                number("Space after", \.spaceAfter, suffix: "pt", scale: 1)
                number("Line spacing", \.lineHeight, suffix: "×", scale: 1)
                number("Left indent", \.leftIndent, suffix: unit.abbreviation, scale: unit.pointsPerUnit)
                number("Right indent", \.rightIndent, suffix: unit.abbreviation, scale: unit.pointsPerUnit)
                number("First line", \.firstLineIndent, suffix: unit.abbreviation, scale: unit.pointsPerUnit)
                TriStateToggle(title: "Keep with next", value: $style.keepWithNext)
                Picker("Outline level", selection: Binding(get: { style.outlineLevel ?? 0 }, set: { style.outlineLevel = $0 == 0 ? nil : $0 })) {
                    Text("Body text").tag(0)
                    ForEach(1...9, id: \.self) { Text("Level \($0)").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func optional(_ keyPath: WritableKeyPath<StyleDefinition, String?>, fallback: String) -> Binding<String> {
        Binding(get: { style[keyPath: keyPath] ?? fallback }, set: { style[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func number(_ title: String, _ keyPath: WritableKeyPath<StyleDefinition, CGFloat?>, suffix: String, scale: CGFloat) -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, value: Binding(
                    get: { style[keyPath: keyPath].map { Double($0 / scale) } },
                    set: { style[keyPath: keyPath] = $0.map { CGFloat($0) * scale } }
                ), format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .frame(width: 60)
                Text(style[keyPath: keyPath] == nil ? "inherit" : suffix).foregroundStyle(.secondary)
            }
        }
    }
}

/// On / Off / Inherit.
private struct TriStateToggle: View {
    let title: String
    @Binding var value: Bool?

    var body: some View {
        Picker(title, selection: Binding(get: { value.map { $0 ? 1 : 0 } ?? -1 }, set: { value = $0 == -1 ? nil : $0 == 1 })) {
            Text("Inherit").tag(-1)
            Text("On").tag(1)
            Text("Off").tag(0)
        }
        .pickerStyle(.segmented)
    }
}
