import AppKit

/// An accessibility problem found by Review ▸ Check Accessibility.
struct AccessibilityIssue: Identifiable, Equatable {
    enum Severity: String { case error = "Error", warning = "Warning", tip = "Tip" }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
    let range: NSRange?

    static func == (lhs: AccessibilityIssue, rhs: AccessibilityIssue) -> Bool { lhs.id == rhs.id }
}

extension EditorController {
    /// Checks alt text, heading order, empty spacing paragraphs, low-contrast
    /// text, vague link text and a missing document title.
    func checkAccessibility() -> [AccessibilityIssue] {
        var issues: [AccessibilityIssue] = []
        let storage = textStorage
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: storage.length)

        // Pictures and objects without alt text.
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, !HorizontalRule.isRule(attachment) else { return }
            if let object = DocumentObject.decode(storage.attribute(.wpObject, at: range.location, effectiveRange: nil)) {
                // Fields, notes and form controls are text, not pictures.
                if object.isTextual || object.form != nil { return }
            }
            let alt = (storage.attribute(.wpAltText, at: range.location, effectiveRange: nil) as? String) ?? ""
            if alt.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(AccessibilityIssue(severity: .error, title: "Missing alternative text",
                                                 detail: "Describe this picture or object (Format ▸ Picture ▸ Alt Text…).", range: range))
            }
        }

        // Heading levels must not skip (Heading 1 → Heading 3).
        var previousLevel = 0
        for item in computeOutline() where item.level > 0 {
            if item.level > previousLevel + 1 {
                issues.append(AccessibilityIssue(severity: .warning, title: "Skipped heading level",
                                                 detail: "“\(item.title)” is Heading \(item.level) but follows Heading \(max(previousLevel, 0)). Use headings in order.", range: item.range))
            }
            previousLevel = item.level
        }

        // Runs of empty paragraphs used as spacing.
        var emptyRun = 0
        var runStart = 0
        string.enumerateSubstrings(in: full, options: [.byParagraphs]) { text, range, _, _ in
            let isEmpty = (text ?? "").trimmingCharacters(in: .whitespaces).isEmpty && !(text ?? "").contains("\u{FFFC}") && !(text ?? "").contains("\u{0C}")
            if isEmpty {
                if emptyRun == 0 { runStart = range.location }
                emptyRun += 1
            } else {
                if emptyRun >= 3 {
                    issues.append(AccessibilityIssue(severity: .tip, title: "Blank lines used for spacing",
                                                     detail: "\(emptyRun) empty paragraphs in a row. Use paragraph spacing or a page break instead.",
                                                     range: NSRange(location: runStart, length: 0)))
                }
                emptyRun = 0
            }
        }

        // Low-contrast text on white paper.
        var reportedContrast = 0
        storage.enumerateAttribute(.foregroundColor, in: full) { value, range, stop in
            guard let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            let text = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let background = (storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB) ?? .white
            let ratio = Self.contrastRatio(color, background)
            if ratio < 4.5 {
                issues.append(AccessibilityIssue(severity: .warning, title: "Hard-to-read text contrast",
                                                 detail: String(format: "Contrast ratio %.1f:1 is below 4.5:1 for “%@”.", ratio, String(text.prefix(40))), range: range))
                reportedContrast += 1
                if reportedContrast >= 10 { stop.pointee = true }
            }
        }

        // Link text that doesn't say where it goes.
        let vague: Set<String> = ["click here", "here", "link", "more", "read more", "this", "hier", "mehr"]
        storage.enumerateAttribute(.link, in: full) { value, range, _ in
            guard value != nil else { return }
            let text = string.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if vague.contains(text) {
                issues.append(AccessibilityIssue(severity: .tip, title: "Unclear link text",
                                                 detail: "“\(text)” doesn't say where the link goes.", range: range))
            }
        }

        // Tables should start with a header row (bold first row).
        var checkedTables = Set<ObjectIdentifier>()
        storage.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  let block = style.textBlocks.first(where: { $0 is NSTextTableBlock }) as? NSTextTableBlock,
                  !checkedTables.contains(ObjectIdentifier(block.table)) else { return }
            checkedTables.insert(ObjectIdentifier(block.table))
            if block.startingRow == 0, let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
               !font.fontDescriptor.symbolicTraits.contains(.bold) {
                issues.append(AccessibilityIssue(severity: .tip, title: "Table without a header row",
                                                 detail: "Make the first row a header (bold) so screen readers can describe columns.", range: range))
            }
        }

        if (document?.metadata.properties.title ?? "").isEmpty {
            issues.append(AccessibilityIssue(severity: .tip, title: "No document title",
                                             detail: "Add a title in File ▸ Properties… so assistive technology can announce it.", range: nil))
        }
        return issues
    }

    static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            let c = color.usingColorSpace(.sRGB) ?? color
            // Blend translucent colors onto white paper.
            let alpha = Double(c.alphaComponent)
            let r = channel(c.redComponent) * alpha + (1 - alpha)
            let g = channel(c.greenComponent) * alpha + (1 - alpha)
            let bl = channel(c.blueComponent) * alpha + (1 - alpha)
            return 0.2126 * r + 0.7152 * g + 0.0722 * bl
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    // MARK: Look Up, blank page, views, language

    /// Shows the Dictionary / Look Up panel for the selection or the word at the caret.
    func lookUpSelection() {
        let textView = self.textView
        var range = textView.selectedRange()
        if range.length == 0 {
            range = (textStorage.string as NSString).rangeOfWord(at: range.location)
        }
        guard range.length > 0, NSMaxRange(range) <= textStorage.length,
              let container = textView.textContainer else { NSSound.beep(); return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let origin = textView.textContainerOrigin
        let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 12)
        let point = NSPoint(x: rect.minX + origin.x, y: rect.minY + origin.y + font.ascender)
        textView.showDefinition(for: textStorage.attributedSubstring(from: range), at: point)
    }

    func insertBlankPage() {
        insertPageBreak()
        insertPageBreak()
        // Put the caret on the blank page.
        let location = max(textView.selectedRange().location - 1, 0)
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    var pagesPerRow: Int { pagesView?.pagesPerRow ?? 1 }

    func setPagesPerRow(_ count: Int) {
        pagesView?.pagesPerRow = max(count, 1)
        zoomToPageWidth()
        objectWillChange.send()
    }

    var spellingLanguages: [String] { NSSpellChecker.shared.availableLanguages }

    func setSpellingLanguage(_ language: String?) {
        let checker = NSSpellChecker.shared
        if let language {
            checker.automaticallyIdentifiesLanguages = false
            checker.setLanguage(language)
        } else {
            checker.automaticallyIdentifiesLanguages = true
        }
        for view in pagesView.allTextViews where view.isContinuousSpellCheckingEnabled {
            view.isContinuousSpellCheckingEnabled = false
            view.isContinuousSpellCheckingEnabled = true
        }
        objectWillChange.send()
    }
}
