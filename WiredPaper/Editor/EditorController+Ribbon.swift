import AppKit

/// Commands behind the ribbon that have no menu equivalent yet: underline
/// styles, paragraph sorting, formatting marks, quick borders and shading,
/// paragraph spacing presets and sensitivity labels.
extension EditorController {
    // MARK: Underline

    enum UnderlineKind: String, CaseIterable, Identifiable {
        case single, double, thick, dotted, dashed, dashDot, words
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .single: "Single"
            case .double: "Double"
            case .thick: "Thick"
            case .dotted: "Dotted"
            case .dashed: "Dashed"
            case .dashDot: "Dot-Dash"
            case .words: "Words Only"
            }
        }

        var style: NSUnderlineStyle {
            switch self {
            case .single: .single
            case .double: .double
            case .thick: .thick
            case .dotted: [.single, .patternDot]
            case .dashed: [.single, .patternDash]
            case .dashDot: [.single, .patternDashDot]
            case .words: [.single, .byWord]
            }
        }
    }

    /// Applies an underline style (nil removes underlining).
    func setUnderline(_ kind: UnderlineKind?) {
        TextFormatter.setAttribute(.underlineStyle, to: kind.map { $0.style.rawValue }, in: textView, actionName: "Underline")
        refreshState()
    }

    func setUnderlineColor(_ color: NSColor?) {
        TextFormatter.setAttribute(.underlineColor, to: color, in: textView, actionName: "Underline Color")
        refreshState()
    }

    // MARK: Superscript & subscript

    func toggleSuperscript() {
        let textView = self.textView
        if formatting.isSuperscript { textView.unscript(nil) } else { textView.superscript(nil) }
        refreshState()
    }

    func toggleSubscript() {
        let textView = self.textView
        if formatting.isSubscript { textView.unscript(nil) } else { textView.subscript(nil) }
        refreshState()
    }

    // MARK: Sorting

    /// Sorts the selected paragraphs alphabetically (numbers compare by value).
    @discardableResult
    func sortParagraphs(ascending: Bool) -> Bool {
        let textView = self.textView
        let string = textStorage.string as NSString
        let range = string.paragraphRange(for: textView.selectedRange())
        guard range.length > 0 else { NSSound.beep(); return false }

        var paragraphs: [NSAttributedString] = []
        string.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            // Keep each paragraph's own attributes; terminators are re-added below.
            paragraphs.append(self.textStorage.attributedSubstring(from: substringRange))
            _ = enclosingRange
        }
        guard paragraphs.count > 1 else { NSSound.beep(); return false }
        let endsWithNewline = string.substring(with: range).hasSuffix("\n")
        let sorted = paragraphs.enumerated().sorted { a, b in
            let order = a.element.string.localizedStandardCompare(b.element.string)
            if order == .orderedSame { return a.offset < b.offset }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.element)

        let result = NSMutableAttributedString()
        for (index, paragraph) in sorted.enumerated() {
            result.append(paragraph)
            if index < sorted.count - 1 || endsWithNewline {
                var attributes = paragraph.length > 0 ? paragraph.attributes(at: max(paragraph.length - 1, 0), effectiveRange: nil) : textView.typingAttributes
                attributes.removeValue(forKey: .attachment)
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        guard textView.shouldChangeText(in: range, replacementString: result.string) else { return false }
        textStorage.replaceCharacters(in: range, with: result)
        textView.didChangeText()
        textView.undoManager?.setActionName(ascending ? "Sort Ascending" : "Sort Descending")
        textView.setSelectedRange(NSRange(location: range.location, length: result.length))
        return true
    }

    // MARK: Formatting marks

    var showsFormattingMarks: Bool { layoutManager.showsFormattingMarks }

    func toggleFormattingMarks() {
        layoutManager.showsFormattingMarks.toggle()
        objectWillChange.send()
        for textView in pagesView.allTextViews { textView.needsDisplay = true }
    }

    // MARK: Quick borders & shading

    enum BorderPreset: String, CaseIterable, Identifiable {
        case bottom, top, left, right, none, all, outside
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .bottom: "Bottom Border"
            case .top: "Top Border"
            case .left: "Left Border"
            case .right: "Right Border"
            case .none: "No Border"
            case .all: "All Borders"
            case .outside: "Outside Borders"
            }
        }

        var symbol: String {
            switch self {
            case .bottom: "square.bottomhalf.filled"
            case .top: "square.tophalf.filled"
            case .left: "square.lefthalf.filled"
            case .right: "square.righthalf.filled"
            case .none: "square.dashed"
            case .all, .outside: "square"
            }
        }
    }

    var currentBorders: ParagraphBorderSettings { ParagraphBorders.current(in: textView) }

    /// Toggles one edge (like Word's border button) or applies a whole preset.
    func applyBorderPreset(_ preset: BorderPreset) {
        var settings = ParagraphBorders.current(in: textView)
        switch preset {
        case .bottom: settings.bottom.toggle()
        case .top: settings.top.toggle()
        case .left: settings.left.toggle()
        case .right: settings.right.toggle()
        case .none: settings.top = false; settings.bottom = false; settings.left = false; settings.right = false
        case .all, .outside: settings.top = true; settings.bottom = true; settings.left = true; settings.right = true
        }
        ParagraphBorders.apply(settings, in: textView)
        refreshState()
    }

    func setParagraphShading(_ color: NSColor?) {
        var settings = ParagraphBorders.current(in: textView)
        settings.shading = color
        ParagraphBorders.apply(settings, in: textView)
        refreshState()
    }

    // MARK: Paragraph spacing & indents

    func adjustParagraphSpacing(before: Bool, add: Bool) {
        var settings = currentParagraphSettings()
        if before { settings.spacingBefore = add ? 12 : 0 } else { settings.spacingAfter = add ? 12 : 0 }
        applyParagraphSettings(settings)
    }

    func setParagraphMetric(_ keyPath: WritableKeyPath<ParagraphSettings, CGFloat>, _ value: CGFloat) {
        var settings = currentParagraphSettings()
        settings[keyPath: keyPath] = max(value, 0)
        applyParagraphSettings(settings)
    }

    /// Document-wide paragraph spacing, applied to the Normal style (Design tab).
    enum SpacingPreset: String, CaseIterable, Identifiable {
        case noSpace, compact, tight, open, relaxed, double
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .noSpace: "No Paragraph Space"
            case .compact: "Compact"
            case .tight: "Tight"
            case .open: "Open"
            case .relaxed: "Relaxed"
            case .double: "Double"
            }
        }

        /// (space after, line height multiple)
        var values: (after: CGFloat, line: CGFloat) {
            switch self {
            case .noSpace: (0, 1)
            case .compact: (4, 1)
            case .tight: (6, 1.15)
            case .open: (10, 1.15)
            case .relaxed: (12, 1.5)
            case .double: (12, 2)
            }
        }
    }

    func applySpacingPreset(_ preset: SpacingPreset) {
        guard let document else { return }
        var normal = document.styleSheet.definition("normal") ?? StyleDefinition(id: "normal", name: "Normal", basedOn: nil, isBuiltIn: true)
        normal.spaceAfter = preset.values.after
        normal.lineHeight = preset.values.line
        var styles = document.metadata.styles.filter { $0.id != "normal" }
        styles.append(normal)
        updateStyles(theme: document.styleSheet.theme, styles: styles)
    }

    // MARK: Sensitivity

    var sensitivity: SensitivityLabel {
        SensitivityLabel(rawValue: document?.metadata.properties.sensitivity ?? "") ?? .none
    }

    func setSensitivity(_ label: SensitivityLabel) {
        document?.updateMetadata("Sensitivity") { $0.properties.sensitivity = label.rawValue }
        objectWillChange.send()
    }
}

/// Document classification (Home ▸ Sensitivity).
enum SensitivityLabel: String, CaseIterable, Identifiable {
    case none = "", `public` = "public", general, confidential, highlyConfidential
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Label"
        case .public: "Public"
        case .general: "General"
        case .confidential: "Confidential"
        case .highlyConfidential: "Highly Confidential"
        }
    }

    var color: NSColor {
        switch self {
        case .none: .secondaryLabelColor
        case .public: .systemGreen
        case .general: .systemBlue
        case .confidential: .systemOrange
        case .highlyConfidential: .systemRed
        }
    }
}
