import AppKit
import SwiftUI

/// Shared sheet chrome: title, content, Cancel/primary buttons.
struct SheetScaffold<Content: View>: View {
    let title: String
    var primaryTitle = "OK"
    var primaryDisabled = false
    var width: CGFloat = 420
    let onPrimary: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.horizontal, .top], 20)
            content()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: onPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
            .padding(20)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A measurement text field with a unit suffix.
struct MeasurementField: View {
    let title: String
    @Binding var points: CGFloat
    let unit: MeasurementUnit

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(get: { unit.fromPoints(points) }, set: { points = unit.toPoints($0) }),
                          format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(unit.abbreviation).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
            }
        }
    }
}

struct NumberPromptSheet: View {
    let title: String
    let label: String
    let range: ClosedRange<Int>
    let onApply: (Int) -> Void
    let onCancel: () -> Void
    @State private var value: Int

    init(title: String, label: String, initial: Int, range: ClosedRange<Int>, onApply: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.label = label
        self.range = range
        self.onApply = onApply
        self.onCancel = onCancel
        _value = State(initialValue: initial)
    }

    var body: some View {
        SheetScaffold(title: title, width: 300, onPrimary: { onApply(min(max(value, range.lowerBound), range.upperBound)) }, onCancel: onCancel) {
            Form {
                Stepper(value: $value, in: range) {
                    LabeledContent(label) {
                        TextField(label, value: $value, format: .number).labelsHidden().frame(width: 70)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

struct TextPromptSheet: View {
    let title: String
    let label: String
    var primaryTitle = "OK"
    let onApply: (String) -> Void
    let onCancel: () -> Void
    @State var text: String

    var body: some View {
        SheetScaffold(title: title, primaryTitle: primaryTitle, primaryDisabled: text.trimmingCharacters(in: .whitespaces).isEmpty, width: 380,
                      onPrimary: { onApply(text.trimmingCharacters(in: .whitespaces)) }, onCancel: onCancel) {
            Form {
                TextField(label, text: $text)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

// MARK: - Borders & shading

struct BordersShadingSheet: View {
    let onApply: (ParagraphBorderSettings) -> Void
    let onCancel: () -> Void
    @State private var settings: ParagraphBorderSettings
    @State private var useShading: Bool

    init(initial: ParagraphBorderSettings, onApply: @escaping (ParagraphBorderSettings) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _settings = State(initialValue: initial)
        _useShading = State(initialValue: initial.shading != nil)
    }

    var body: some View {
        SheetScaffold(title: "Borders and Shading", primaryTitle: "Apply", width: 460, onPrimary: {
            var result = settings
            if !useShading { result.shading = nil }
            onApply(result)
        }, onCancel: onCancel) {
            HStack(alignment: .top, spacing: 16) {
                Form {
                    Section("Presets") {
                        HStack {
                            Button("None") { settings.top = false; settings.bottom = false; settings.left = false; settings.right = false }
                            Button("Box") { settings.top = true; settings.bottom = true; settings.left = true; settings.right = true }
                            Button("Bottom") { settings.top = false; settings.bottom = true; settings.left = false; settings.right = false }
                            Button("Top & Bottom") { settings.top = true; settings.bottom = true; settings.left = false; settings.right = false }
                        }
                    }
                    Section("Edges") {
                        Toggle("Top", isOn: $settings.top)
                        Toggle("Bottom", isOn: $settings.bottom)
                        Toggle("Left", isOn: $settings.left)
                        Toggle("Right", isOn: $settings.right)
                        Stepper(value: $settings.width, in: 0.25...6, step: 0.25) {
                            LabeledContent("Width", value: String(format: "%.2g pt", settings.width))
                        }
                        ColorPicker("Color", selection: Binding(get: { Color(nsColor: settings.color) }, set: { settings.color = NSColor($0) }), supportsOpacity: false)
                    }
                    Section("Shading") {
                        Toggle("Fill", isOn: $useShading)
                        ColorPicker("Fill color", selection: Binding(
                            get: { Color(nsColor: settings.shading ?? NSColor(srgbRed: 0.93, green: 0.96, blue: 0.97, alpha: 1)) },
                            set: { settings.shading = NSColor($0); useShading = true }
                        ), supportsOpacity: false)
                        Stepper(value: $settings.padding, in: 0...24, step: 1) {
                            LabeledContent("Padding", value: "\(Int(settings.padding)) pt")
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
        }
    }
}

// MARK: - Tabs

struct TabsSheet: View {
    let unit: MeasurementUnit
    let onApply: ([TabStopSpec], CGFloat) -> Void
    let onCancel: () -> Void
    @State private var tabs: [TabStopSpec]
    @State private var defaultInterval: CGFloat
    @State private var selection: TabStopSpec.ID?

    init(tabs: ([TabStopSpec], CGFloat), unit: MeasurementUnit, onApply: @escaping ([TabStopSpec], CGFloat) -> Void, onCancel: @escaping () -> Void) {
        self.unit = unit
        self.onApply = onApply
        self.onCancel = onCancel
        _tabs = State(initialValue: tabs.0)
        _defaultInterval = State(initialValue: tabs.1)
    }

    var body: some View {
        SheetScaffold(title: "Tabs", primaryTitle: "Apply", width: 520, onPrimary: { onApply(tabs, defaultInterval) }, onCancel: onCancel) {
            VStack(alignment: .leading, spacing: 10) {
                Table($tabs, selection: $selection) {
                    TableColumn("Position (\(unit.abbreviation))") { $tab in
                        TextField("", value: Binding(get: { unit.fromPoints(tab.location) }, set: { tab.location = unit.toPoints($0) }),
                                  format: .number.precision(.fractionLength(0...2)))
                    }
                    TableColumn("Alignment") { $tab in
                        Picker("", selection: Binding(
                            get: { tab.isDecimal ? 99 : tab.alignment.rawValue },
                            set: { if $0 == 99 { tab.isDecimal = true } else { tab.isDecimal = false; tab.alignment = NSTextAlignment(rawValue: $0) ?? .left } }
                        )) {
                            Text("Left").tag(NSTextAlignment.left.rawValue)
                            Text("Center").tag(NSTextAlignment.center.rawValue)
                            Text("Right").tag(NSTextAlignment.right.rawValue)
                            Text("Decimal").tag(99)
                        }
                        .labelsHidden()
                    }
                    TableColumn("Leader") { $tab in
                        Picker("", selection: $tab.leader) {
                            ForEach(TabLeader.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                .frame(height: 180)
                HStack {
                    Button {
                        let next = (tabs.map(\.location).max() ?? 0) + 72
                        tabs.append(TabStopSpec(location: next))
                    } label: { Label("Add Tab Stop", systemImage: "plus") }
                    Button {
                        tabs.removeAll { $0.id == selection }
                    } label: { Label("Remove", systemImage: "minus") }
                    .disabled(selection == nil)
                    Button("Clear All") { tabs.removeAll() }
                    Spacer()
                }
                .buttonStyle(.borderless)
                Form {
                    MeasurementField(title: "Default tab stops", points: $defaultInterval, unit: unit)
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
}

// MARK: - Columns

struct ColumnsSheet: View {
    let unit: MeasurementUnit
    let onApply: (PageDecoration) -> Void
    let onCancel: () -> Void
    @State private var decoration: PageDecoration

    init(decoration: PageDecoration, unit: MeasurementUnit, onApply: @escaping (PageDecoration) -> Void, onCancel: @escaping () -> Void) {
        self.unit = unit
        self.onApply = onApply
        self.onCancel = onCancel
        _decoration = State(initialValue: decoration)
    }

    var body: some View {
        SheetScaffold(title: "Columns", primaryTitle: "Apply", width: 400, onPrimary: { onApply(decoration) }, onCancel: onCancel) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ForEach(1...4, id: \.self) { count in
                        Button { decoration.columns = count } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 3) {
                                    ForEach(0..<count, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.5)).frame(width: 28 / CGFloat(count), height: 34)
                                    }
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(decoration.columns == count ? Theme.accentColor : Color.secondary.opacity(0.3), lineWidth: decoration.columns == count ? 2 : 1))
                                Text(["One", "Two", "Three", "Four"][count - 1]).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                Form {
                    Stepper(value: $decoration.columns, in: 1...6) {
                        LabeledContent("Number of columns", value: "\(decoration.columns)")
                    }
                    MeasurementField(title: "Spacing", points: $decoration.columnSpacing, unit: unit)
                    Toggle("Line between columns", isOn: $decoration.columnSeparator)
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }
        }
    }
}

// MARK: - Watermark & page border

struct WatermarkSheet: View {
    let onApply: (WatermarkSettings?) -> Void
    let onCancel: () -> Void
    @State private var enabled: Bool
    @State private var settings: WatermarkSettings

    init(initial: WatermarkSettings?, onApply: @escaping (WatermarkSettings?) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _enabled = State(initialValue: true)
        _settings = State(initialValue: initial ?? WatermarkSettings())
    }

    var body: some View {
        SheetScaffold(title: "Watermark", primaryTitle: "Apply", width: 400, onPrimary: { onApply(enabled ? settings : nil) }, onCancel: onCancel) {
            Form {
                Toggle("Show watermark", isOn: $enabled)
                Picker("Text", selection: $settings.text) {
                    ForEach(["DRAFT", "CONFIDENTIAL", "DO NOT COPY", "SAMPLE", "URGENT", "ASAP"], id: \.self) { Text($0).tag($0) }
                    if !["DRAFT", "CONFIDENTIAL", "DO NOT COPY", "SAMPLE", "URGENT", "ASAP"].contains(settings.text) {
                        Text(settings.text).tag(settings.text)
                    }
                }
                TextField("Custom text", text: $settings.text)
                ColorPicker("Color", selection: Binding(get: { Color(nsColor: NSColor(hex: settings.colorHex) ?? .gray) }, set: { settings.colorHex = NSColor($0).hexString }), supportsOpacity: false)
                Slider(value: $settings.opacity, in: 0.05...0.8) { Text("Opacity") }
                Picker("Layout", selection: $settings.diagonal) {
                    Text("Diagonal").tag(true)
                    Text("Horizontal").tag(false)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .disabled(false)
        }
    }
}

struct PageBorderSheet: View {
    let onApply: (PageBorderSettings?) -> Void
    let onCancel: () -> Void
    @State private var enabled: Bool
    @State private var settings: PageBorderSettings

    init(initial: PageBorderSettings?, onApply: @escaping (PageBorderSettings?) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _enabled = State(initialValue: true)
        _settings = State(initialValue: initial ?? PageBorderSettings())
    }

    var body: some View {
        SheetScaffold(title: "Page Borders", primaryTitle: "Apply", width: 380, onPrimary: { onApply(enabled ? settings : nil) }, onCancel: onCancel) {
            Form {
                Toggle("Border around each page", isOn: $enabled)
                Picker("Style", selection: $settings.style) {
                    ForEach(BorderLineStyle.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper(value: $settings.width, in: 0.5...6, step: 0.5) {
                    LabeledContent("Width", value: String(format: "%.1f pt", settings.width))
                }
                ColorPicker("Color", selection: Binding(get: { Color(nsColor: NSColor(hex: settings.colorHex) ?? .darkGray) }, set: { settings.colorHex = NSColor($0).hexString }), supportsOpacity: false)
                Stepper(value: $settings.inset, in: 6...72, step: 2) {
                    LabeledContent("Distance from edge", value: "\(Int(settings.inset)) pt")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}
