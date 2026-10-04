import SwiftUI

/// Paper size, orientation and margins, with a live miniature of the page.
struct DocumentSetupSheet: View {
    let unit: MeasurementUnit
    let onApply: (PageSetup) -> Void
    let onCancel: () -> Void

    /// nil means the document's existing, non-standard paper size.
    @State private var paper: PaperPreset?
    @State private var orientation: PageOrientation
    @State private var top: Double
    @State private var left: Double
    @State private var bottom: Double
    @State private var right: Double
    private let originalSize: CGSize

    init(setup: PageSetup, unit: MeasurementUnit, onApply: @escaping (PageSetup) -> Void, onCancel: @escaping () -> Void) {
        self.unit = unit
        self.onApply = onApply
        self.onCancel = onCancel
        originalSize = setup.paperSize
        _paper = State(initialValue: PaperPreset.matching(setup.paperSize))
        _orientation = State(initialValue: setup.orientation)
        _top = State(initialValue: unit.fromPoints(setup.margins.top))
        _left = State(initialValue: unit.fromPoints(setup.margins.left))
        _bottom = State(initialValue: unit.fromPoints(setup.margins.bottom))
        _right = State(initialValue: unit.fromPoints(setup.margins.right))
    }

    private var result: PageSetup {
        let portrait: CGSize
        if let paper {
            portrait = paper.size
        } else {
            portrait = CGSize(width: min(originalSize.width, originalSize.height), height: max(originalSize.width, originalSize.height))
        }
        let setup = PageSetup(
            paperSize: portrait,
            margins: Margins(
                top: unit.toPoints(max(top, 0)),
                left: unit.toPoints(max(left, 0)),
                bottom: unit.toPoints(max(bottom, 0)),
                right: unit.toPoints(max(right, 0))
            )
        )
        return setup.oriented(orientation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section("Paper") {
                        Picker("Size", selection: $paper) {
                            ForEach(PaperPreset.allCases) { preset in
                                Text("\(preset.displayName) (\(preset.dimensionsDescription))").tag(Optional(preset))
                            }
                            if PaperPreset.matching(originalSize) == nil {
                                Text("Custom").tag(PaperPreset?.none)
                            }
                        }
                        Picker("Orientation", selection: $orientation) {
                            Text("Portrait").tag(PageOrientation.portrait)
                            Text("Landscape").tag(PageOrientation.landscape)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Margins") {
                        margin("Top", $top)
                        margin("Bottom", $bottom)
                        margin("Left", $left)
                        margin("Right", $right)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(width: 360)

                PagePreview(setup: result)
                    .frame(width: 150, height: 200)
                    .padding(.top, 28)
                    .padding(.trailing, 20)
            }

            HStack {
                if !result.isValid {
                    Label("Margins leave no room for text.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { onApply(result) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!result.isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .fixedSize()
    }

    private func margin(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(unit.abbreviation)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
            }
        }
    }
}

private struct PagePreview: View {
    let setup: PageSetup

    var body: some View {
        GeometryReader { proxy in
            let paper = setup.paperSize
            let scale = min(proxy.size.width / paper.width, proxy.size.height / paper.height)
            let size = CGSize(width: paper.width * scale, height: paper.height * scale)
            let margins = setup.margins
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                Rectangle()
                    .strokeBorder(Theme.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(
                        width: max(size.width - (margins.left + margins.right) * scale, 1),
                        height: max(size.height - (margins.top + margins.bottom) * scale, 1)
                    )
                    .offset(x: margins.left * scale, y: margins.top * scale)
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: setup)
        }
    }
}
