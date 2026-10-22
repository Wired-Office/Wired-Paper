import AppKit

/// Markdown (`.md`): headings, emphasis, code, quotes, lists, links and tables
/// become Wired Paper styles on read, and are written back as CommonMark.
/// Anything Markdown can't express (fonts, colors, images…) is dropped on save.
struct MarkdownCodec: DocumentCodec {
    func read(from fileWrapper: FileWrapper, defaultAttributes: [NSAttributedString.Key: Any]) throws -> DocumentContents {
        guard let data = fileWrapper.regularFileContents else {
            throw WiredPaperError.corruptDocument("The file is empty or unreadable.")
        }
        return DocumentContents(
            text: MarkdownReader.attributedString(from: PlainTextCodec.decode(data)),
            pageSetup: nil,
            metadata: nil
        )
    }

    func write(_ contents: DocumentContents) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(MarkdownWriter.markdown(from: contents.text).utf8))
    }
}

// MARK: - Reading

enum MarkdownReader {
    static func attributedString(from source: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source, attributes: StyleCatalog.attributes(for: .normal))
        }

        let result = NSMutableAttributedString()
        var lists: [Int: NSTextList] = [:]          // list block identity → its NSTextList
        var markedItems: Set<Int> = []              // list items whose marker is already written
        var previousIntent: PresentationIntent?
        var blockAttributes = StyleCatalog.attributes(for: .normal)

        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let intent = run.presentationIntent

            if intent != previousIntent || result.length == 0 {
                if result.length > 0 {
                    let sameRow = tableRow(of: intent) != nil && tableRow(of: intent) == tableRow(of: previousIntent)
                    result.append(NSAttributedString(string: sameRow ? "\t" : "\n", attributes: blockAttributes))
                }
                let block = Block(intent: intent, lists: &lists, markedItems: &markedItems)
                blockAttributes = block.attributes
                if let marker = block.marker {
                    result.append(NSAttributedString(string: marker, attributes: blockAttributes))
                }
                previousIntent = intent
            }

            let isCode = intent?.components.contains { isCodeBlock($0.kind) } ?? false
            if isCode {
                while text.hasSuffix("\n") { text.removeLast() }
            } else {
                // A hard line break inside a paragraph, not a new paragraph.
                text = text.replacingOccurrences(of: "\n", with: "\u{2028}")
            }
            result.append(NSAttributedString(string: text, attributes: inlineAttributes(for: run, base: blockAttributes, isHeaderRow: isHeaderRow(intent))))
        }
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n", attributes: blockAttributes))
        }
        return result
    }

    private static func isCodeBlock(_ kind: PresentationIntent.Kind) -> Bool {
        if case .codeBlock = kind { return true }
        return false
    }

    private static func tableRow(of intent: PresentationIntent?) -> Int? {
        intent?.components.first { if case .tableRow = $0.kind { true } else if case .tableHeaderRow = $0.kind { true } else { false } }?.identity
    }

    private static func isHeaderRow(_ intent: PresentationIntent?) -> Bool {
        intent?.components.contains { if case .tableHeaderRow = $0.kind { true } else { false } } ?? false
    }

    private static func inlineAttributes(
        for run: AttributedString.Runs.Run,
        base: [NSAttributedString.Key: Any],
        isHeaderRow: Bool
    ) -> [NSAttributedString.Key: Any] {
        var attributes = base
        let inline = run.inlinePresentationIntent ?? []
        var font = (base[.font] as? NSFont) ?? StyleCatalog.bodyFont
        if inline.contains(.code) {
            let code = StyleCatalog.font(for: .code)
            font = NSFont(descriptor: code.fontDescriptor, size: font.pointSize) ?? .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        }
        if inline.contains(.stronglyEmphasized) || isHeaderRow {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if inline.contains(.emphasized) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        attributes[.font] = font
        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = run.link {
            attributes[.link] = link
        }
        return attributes
    }

    /// The paragraph style, list membership and marker of one Markdown block.
    private struct Block {
        var attributes: [NSAttributedString.Key: Any]
        var marker: String?

        init(intent: PresentationIntent?, lists: inout [Int: NSTextList], markedItems: inout Set<Int>) {
            var kind = ParagraphStyleKind.normal
            var listBlocks: [(identity: Int, kind: ListKind)] = []   // innermost first
            var item: (identity: Int, ordinal: Int)?

            for component in intent?.components ?? [] {
                switch component.kind {
                case .header(let level):
                    kind = .heading(level)
                case .codeBlock:
                    if kind == .normal { kind = .code }
                case .blockQuote:
                    if kind == .normal { kind = .quote }
                case .listItem(let ordinal):
                    if item == nil { item = (component.identity, ordinal) }
                case .orderedList:
                    listBlocks.append((component.identity, .numbered))
                case .unorderedList:
                    listBlocks.append((component.identity, .bullet))
                default:
                    break
                }
            }

            attributes = StyleCatalog.attributes(for: kind)
            guard !listBlocks.isEmpty, let item else { return }
            // Outermost first; nested levels cycle marker shapes like lists made in the editor.
            let textLists = listBlocks.reversed().enumerated().map { level, block in
                let list = lists[block.identity] ?? NSTextList(markerFormat: ListFormatter.format(for: block.kind, level: level), options: 0)
                lists[block.identity] = list
                return list
            }
            let base = attributes[.paragraphStyle] as? NSParagraphStyle
            if markedItems.insert(item.identity).inserted {
                attributes[.paragraphStyle] = ListFormatter.listParagraphStyle(basedOn: base, lists: textLists)
                marker = ListFormatter.marker(for: textLists[textLists.count - 1], number: item.ordinal)
            } else {
                // A further paragraph of the same item: indented, without a marker.
                let style = ((base ?? .default).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                let indent = ListFormatter.textIndent + CGFloat(textLists.count - 1) * ListFormatter.levelIndent
                style.headIndent = indent
                style.firstLineHeadIndent = indent
                attributes[.paragraphStyle] = style
            }
        }
    }
}

// MARK: - Writing

enum MarkdownWriter {
    static func markdown(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        var output: [String] = []
        var previousList: NSTextList?              // outermost list of the previous paragraph
        var codeLines: [String] = []

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            let fence = codeLines.contains { $0.contains("```") } ? "~~~" : "```"
            output.append(([fence] + codeLines + [fence]).joined(separator: "\n"))
            codeLines = []
        }

        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let paragraph = NSMutableAttributedString(attributedString: text.attributedSubstring(from: range))
            let styleID = (range.length > 0 ? text.attribute(.wpParagraphStyle, at: range.location, effectiveRange: nil) as? String : nil) ?? "normal"
            let paragraphStyle = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            let kind = ParagraphStyleKind(rawValue: styleID)

            if kind == .code {
                codeLines.append(paragraph.string.replacingOccurrences(of: "\u{FFFC}", with: ""))
                previousList = nil
                return
            }
            flushCode()

            // Lists: the marker is spelled out in the text; turn it into Markdown syntax.
            let textLists = paragraphStyle?.textLists ?? []
            var prefix = ""
            if let list = textLists.last {
                let markerLength = ListFormatter.stripMarker(from: paragraph, style: paragraphStyle)
                let marker = text.attributedSubstring(from: NSRange(location: range.location, length: markerLength)).string
                    .trimmingCharacters(in: .whitespaces)
                let indent = String(repeating: "    ", count: textLists.count - 1)
                if ListKind(markerFormat: list.markerFormat) == .numbered {
                    let number = marker.prefix { $0.isNumber }
                    prefix = indent + (number.isEmpty ? "1" : String(number)) + ". "
                } else {
                    prefix = indent + "- "
                }
            } else if let level = kind?.headingLevel {
                prefix = String(repeating: "#", count: min(level, 6)) + " "
            } else if kind == .title {
                prefix = "# "
            } else if kind == .quote {
                prefix = "> "
            }

            let isHeading = kind?.headingLevel != nil || kind == .title
            let baseFont = StyleCatalog.standard.font(for: styleID)
            var line = inlineMarkdown(paragraph, baseFont: baseFont, skipEmphasis: isHeading)
            if prefix.isEmpty || kind == .quote { line = escapeLineStart(line) }
            line = line.replacingOccurrences(of: "\u{2028}", with: "  \n" + (kind == .quote ? "> " : ""))

            let isListItem = !textLists.isEmpty
            if line.trimmingCharacters(in: .whitespaces).isEmpty && !isListItem {
                previousList = nil
                return
            }
            // Items of one list stay together; a different list starts a new block.
            if isListItem, previousList != nil, previousList === textLists.first, let last = output.popLast() {
                output.append(last + "\n" + prefix + line)
            } else {
                output.append(prefix + line)
            }
            previousList = textLists.first
        }
        flushCode()
        return output.isEmpty ? "" : output.joined(separator: "\n\n") + "\n"
    }

    private static func inlineMarkdown(_ paragraph: NSAttributedString, baseFont: NSFont, skipEmphasis: Bool) -> String {
        let baseTraits = NSFontManager.shared.traits(of: baseFont)
        var result = ""
        paragraph.enumerateAttributes(in: NSRange(location: 0, length: paragraph.length)) { attributes, range, _ in
            let raw = (paragraph.string as NSString).substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !raw.isEmpty else { return }
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let isCode = font.map { $0.isFixedPitch && !baseFont.isFixedPitch } ?? false

            // Emphasis markers can't sit next to whitespace, so keep spaces outside them.
            let core = raw.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { result += raw; return }
            let leading = String(raw.prefix { $0 == " " || $0 == "\t" })
            let trailing = String(raw.reversed().prefix { $0 == " " || $0 == "\t" })

            var piece: String
            if isCode {
                piece = core.contains("`") ? "`` \(core) ``" : "`\(core)`"
            } else {
                piece = escape(core)
                if !skipEmphasis {
                    let bold = traits.contains(.boldFontMask) && !baseTraits.contains(.boldFontMask)
                    let italic = traits.contains(.italicFontMask) && !baseTraits.contains(.italicFontMask)
                    if italic { piece = "*\(piece)*" }
                    if bold { piece = "**\(piece)**" }
                }
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { piece = "~~\(piece)~~" }
            }
            if let link = attributes[.link] {
                let url = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                if !url.isEmpty { piece = "[\(piece)](\(url.replacingOccurrences(of: " ", with: "%20")))" }
            }
            result += leading + piece + trailing
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// Escapes characters that would otherwise turn a plain paragraph into a heading, list or quote.
    private static func escapeLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#>+-=".contains(first) { return "\\" + line }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, let next = line.dropFirst(digits.count).first, next == "." || next == ")" {
            return digits + "\\" + line.dropFirst(digits.count)
        }
        return line
    }
}
