import SwiftUI

/// Edits any graphic object with a live preview.
struct ObjectEditorSheet: View {
    @State var object: DocumentObject
    let isNew: Bool
    let onSave: (DocumentObject) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetScaffold(title: title, primaryTitle: isNew ? "Insert" : "Update", width: 760, onPrimary: { onSave(object) }, onCancel: onCancel) {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    editor
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 340, height: 420)
                preview
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var title: String {
        switch object.kind {
        case .chart: "Chart"
        case .equation: "Equation"
        case .shape: object.shape?.kind == .textBox ? "Text Box" : object.shape?.kind == .icon ? "Icon" : "Shape"
        case .wordArt: "Decorative Text"
        case .diagram: "Diagram"
        case .spreadsheet: "Spreadsheet"
        case .drawing: "Drawing"
        case .signature: "Signature Line"
        case .dropdown: "Drop-Down List"
        default: "Object"
        }
    }

    private var preview: some View {
        VStack {
            if let image = ObjectRenderer.image(for: object) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(image.size.width, 360), maxHeight: min(image.size.height, 400))
            } else {
                Text("No preview").foregroundStyle(.secondary)
            }
        }
        .frame(width: 370, height: 420)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }

    @ViewBuilder
    private var editor: some View {
        switch object.kind {
        case .chart: ChartEditor(spec: binding(\.chart, ChartSpec()))
        case .equation: EquationEditor(spec: binding(\.equation, EquationSpec()))
        case .shape, .wordArt: ShapeEditor(spec: binding(\.shape, ShapeSpec()))
        case .diagram: DiagramEditor(spec: binding(\.diagram, DiagramSpec()))
        case .spreadsheet: SpreadsheetEditor(spec: binding(\.sheet, SpreadsheetSpec()))
        case .drawing: DrawingEditor(spec: binding(\.drawing, DrawingSpec()))
        case .signature: SignatureEditor(spec: binding(\.signature, SignatureSpec()))
        case .dropdown, .checkbox, .date: FormControlEditor(spec: binding(\.form, FormControlSpec(type: .dropdown)))
        default: Text("This object has no settings.")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<DocumentObject, T?>, _ fallback: T) -> Binding<T> {
        Binding(get: { object[keyPath: keyPath] ?? fallback }, set: { object[keyPath: keyPath] = $0 })
    }
}

// MARK: - Editors

private struct SizeFields: View {
    @Binding var width: CGFloat
    @Binding var height: CGFloat

    var body: some View {
        HStack {
            Text("Size")
            TextField("Width", value: Binding(get: { Double(width) }, set: { width = max(CGFloat($0), 8) }), format: .number.precision(.fractionLength(0))).frame(width: 60)
            Text("×")
            TextField("Height", value: Binding(get: { Double(height) }, set: { height = max(CGFloat($0), 8) }), format: .number.precision(.fractionLength(0))).frame(width: 60)
            Text("pt").foregroundStyle(.secondary)
        }
    }
}

private struct HexColorPicker: View {
    let title: String
    @Binding var hex: String?

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { hex != nil }, set: { hex = $0 ? (hex ?? "#13787F") : nil }))
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: hex.flatMap(NSColor.init(hex:)) ?? .clear) },
                set: { hex = NSColor($0).hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(hex == nil)
        }
    }
}

struct ChartEditor: View {
    @Binding var spec: ChartSpec

    /// Tab-separated data: first row = categories, first column = series names.
    private var dataText: Binding<String> {
        Binding(get: {
            let header = ([""] + spec.categories).joined(separator: "\t")
            let rows = spec.series.map { ([$0.name] + $0.values.map(FormulaEngine.format)).joined(separator: "\t") }
            return ([header] + rows).joined(separator: "\n")
        }, set: { text in
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            guard let header = lines.first else { return }
            spec.categories = Array(header.dropFirst())
            let lineFlags = Dictionary(spec.series.map { ($0.name, $0.asLine) }, uniquingKeysWith: { a, _ in a })
            spec.series = lines.dropFirst().map { row in
                var series = ChartSeries(name: row.first ?? "Series", values: row.dropFirst().map { FormulaEngine.parseNumber($0) ?? 0 })
                series.asLine = lineFlags[series.name] ?? false
                return series
            }
        })
    }

    var body: some View {
        Form {
            Picker("Type", selection: $spec.type) {
                ForEach(ChartType.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
            }
            TextField("Title", text: $spec.title)
            TextField("X axis title", text: $spec.xAxisTitle)
            TextField("Y axis title", text: $spec.yAxisTitle)
            Toggle("Show legend", isOn: $spec.showLegend)
            SizeFields(width: $spec.width, height: $spec.height)
            VStack(alignment: .leading) {
                Text("Data (tab-separated; first row are categories, first column series names)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: dataText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.secondary.opacity(0.3))
            }
            if spec.type == .combo {
                ForEach($spec.series) { $series in
                    Toggle("Draw “\(series.name)” as line", isOn: $series.asLine)
                }
            }
        }
    }
}

struct EquationEditor: View {
    @Binding var spec: EquationSpec
    private let snippets: [(String, String)] = [
        ("a/b", "\\frac{a}{b}"), ("√", "\\sqrt{x}"), ("xⁿ", "x^{n}"), ("xᵢ", "x_{i}"), ("∑", "\\sum_{i=1}^{n}"), ("∫", "\\int_{a}^{b}"),
        ("lim", "\\lim_{x \\to \\infty}"), ("( )", "\\left( x \\right)"), ("Matrix", "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"),
        ("α", "\\alpha"), ("β", "\\beta"), ("π", "\\pi"), ("θ", "\\theta"), ("±", "\\pm"), ("≤", "\\leq"), ("≠", "\\neq"), ("∞", "\\infty"), ("→", "\\to"),
    ]

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("LaTeX").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $spec.latex)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.3))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                ForEach(snippets, id: \.1) { snippet in
                    Button(snippet.0) { spec.latex += (spec.latex.isEmpty || spec.latex.hasSuffix(" ") ? "" : " ") + snippet.1 }
                        .controlSize(.small)
                }
            }
            HStack {
                Text("Size")
                Slider(value: $spec.fontSize, in: 10...40)
                Text("\(Int(spec.fontSize)) pt").monospacedDigit()
            }
            Menu("Examples") {
                Button("Quadratic formula") { spec.latex = "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}" }
                Button("Pythagoras") { spec.latex = "a^2 + b^2 = c^2" }
                Button("Euler") { spec.latex = "e^{i\\pi} + 1 = 0" }
                Button("Sum of squares") { spec.latex = "\\sum_{k=1}^{n} k^2 = \\frac{n(n+1)(2n+1)}{6}" }
                Button("Gaussian integral") { spec.latex = "\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}" }
                Button("Derivative") { spec.latex = "f'(x) = \\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h}" }
                Button("Piecewise") { spec.latex = "|x| = \\begin{cases} x & x \\geq 0 \\\\ -x & x < 0 \\end{cases}" }
            }
        }
    }
}

struct ShapeEditor: View {
    @Binding var spec: ShapeSpec

    var body: some View {
        Form {
            Picker("Shape", selection: $spec.kind) {
                ForEach(ShapeKind.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
            }
            if spec.kind == .wordArt {
                Picker("Style", selection: $spec.wordArtStyle) {
                    ForEach(WordArtStyle.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if spec.kind == .icon {
                TextField("SF Symbol name", text: $spec.symbolName)
                HStack {
                    ForEach(["star.fill", "heart.fill", "checkmark.seal.fill", "lightbulb.fill", "flag.fill", "bolt.fill", "leaf.fill", "person.fill"], id: \.self) { name in
                        Button { spec.symbolName = name } label: { Image(systemName: name) }.buttonStyle(.borderless)
                    }
                }
            } else if spec.kind != .line && spec.kind != .arrowLine {
                VStack(alignment: .leading) {
                    Text("Text").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $spec.text).frame(height: 60).border(Color.secondary.opacity(0.3))
                }
                TextField("Font", text: $spec.fontFamily)
                HStack {
                    Stepper("Font size \(Int(spec.fontSize))", value: $spec.fontSize, in: 6...96)
                    Toggle("Bold", isOn: $spec.bold)
                }
                ColorPicker("Text color", selection: Binding(get: { Color(nsColor: NSColor(hex: spec.textColorHex) ?? .black) },
                                                            set: { spec.textColorHex = NSColor($0).hexString }), supportsOpacity: false)
            }
            HexColorPicker(title: spec.kind == .wordArt || spec.kind == .icon ? "Accent" : "Fill", hex: $spec.fillHex)
            if spec.kind != .wordArt && spec.kind != .icon {
                HexColorPicker(title: "Outline", hex: $spec.strokeHex)
                Stepper("Outline width \(spec.strokeWidth, specifier: "%.1f")", value: $spec.strokeWidth, in: 0...12, step: 0.5)
            }
            if spec.kind == .roundedRectangle {
                Stepper("Corner radius \(Int(spec.cornerRadius))", value: $spec.cornerRadius, in: 0...60)
            }
            SizeFields(width: $spec.width, height: $spec.height)
            HStack {
                Text("Rotation")
                Slider(value: $spec.rotation, in: -180...180, step: 5)
                Text("\(Int(spec.rotation))°").monospacedDigit().frame(width: 40)
            }
            HStack {
                Toggle("Flip horizontal", isOn: $spec.flipHorizontal)
                Toggle("Flip vertical", isOn: $spec.flipVertical)
            }
            Toggle("Shadow", isOn: $spec.shadow)
        }
    }
}

struct DiagramEditor: View {
    @Binding var spec: DiagramSpec

    var body: some View {
        Form {
            Picker("Layout", selection: $spec.type) {
                ForEach(DiagramType.allCases) { Text($0.displayName).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Items — one per line; indent with a tab for sub-items (hierarchy, list). End a flowchart step with “?” for a decision.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $spec.outline)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 160)
                    .border(Color.secondary.opacity(0.3))
            }
            ColorPicker("Color", selection: Binding(get: { Color(nsColor: NSColor(hex: spec.colorHex) ?? .systemTeal) },
                                                    set: { spec.colorHex = NSColor($0).hexString }), supportsOpacity: false)
            SizeFields(width: $spec.width, height: $spec.height)
        }
    }
}

struct SpreadsheetEditor: View {
    @Binding var spec: SpreadsheetSpec

    var body: some View {
        Form {
            Text("Cells may hold numbers, text or formulas such as =SUM(B2:B5), =AVERAGE(A1:A3) or =B2*C2.")
                .font(.caption).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("")
                    ForEach(0..<columnCount, id: \.self) { Text(String(UnicodeScalar(65 + $0)!)).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(0..<spec.cells.count, id: \.self) { row in
                    GridRow {
                        Text("\(row + 1)").font(.caption).foregroundStyle(.secondary)
                        ForEach(0..<columnCount, id: \.self) { column in
                            TextField("", text: cell(row, column)).textFieldStyle(.squareBorder).frame(width: 64)
                        }
                    }
                }
            }
            HStack {
                Button("Add Row") { spec.cells.append(Array(repeating: "", count: columnCount)) }
                Button("Add Column") { for row in spec.cells.indices { spec.cells[row].append("") } }
                Button("Remove Row") { if spec.cells.count > 1 { spec.cells.removeLast() } }.disabled(spec.cells.count <= 1)
                Button("Remove Column") { for row in spec.cells.indices where spec.cells[row].count > 1 { spec.cells[row].removeLast() } }
                    .disabled(columnCount <= 1)
            }
            .controlSize(.small)
            Toggle("Header row", isOn: $spec.headerRow)
            Stepper("Column width \(Int(spec.columnWidth))", value: $spec.columnWidth, in: 40...200, step: 5)
        }
    }

    private var columnCount: Int { spec.cells.map(\.count).max() ?? 1 }

    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(get: { column < spec.cells[row].count ? spec.cells[row][column] : "" }, set: { value in
            while spec.cells[row].count <= column { spec.cells[row].append("") }
            spec.cells[row][column] = value
        })
    }
}

struct SignatureEditor: View {
    @Binding var spec: SignatureSpec

    var body: some View {
        Form {
            TextField("Suggested signer", text: $spec.signer)
            TextField("Signer's title", text: $spec.title)
            TextField("Instructions", text: $spec.instructions)
            Divider()
            TextField("Sign by typing your name", text: Binding(get: { spec.signedName ?? "" }, set: {
                spec.signedName = $0.isEmpty ? nil : $0
                spec.signedDate = $0.isEmpty ? nil : (spec.signedDate ?? Date())
            }))
        }
    }
}

struct FormControlEditor: View {
    @Binding var spec: FormControlSpec

    var body: some View {
        Form {
            TextField("Name", text: $spec.name)
            if spec.type == .dropdown {
                VStack(alignment: .leading) {
                    Text("Choices (one per line)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { spec.options.joined(separator: "\n") }, set: {
                        spec.options = $0.split(separator: "\n").map(String.init)
                        spec.selected = min(spec.selected, max(spec.options.count - 1, 0))
                    }))
                    .frame(height: 120).border(Color.secondary.opacity(0.3))
                }
            }
            if spec.type == .date {
                TextField("Placeholder", text: $spec.placeholder)
            }
        }
    }
}

/// A freehand canvas: pen, highlighter, color, eraser (undo last stroke).
struct DrawingEditor: View {
    @Binding var spec: DrawingSpec
    @State private var colorHex = "#1B1B1B"
    @State private var width: CGFloat = 2.5
    @State private var highlighter = false
    @State private var current: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $highlighter) {
                    Label("Pen", systemImage: "pencil.tip").tag(false)
                    Label("Highlighter", systemImage: "highlighter").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ColorPicker("", selection: Binding(get: { Color(nsColor: NSColor(hex: colorHex) ?? .black) }, set: { colorHex = NSColor($0).hexString }))
                    .labelsHidden()
            }
            Stepper("Width \(width, specifier: "%.1f")", value: $width, in: 1...20, step: 0.5)
            Canvas { context, _ in
                let scale = spec.width / min(spec.width, 330)
                let stored = spec.strokes.map { stroke in
                    var scaled = stroke
                    scaled.points = stroke.points.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
                    return scaled
                }
                for stroke in stored + (current.isEmpty ? [] : [DrawingStroke(points: current, colorHex: colorHex, width: width, highlighter: highlighter)]) {
                    var path = Path()
                    path.addLines(stroke.points)
                    let color = Color(nsColor: NSColor(hex: stroke.colorHex) ?? .black).opacity(stroke.highlighter ? 0.35 : 1)
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.highlighter ? max(stroke.width, 12) : stroke.width, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: min(spec.width, 330), height: spec.height / (spec.width / min(spec.width, 330)))
            .background(Color.white)
            .border(Color.secondary.opacity(0.4))
            .gesture(DragGesture(minimumDistance: 0).onChanged { current.append($0.location) }.onEnded { _ in
                let scale = spec.width / min(spec.width, 330)
                spec.strokes.append(DrawingStroke(points: current.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }, colorHex: colorHex, width: width, highlighter: highlighter))
                current = []
            })
            HStack {
                Button("Undo Stroke") { if !spec.strokes.isEmpty { spec.strokes.removeLast() } }.disabled(spec.strokes.isEmpty)
                Button("Clear") { spec.strokes = [] }.disabled(spec.strokes.isEmpty)
            }
            SizeFields(width: $spec.width, height: $spec.height)
        }
    }
}
