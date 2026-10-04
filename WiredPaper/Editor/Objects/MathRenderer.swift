import AppKit

/// A small TeX-style math layout engine: fractions, roots, scripts, big
/// operators, matrices, Greek letters and common symbols.
indirect enum MathNode {
    case text(String, italic: Bool)
    case symbol(String)
    case row([MathNode])
    case fraction(MathNode, MathNode)
    case root(MathNode, index: MathNode?)
    case scripts(base: MathNode, sup: MathNode?, sub: MathNode?)
    case bigOperator(String, sup: MathNode?, sub: MathNode?)
    case fenced(String, MathNode, String)
    case matrix([[MathNode]], left: String, right: String)
    case accent(MathNode, String)
    case function(String)
}

struct MathParser {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    static func parse(_ source: String) -> MathNode {
        var parser = MathParser(source)
        return parser.parseRow(until: [])
    }

    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]

    static let symbols: [String: String] = [
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "·", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠",
        "approx": "≈", "equiv": "≡", "sim": "∼", "propto": "∝", "infty": "∞", "partial": "∂", "nabla": "∇", "to": "→", "rightarrow": "→",
        "leftarrow": "←", "Rightarrow": "⇒", "Leftarrow": "⇐", "leftrightarrow": "↔", "Leftrightarrow": "⇔", "in": "∈", "notin": "∉",
        "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "cup": "∪", "cap": "∩", "emptyset": "∅", "forall": "∀", "exists": "∃",
        "neg": "¬", "land": "∧", "lor": "∨", "cdots": "⋯", "ldots": "…", "dots": "…", "degree": "°", "circ": "∘", "angle": "∠",
        "perp": "⊥", "parallel": "∥", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "prime": "′", "star": "⋆",
        "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}", ",": "\u{2009}", ";": "\u{2005}", " ": " ", "{": "{", "}": "}", "%": "%", "$": "$",
        "langle": "⟨", "rangle": "⟩", "mid": "∣", "setminus": "∖", "oplus": "⊕", "otimes": "⊗",
    ]

    static let bigOperators: [String: String] = [
        "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "bigcup": "⋃", "bigcap": "⋂", "coprod": "∐",
    ]

    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "log", "ln", "lg", "exp", "lim", "max", "min", "sup", "inf", "det", "gcd", "deg", "dim", "ker", "arg", "mod",
    ]

    private var atEnd: Bool { index >= characters.count }
    private var current: Character? { atEnd ? nil : characters[index] }

    private mutating func skipSpaces() {
        while let c = current, c == " " || c == "\n" { index += 1 }
    }

    mutating func parseRow(until terminators: Set<String>) -> MathNode {
        var items: [MathNode] = []
        while true {
            skipSpaces()
            guard let c = current else { break }
            if c == "}" && terminators.contains("}") { break }
            if c == "]" && terminators.contains("]") { break }
            if c == "&" && terminators.contains("&") { break }
            if c == "\\" {
                let save = index
                let command = readCommand()
                if terminators.contains("\\" + command) { index = save; break }
                if command == "\\" && terminators.contains("\\\\") { index = save; break }
                items.append(parseScripts(on: parseCommand(command)))
                continue
            }
            if c == "^" || c == "_" {
                // Script with no base.
                items.append(parseScripts(on: .text("", italic: false)))
                continue
            }
            items.append(parseScripts(on: parseAtom()))
        }
        return items.count == 1 ? items[0] : .row(items)
    }

    private mutating func readCommand() -> String {
        index += 1 // backslash
        guard let c = current else { return "" }
        if !c.isLetter { index += 1; return String(c) }
        var name = ""
        while let c = current, c.isLetter { name.append(c); index += 1 }
        return name
    }

    private mutating func parseGroup() -> MathNode {
        skipSpaces()
        guard let c = current else { return .row([]) }
        if c == "{" {
            index += 1
            let node = parseRow(until: ["}"])
            if current == "}" { index += 1 }
            return node
        }
        if c == "\\" {
            let command = readCommand()
            return parseCommand(command)
        }
        index += 1
        return atom(for: c)
    }

    private mutating func parseOptional() -> MathNode? {
        skipSpaces()
        guard current == "[" else { return nil }
        index += 1
        let node = parseRow(until: ["]"])
        if current == "]" { index += 1 }
        return node
    }

    private mutating func parseAtom() -> MathNode {
        let c = characters[index]
        if c == "{" { return parseGroup() }
        index += 1
        if c.isNumber || c == "." {
            var number = String(c)
            while let next = current, next.isNumber || (next == "." && characters.indices.contains(index + 1) && characters[index + 1].isNumber) {
                number.append(next)
                index += 1
            }
            return .text(number, italic: false)
        }
        return atom(for: c)
    }

    private func atom(for c: Character) -> MathNode {
        if c.isLetter { return .text(String(c), italic: true) }
        switch c {
        case "-": return .symbol("−")
        case "*": return .symbol("∗")
        case "'": return .text("′", italic: false)
        default: return .symbol(String(c))
        }
    }

    private mutating func parseScripts(on base: MathNode) -> MathNode {
        var sup: MathNode?, sub: MathNode?
        while true {
            skipSpaces()
            if current == "^", sup == nil { index += 1; sup = parseGroup() }
            else if current == "_", sub == nil { index += 1; sub = parseGroup() }
            else { break }
        }
        guard sup != nil || sub != nil else { return base }
        if case let .bigOperator(op, _, _) = base { return .bigOperator(op, sup: sup, sub: sub) }
        if case let .function(name) = base, name == "lim" || name == "max" || name == "min" || name == "sup" || name == "inf" {
            return .bigOperator(name, sup: sup, sub: sub)
        }
        return .scripts(base: base, sup: sup, sub: sub)
    }

    private mutating func parseCommand(_ command: String) -> MathNode {
        if let letter = Self.greek[command] {
            return .text(letter, italic: command.first?.isLowercase ?? false)
        }
        if let symbol = Self.symbols[command] { return .symbol(symbol) }
        if let op = Self.bigOperators[command] { return .bigOperator(op, sup: nil, sub: nil) }
        if Self.functions.contains(command) { return .function(command) }
        switch command {
        case "frac", "dfrac", "tfrac": return .fraction(parseGroup(), parseGroup())
        case "binom": return .fenced("(", .fraction(parseGroup(), parseGroup()), ")") // rendered without bar below
        case "sqrt":
            let index = parseOptional()
            return .root(parseGroup(), index: index)
        case "left":
            let open = readDelimiter()
            let body = parseRow(until: ["\\right"])
            _ = readCommand() // \right
            let close = readDelimiter()
            return .fenced(open, body, close)
        case "hat": return .accent(parseGroup(), "^")
        case "bar", "overline": return .accent(parseGroup(), "‾")
        case "vec": return .accent(parseGroup(), "→")
        case "dot": return .accent(parseGroup(), "˙")
        case "tilde": return .accent(parseGroup(), "~")
        case "text", "mathrm", "operatorname":
            if case let .text(value, _) = flatten(parseGroup()) { return .text(value, italic: false) }
            return .row([])
        case "mathbf", "mathit", "mathbb", "mathcal":
            return transform(parseGroup(), style: command)
        case "begin":
            return parseEnvironment()
        default:
            return .text(command, italic: false)
        }
    }

    private mutating func readDelimiter() -> String {
        skipSpaces()
        guard let c = current else { return "" }
        if c == "\\" {
            let command = readCommand()
            switch command {
            case "{": return "{"
            case "}": return "}"
            case "langle": return "⟨"
            case "rangle": return "⟩"
            case "|": return "‖"
            default: return ""
            }
        }
        index += 1
        return c == "." ? "" : String(c)
    }

    private mutating func parseEnvironment() -> MathNode {
        guard case let .text(name, _) = flatten(parseGroup()) else { return .row([]) }
        var rows: [[MathNode]] = [[]]
        while !atEnd {
            let cell = parseRow(until: ["&", "\\\\", "\\end"])
            rows[rows.count - 1].append(cell)
            if current == "&" { index += 1; continue }
            let save = index
            let command = readCommand()
            if command == "\\" { rows.append([]); continue }
            if command == "end" { _ = parseGroup(); break }
            index = save + 1
        }
        rows.removeAll { $0.count == 1 && isEmpty($0[0]) }
        switch name {
        case "pmatrix": return .matrix(rows, left: "(", right: ")")
        case "bmatrix": return .matrix(rows, left: "[", right: "]")
        case "vmatrix": return .matrix(rows, left: "|", right: "|")
        case "cases": return .matrix(rows, left: "{", right: "")
        default: return .matrix(rows, left: "", right: "")
        }
    }

    private func isEmpty(_ node: MathNode) -> Bool {
        if case let .row(items) = node { return items.isEmpty }
        return false
    }

    /// Collapses a node made only of text into a single text node.
    private func flatten(_ node: MathNode) -> MathNode {
        func collect(_ node: MathNode) -> String? {
            switch node {
            case let .text(value, _), let .symbol(value): return value
            case let .row(items):
                var result = ""
                for item in items { guard let part = collect(item) else { return nil }; result += part }
                return result
            default: return nil
            }
        }
        return collect(node).map { .text($0, italic: false) } ?? node
    }

    private func transform(_ node: MathNode, style: String) -> MathNode {
        guard case let .text(value, _) = flatten(node) else { return node }
        switch style {
        case "mathbb":
            let map: [Character: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ"]
            return .text(value.map { map[$0] ?? String($0) }.joined(), italic: false)
        case "mathcal":
            let map: [Character: String] = ["L": "ℒ", "F": "ℱ", "H": "ℋ", "E": "ℰ", "B": "ℬ", "M": "ℳ", "R": "ℛ", "I": "ℐ"]
            return .text(value.map { map[$0] ?? String($0) }.joined(), italic: false)
        case "mathit": return .text(value, italic: true)
        default: return .symbol(value) // bold is applied as upright symbol text
        }
    }
}

/// A laid-out box: width, ascent above the baseline, descent below, and a
/// drawing closure positioned at the baseline origin.
struct MathBox {
    var width: CGFloat
    var ascent: CGFloat
    var descent: CGFloat
    var draw: (CGPoint) -> Void

    var height: CGFloat { ascent + descent }

    static let empty = MathBox(width: 0, ascent: 0, descent: 0) { _ in }
}

enum MathRenderer {
    static func image(_ spec: EquationSpec) -> NSImage {
        let box = layout(MathParser.parse(spec.latex), size: spec.fontSize, color: .black)
        let padding: CGFloat = 4
        let size = CGSize(width: ceil(max(box.width, 4) + padding * 2), height: ceil(max(box.height, 4) + padding * 2))
        return ObjectRenderer.draw(size: size) { _ in
            box.draw(CGPoint(x: padding, y: padding + box.ascent))
        }
    }

    static func layout(_ node: MathNode, size: CGFloat, color: NSColor) -> MathBox {
        let body = NSFont(name: "STIX Two Math", size: size) ?? NSFont(name: "Cambria Math", size: size) ?? NSFont(name: "Times New Roman", size: size) ?? .systemFont(ofSize: size)
        let axis = size * 0.25 // math axis height above baseline

        func textBox(_ string: String, italic: Bool, font: NSFont? = nil, spacing: CGFloat = 0) -> MathBox {
            var font = font ?? body
            if italic {
                let converted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                font = converted.fontDescriptor.symbolicTraits.contains(.italic)
                    ? converted
                    : NSFont(name: "STIXTwoText-Italic", size: font.pointSize) ?? NSFont(name: "TimesNewRomanPS-ItalicMT", size: font.pointSize) ?? converted
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let width = (string as NSString).size(withAttributes: attributes).width
            return MathBox(width: width + spacing * 2, ascent: font.ascender, descent: -font.descender) { origin in
                (string as NSString).draw(at: CGPoint(x: origin.x + spacing, y: origin.y - font.ascender), withAttributes: attributes)
            }
        }

        func hstack(_ boxes: [MathBox]) -> MathBox {
            let width = boxes.map(\.width).reduce(0, +)
            let ascent = boxes.map(\.ascent).max() ?? 0
            let descent = boxes.map(\.descent).max() ?? 0
            return MathBox(width: width, ascent: ascent, descent: descent) { origin in
                var x = origin.x
                for box in boxes { box.draw(CGPoint(x: x, y: origin.y)); x += box.width }
            }
        }

        func line(from: CGPoint, to: CGPoint, width: CGFloat) {
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.lineWidth = width
            path.stroke()
        }

        /// A stretchy delimiter drawn to cover `ascent`/`descent`.
        func delimiter(_ symbol: String, ascent: CGFloat, descent: CGFloat) -> MathBox {
            guard !symbol.isEmpty else { return .empty }
            let height = ascent + descent
            if height <= size * 1.25 { return textBox(symbol, italic: false) }
            let width = size * 0.42
            let stroke = max(size / 18, 0.9)
            return MathBox(width: width, ascent: ascent, descent: descent) { origin in
                let top = origin.y - ascent + 1, bottom = origin.y + descent - 1
                let midY = (top + bottom) / 2
                let path = NSBezierPath()
                path.lineWidth = stroke
                path.lineCapStyle = .round
                let l = origin.x + width * 0.25, r = origin.x + width * 0.75
                switch symbol {
                case "(":
                    path.move(to: CGPoint(x: r, y: top))
                    path.curve(to: CGPoint(x: r, y: bottom), controlPoint1: CGPoint(x: l - width * 0.2, y: top + height * 0.25), controlPoint2: CGPoint(x: l - width * 0.2, y: bottom - height * 0.25))
                case ")":
                    path.move(to: CGPoint(x: l, y: top))
                    path.curve(to: CGPoint(x: l, y: bottom), controlPoint1: CGPoint(x: r + width * 0.2, y: top + height * 0.25), controlPoint2: CGPoint(x: r + width * 0.2, y: bottom - height * 0.25))
                case "[":
                    path.move(to: CGPoint(x: r, y: top)); path.line(to: CGPoint(x: l, y: top)); path.line(to: CGPoint(x: l, y: bottom)); path.line(to: CGPoint(x: r, y: bottom))
                case "]":
                    path.move(to: CGPoint(x: l, y: top)); path.line(to: CGPoint(x: r, y: top)); path.line(to: CGPoint(x: r, y: bottom)); path.line(to: CGPoint(x: l, y: bottom))
                case "|", "‖":
                    path.move(to: CGPoint(x: origin.x + width / 2, y: top)); path.line(to: CGPoint(x: origin.x + width / 2, y: bottom))
                    if symbol == "‖" { path.move(to: CGPoint(x: origin.x + width / 2 + 3, y: top)); path.line(to: CGPoint(x: origin.x + width / 2 + 3, y: bottom)) }
                case "{":
                    path.move(to: CGPoint(x: r, y: top))
                    path.curve(to: CGPoint(x: l, y: midY), controlPoint1: CGPoint(x: l, y: top), controlPoint2: CGPoint(x: r - width * 0.2, y: midY))
                    path.curve(to: CGPoint(x: r, y: bottom), controlPoint1: CGPoint(x: r - width * 0.2, y: midY), controlPoint2: CGPoint(x: l, y: bottom))
                case "}":
                    path.move(to: CGPoint(x: l, y: top))
                    path.curve(to: CGPoint(x: r, y: midY), controlPoint1: CGPoint(x: r, y: top), controlPoint2: CGPoint(x: l + width * 0.2, y: midY))
                    path.curve(to: CGPoint(x: l, y: bottom), controlPoint1: CGPoint(x: l + width * 0.2, y: midY), controlPoint2: CGPoint(x: r, y: bottom))
                case "⟨":
                    path.move(to: CGPoint(x: r, y: top)); path.line(to: CGPoint(x: l, y: midY)); path.line(to: CGPoint(x: r, y: bottom))
                case "⟩":
                    path.move(to: CGPoint(x: l, y: top)); path.line(to: CGPoint(x: r, y: midY)); path.line(to: CGPoint(x: l, y: bottom))
                default:
                    textBox(symbol, italic: false).draw(CGPoint(x: origin.x, y: origin.y))
                }
                color.setStroke()
                path.stroke()
            }
        }

        switch node {
        case let .text(value, italic):
            return textBox(value, italic: italic)
        case let .function(name):
            return textBox(name, italic: false, spacing: size * 0.08)
        case let .symbol(value):
            let spaced: Set<String> = ["=", "+", "−", "±", "∓", "×", "÷", "≤", "≥", "≠", "≈", "≡", "→", "⇒", "⇔", "∈", "⊂", "⊆", "<", ">", "∼", "∝", "·"]
            return textBox(value, italic: false, spacing: spaced.contains(value) ? size * 0.18 : 0)
        case let .row(items):
            return hstack(items.map { layout($0, size: size, color: color) })
        case let .fraction(numerator, denominator):
            let small = size * 0.85
            let top = layout(numerator, size: small, color: color)
            let bottom = layout(denominator, size: small, color: color)
            let width = max(top.width, bottom.width) + size * 0.3
            let gap = size * 0.14
            let rule = max(size / 20, 0.8)
            return MathBox(width: width, ascent: axis + gap + top.height, descent: max(bottom.height + gap - axis, 0)) { origin in
                let barY = origin.y - axis
                top.draw(CGPoint(x: origin.x + (width - top.width) / 2, y: barY - gap - top.descent))
                bottom.draw(CGPoint(x: origin.x + (width - bottom.width) / 2, y: barY + gap + bottom.ascent))
                line(from: CGPoint(x: origin.x + size * 0.08, y: barY), to: CGPoint(x: origin.x + width - size * 0.08, y: barY), width: rule)
            }
        case let .root(radicand, index):
            let inner = layout(radicand, size: size, color: color)
            let indexBox = index.map { layout($0, size: size * 0.55, color: color) }
            let gap = size * 0.12
            let hook = size * 0.55
            let lead = max(indexBox.map { $0.width - hook * 0.4 } ?? 0, 0)
            let rule = max(size / 20, 0.8)
            return MathBox(width: lead + hook + inner.width + size * 0.1, ascent: inner.ascent + gap + rule, descent: inner.descent) { origin in
                let topY = origin.y - inner.ascent - gap
                let bottomY = origin.y + inner.descent
                let x = origin.x + lead
                color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = rule
                path.lineJoinStyle = .round
                path.move(to: CGPoint(x: x, y: bottomY - inner.height * 0.45))
                path.line(to: CGPoint(x: x + hook * 0.3, y: bottomY - inner.height * 0.55))
                path.line(to: CGPoint(x: x + hook * 0.6, y: bottomY))
                path.line(to: CGPoint(x: x + hook, y: topY))
                path.line(to: CGPoint(x: x + hook + inner.width + size * 0.1, y: topY))
                path.stroke()
                inner.draw(CGPoint(x: x + hook, y: origin.y))
                indexBox?.draw(CGPoint(x: origin.x, y: bottomY - inner.height * 0.5 - (indexBox?.descent ?? 0)))
            }
        case let .scripts(base, sup, sub):
            let baseBox = layout(base, size: size, color: color)
            let supBox = sup.map { layout($0, size: size * 0.68, color: color) }
            let subBox = sub.map { layout($0, size: size * 0.68, color: color) }
            let supShift = max(baseBox.ascent - size * 0.35, size * 0.4)
            let subShift = max(baseBox.descent, size * 0.18)
            let scriptWidth = max(supBox?.width ?? 0, subBox?.width ?? 0)
            let ascent = max(baseBox.ascent, supShift + (supBox?.ascent ?? 0))
            let descent = max(baseBox.descent, subShift + (subBox?.descent ?? 0))
            return MathBox(width: baseBox.width + scriptWidth + size * 0.05, ascent: ascent, descent: descent) { origin in
                baseBox.draw(origin)
                supBox?.draw(CGPoint(x: origin.x + baseBox.width + size * 0.03, y: origin.y - supShift))
                subBox?.draw(CGPoint(x: origin.x + baseBox.width + size * 0.03, y: origin.y + subShift))
            }
        case let .bigOperator(op, sup, sub):
            let isWord = op.count > 1
            let opBox = isWord ? textBox(op, italic: false) : textBox(op, italic: false, font: body.withSize(size * 1.6))
            let supBox = sup.map { layout($0, size: size * 0.62, color: color) }
            let subBox = sub.map { layout($0, size: size * 0.62, color: color) }
            // Integrals put limits at the side; others above/below.
            if op == "∫" || op == "∬" || op == "∭" || op == "∮" {
                let width = opBox.width + max(supBox?.width ?? 0, subBox?.width ?? 0) + size * 0.15
                return MathBox(width: width, ascent: max(opBox.ascent, (supBox?.height ?? 0) + size * 0.5), descent: max(opBox.descent, (subBox?.height ?? 0) + size * 0.1)) { origin in
                    opBox.draw(CGPoint(x: origin.x, y: origin.y + size * 0.25))
                    supBox?.draw(CGPoint(x: origin.x + opBox.width, y: origin.y - opBox.ascent + (supBox?.ascent ?? 0) + size * 0.3))
                    subBox?.draw(CGPoint(x: origin.x + opBox.width * 0.7, y: origin.y + opBox.descent + size * 0.1))
                }
            }
            let width = max(opBox.width, supBox?.width ?? 0, subBox?.width ?? 0) + size * 0.2
            let opShift = isWord ? 0 : size * 0.3
            let ascent = opBox.ascent - opShift + (supBox.map { $0.height + size * 0.05 } ?? 0)
            let descent = opBox.descent + opShift + (subBox.map { $0.height + size * 0.05 } ?? 0)
            return MathBox(width: width, ascent: ascent, descent: descent) { origin in
                let center = origin.x + width / 2
                let opY = origin.y + opShift
                opBox.draw(CGPoint(x: center - opBox.width / 2, y: opY))
                if let supBox { supBox.draw(CGPoint(x: center - supBox.width / 2, y: opY - opBox.ascent - size * 0.05 - supBox.descent)) }
                if let subBox { subBox.draw(CGPoint(x: center - subBox.width / 2, y: opY + opBox.descent + size * 0.05 + subBox.ascent)) }
            }
        case let .fenced(open, body, close):
            let inner = layout(body, size: size, color: color)
            let ascent = max(inner.ascent, size * 0.75), descent = max(inner.descent, size * 0.25)
            return hstack([delimiter(open, ascent: ascent, descent: descent), inner, delimiter(close, ascent: ascent, descent: descent)])
        case let .matrix(rows, left, right):
            let cells = rows.map { $0.map { layout($0, size: size, color: color) } }
            let columnCount = cells.map(\.count).max() ?? 0
            let columnWidths = (0..<columnCount).map { column in cells.compactMap { $0.indices.contains(column) ? $0[column].width : nil }.max() ?? 0 }
            let rowHeights = cells.map { row in (row.map(\.ascent).max() ?? size * 0.7, row.map(\.descent).max() ?? size * 0.2) }
            let columnGap = size * 0.8, rowGap = size * 0.3
            let width = columnWidths.reduce(0, +) + columnGap * CGFloat(max(columnCount - 1, 0))
            let height = rowHeights.map { $0.0 + $0.1 }.reduce(0, +) + rowGap * CGFloat(max(rows.count - 1, 0))
            let isCases = left == "{" && right.isEmpty
            let grid = MathBox(width: width, ascent: height / 2 + axis, descent: height / 2 - axis) { origin in
                var y = origin.y - axis - height / 2
                for (rowIndex, row) in cells.enumerated() {
                    let baseline = y + rowHeights[rowIndex].0
                    var x = origin.x
                    for (column, cell) in row.enumerated() {
                        let offset = isCases ? 0 : (columnWidths[column] - cell.width) / 2
                        cell.draw(CGPoint(x: x + offset, y: baseline))
                        x += columnWidths[column] + columnGap
                    }
                    y = baseline + rowHeights[rowIndex].1 + rowGap
                }
            }
            let pad = MathBox(width: size * 0.15, ascent: 0, descent: 0) { _ in }
            return hstack([delimiter(left, ascent: grid.ascent, descent: grid.descent), pad, grid, pad, delimiter(right, ascent: grid.ascent, descent: grid.descent)])
        case let .accent(base, mark):
            let inner = layout(base, size: size, color: color)
            let markBox = textBox(mark, italic: false, font: body.withSize(size * 0.7))
            let lift = size * 0.28
            return MathBox(width: max(inner.width, markBox.width), ascent: inner.ascent + lift, descent: inner.descent) { origin in
                inner.draw(origin)
                if mark == "‾" {
                    line(from: CGPoint(x: origin.x + 1, y: origin.y - inner.ascent + size * 0.12), to: CGPoint(x: origin.x + inner.width - 1, y: origin.y - inner.ascent + size * 0.12), width: max(size / 20, 0.8))
                } else {
                    markBox.draw(CGPoint(x: origin.x + (inner.width - markBox.width) / 2, y: origin.y - inner.ascent + markBox.ascent * 0.55))
                }
            }
        }
    }
}
