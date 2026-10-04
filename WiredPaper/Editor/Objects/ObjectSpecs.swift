import AppKit

// Data models for embedded objects. Renderers live next to each feature.

// MARK: Charts

enum ChartType: String, Codable, CaseIterable, Identifiable {
    case column, bar, line, area, pie, scatter, combo
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .column: "chart.bar"
        case .bar: "chart.bar.xaxis"
        case .line: "chart.line.uptrend.xyaxis"
        case .area: "chart.line.uptrend.xyaxis.circle"
        case .pie: "chart.pie"
        case .scatter: "chart.dots.scatter"
        case .combo: "chart.bar.doc.horizontal"
        }
    }
}

struct ChartSeries: Codable, Equatable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var values: [Double]
    /// In combo charts, draw this series as a line.
    var asLine = false
}

struct ChartSpec: Codable, Equatable {
    var type: ChartType = .column
    var title = "Chart Title"
    var categories: [String] = ["Q1", "Q2", "Q3", "Q4"]
    var series: [ChartSeries] = [
        ChartSeries(name: "Series 1", values: [4.3, 2.5, 3.5, 4.5]),
        ChartSeries(name: "Series 2", values: [2.4, 4.4, 1.8, 2.8], asLine: true),
    ]
    var width: CGFloat = 420
    var height: CGFloat = 260
    var showLegend = true
    var xAxisTitle = ""
    var yAxisTitle = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChartSpec()
        type = c.value(.type, default: d.type)
        title = c.value(.title, default: d.title)
        categories = c.value(.categories, default: d.categories)
        series = c.value(.series, default: d.series)
        width = c.value(.width, default: d.width)
        height = c.value(.height, default: d.height)
        showLegend = c.value(.showLegend, default: true)
        xAxisTitle = c.value(.xAxisTitle, default: "")
        yAxisTitle = c.value(.yAxisTitle, default: "")
    }
}

// MARK: Equations

struct EquationSpec: Codable, Equatable {
    /// LaTeX-style source, e.g. `\frac{a}{b} + \sqrt{x^2}`.
    var latex = "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"
    var fontSize: CGFloat = 16
    var display = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latex = c.value(.latex, default: "")
        fontSize = c.value(.fontSize, default: 16)
        display = c.value(.display, default: true)
    }
}

// MARK: Shapes, text boxes, WordArt, icons

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle, roundedRectangle, ellipse, triangle, diamond, pentagon, hexagon, star
    case arrowRight, arrowLeft, arrowUp, arrowDown, line, arrowLine, callout, textBox, icon, wordArt
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .roundedRectangle: "Rounded Rectangle"
        case .arrowRight: "Right Arrow"
        case .arrowLeft: "Left Arrow"
        case .arrowUp: "Up Arrow"
        case .arrowDown: "Down Arrow"
        case .arrowLine: "Arrow"
        case .textBox: "Text Box"
        case .wordArt: "Decorative Text"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .roundedRectangle: "app"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .diamond: "diamond"
        case .pentagon: "pentagon"
        case .hexagon: "hexagon"
        case .star: "star"
        case .arrowRight: "arrow.right"
        case .arrowLeft: "arrow.left"
        case .arrowUp: "arrow.up"
        case .arrowDown: "arrow.down"
        case .line: "line.diagonal"
        case .arrowLine: "arrow.up.right"
        case .callout: "bubble.left"
        case .textBox: "character.textbox"
        case .icon: "star.square"
        case .wordArt: "textformat"
        }
    }
}

enum WordArtStyle: String, Codable, CaseIterable, Identifiable {
    case gradient, outline, shadow, neon, retro
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct ShapeSpec: Codable, Equatable {
    var kind: ShapeKind = .rectangle
    var width: CGFloat = 160
    var height: CGFloat = 100
    var fillHex: String? = "#D7ECEF"
    var strokeHex: String? = "#13787F"
    var strokeWidth: CGFloat = 1.5
    var text = ""
    var textColorHex = "#1B1B1B"
    var fontFamily = "Helvetica Neue"
    var fontSize: CGFloat = 14
    var bold = false
    var rotation: CGFloat = 0
    var flipHorizontal = false
    var flipVertical = false
    var shadow = false
    var symbolName = "star.fill"
    var wordArtStyle: WordArtStyle = .gradient
    var cornerRadius: CGFloat = 12

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ShapeSpec()
        kind = c.value(.kind, default: d.kind)
        width = c.value(.width, default: d.width)
        height = c.value(.height, default: d.height)
        fillHex = c.value(.fillHex, default: d.fillHex)
        strokeHex = c.value(.strokeHex, default: d.strokeHex)
        strokeWidth = c.value(.strokeWidth, default: d.strokeWidth)
        text = c.value(.text, default: "")
        textColorHex = c.value(.textColorHex, default: d.textColorHex)
        fontFamily = c.value(.fontFamily, default: d.fontFamily)
        fontSize = c.value(.fontSize, default: d.fontSize)
        bold = c.value(.bold, default: false)
        rotation = c.value(.rotation, default: 0)
        flipHorizontal = c.value(.flipHorizontal, default: false)
        flipVertical = c.value(.flipVertical, default: false)
        shadow = c.value(.shadow, default: false)
        symbolName = c.value(.symbolName, default: d.symbolName)
        wordArtStyle = c.value(.wordArtStyle, default: .gradient)
        cornerRadius = c.value(.cornerRadius, default: 12)
    }
}

// MARK: Diagrams (SmartArt-style)

enum DiagramType: String, Codable, CaseIterable, Identifiable {
    case process, cycle, hierarchy, list, pyramid, flowchart, venn, timeline
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct DiagramItem: Codable, Equatable, Identifiable, Hashable {
    var id = UUID().uuidString
    var text: String
    var level = 0
}

struct DiagramSpec: Codable, Equatable {
    var type: DiagramType = .process
    var items: [DiagramItem] = [DiagramItem(text: "Plan"), DiagramItem(text: "Build"), DiagramItem(text: "Review"), DiagramItem(text: "Ship")]
    var colorHex = "#13787F"
    var width: CGFloat = 440
    var height: CGFloat = 220

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiagramSpec()
        type = c.value(.type, default: d.type)
        items = c.value(.items, default: d.items)
        colorHex = c.value(.colorHex, default: d.colorHex)
        width = c.value(.width, default: d.width)
        height = c.value(.height, default: d.height)
    }

    /// Items written as an indented outline (tabs or two spaces per level).
    var outline: String {
        get { items.map { String(repeating: "\t", count: $0.level) + $0.text }.joined(separator: "\n") }
        set {
            items = newValue.split(separator: "\n", omittingEmptySubsequences: true).map { line in
                var level = 0
                var rest = Substring(line)
                while let first = rest.first, first == "\t" || rest.hasPrefix("  ") {
                    level += 1
                    rest = first == "\t" ? rest.dropFirst() : rest.dropFirst(2)
                }
                return DiagramItem(text: rest.trimmingCharacters(in: .whitespaces), level: level)
            }.filter { !$0.text.isEmpty }
        }
    }
}

// MARK: Form controls

enum FormControlType: String, Codable, CaseIterable, Identifiable {
    case checkbox, dropdown, date
    var id: String { rawValue }
}

struct FormControlSpec: Codable, Equatable {
    var type: FormControlType = .checkbox
    var name = ""
    var checked = false
    var options: [String] = ["Choose an item"]
    var selected = 0
    var date: Date?
    var placeholder = "Click to choose a date"

    init(type: FormControlType) {
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.value(.type, default: .checkbox)
        name = c.value(.name, default: "")
        checked = c.value(.checked, default: false)
        options = c.value(.options, default: ["Choose an item"])
        selected = c.value(.selected, default: 0)
        date = c.value(.date, default: nil)
        placeholder = c.value(.placeholder, default: "Click to choose a date")
    }

    var displayText: String {
        switch type {
        case .checkbox: checked ? "☒" : "☐"
        case .dropdown: options.indices.contains(selected) ? options[selected] : (options.first ?? "")
        case .date: date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? placeholder
        }
    }
}

// MARK: Freehand drawing

struct DrawingStroke: Codable, Equatable {
    var points: [CGPoint]
    var colorHex = "#1B1B1B"
    var width: CGFloat = 2.5
    var highlighter = false
}

struct DrawingSpec: Codable, Equatable {
    var strokes: [DrawingStroke] = []
    var width: CGFloat = 400
    var height: CGFloat = 220

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokes = c.value(.strokes, default: [])
        width = c.value(.width, default: 400)
        height = c.value(.height, default: 220)
    }
}

// MARK: Embedded spreadsheet

struct SpreadsheetSpec: Codable, Equatable {
    /// Raw cell contents; values starting with "=" are formulas.
    var cells: [[String]] = [
        ["Item", "Qty", "Price", "Total"],
        ["Widgets", "3", "4.50", "=B2*C2"],
        ["Gadgets", "2", "12", "=B3*C3"],
        ["", "", "Sum", "=SUM(D2:D3)"],
    ]
    var headerRow = true
    var columnWidth: CGFloat = 90

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cells = c.value(.cells, default: SpreadsheetSpec().cells)
        headerRow = c.value(.headerRow, default: true)
        columnWidth = c.value(.columnWidth, default: 90)
    }
}

// MARK: Signature line

struct SignatureSpec: Codable, Equatable {
    var signer = ""
    var title = ""
    var instructions = ""
    /// Typed signature (shown in a script face) once signed.
    var signedName: String?
    var signedDate: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signer = c.value(.signer, default: "")
        title = c.value(.title, default: "")
        instructions = c.value(.instructions, default: "")
        signedName = c.value(.signedName, default: nil)
        signedDate = c.value(.signedDate, default: nil)
    }
}
