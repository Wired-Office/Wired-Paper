import SwiftUI

struct ParagraphSheet: View {
    private enum FirstLine: String, CaseIterable, Identifiable {
        case none = "None", indent = "First Line", hanging = "Hanging"
        var id: String { rawValue }
    }

    let unit: MeasurementUnit
    let onApply: (ParagraphSettings) -> Void
    let onCancel: () -> Void

    @State private var alignment: NSTextAlignment
    @State private var left: Double
    @State private var right: Double
    @State private var firstLine: FirstLine
    @State private var firstLineBy: Double
    @State private var before: Double
    @State private var after: Double
    @State private var lineSpacing: Double

    init(settings: ParagraphSettings, unit: MeasurementUnit, onApply: @escaping (ParagraphSettings) -> Void, onCancel: @escaping () -> Void) {
        self.unit = unit
        self.onApply = onApply
        self.onCancel = onCancel
        _alignment = State(initialValue: settings.alignment)
        _left = State(initialValue: unit.fromPoints(settings.leftIndent))
        _right = State(initialValue: unit.fromPoints(settings.rightIndent))
        let offset = settings.firstLineOffset
        _firstLine = State(initialValue: abs(offset) < 0.5 ? .none : (offset > 0 ? .indent : .hanging))
        _firstLineBy = State(initialValue: unit.fromPoints(abs(offset)))
        _before = State(initialValue: Double(settings.spacingBefore))
        _after = State(initialValue: Double(settings.spacingAfter))
        _lineSpacing = State(initialValue: Double(settings.lineHeightMultiple))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("General") {
                    Picker("Alignment", selection: $alignment) {
                        Text("Left").tag(NSTextAlignment.left)
                        Text("Center").tag(NSTextAlignment.center)
                        Text("Right").tag(NSTextAlignment.right)
                        Text("Justified").tag(NSTextAlignment.justified)
                    }
                }

                Section("Indentation") {
                    measurement("Left", $left, unit.abbreviation)
                    measurement("Right", $right, unit.abbreviation)
                    Picker("Special", selection: $firstLine) {
                        ForEach(FirstLine.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if firstLine != .none {
                        measurement("By", $firstLineBy, unit.abbreviation)
                    }
                }

                Section("Spacing") {
                    measurement("Before", $before, "pt")
                    measurement("After", $after, "pt")
                    Picker("Line Spacing", selection: $lineSpacing) {
                        ForEach(LineSpacingOption.all) { option in
                            Text(option.title).tag(Double(option.multiple))
                        }
                        if !LineSpacingOption.all.contains(where: { abs(Double($0.multiple) - lineSpacing) < 0.001 }) {
                            Text(String(format: "%.2f", lineSpacing)).tag(lineSpacing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func measurement(_ title: String, _ value: Binding<Double>, _ suffix: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
            }
        }
    }

    private func apply() {
        var settings = ParagraphSettings()
        settings.alignment = alignment
        settings.leftIndent = unit.toPoints(max(left, 0))
        settings.rightIndent = unit.toPoints(max(right, 0))
        let by = unit.toPoints(max(firstLineBy, 0))
        switch firstLine {
        case .none: settings.firstLineOffset = 0
        case .indent: settings.firstLineOffset = by
        case .hanging: settings.firstLineOffset = -min(by, settings.leftIndent)
        }
        settings.spacingBefore = CGFloat(max(before, 0))
        settings.spacingAfter = CGFloat(max(after, 0))
        settings.lineHeightMultiple = CGFloat(max(lineSpacing, 0.5))
        onApply(settings)
    }
}
