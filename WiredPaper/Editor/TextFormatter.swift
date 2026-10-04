import AppKit

/// Undoable formatting operations on an NSTextView's selection.
///
/// Every mutation goes through `shouldChangeText(inRanges:replacementStrings:)`
/// / `didChangeText()`, which is how NSTextView registers undo, notifies its
/// delegate and keeps sibling page views in sync.
enum TextFormatter {
    typealias Attributes = [NSAttributedString.Key: Any]

    // MARK: - Character attributes

    /// Applies a character-level change to the selection, or to the typing
    /// attributes when nothing is selected.
    static func changeCharacterAttributes(
        in textView: NSTextView,
        actionName: String,
        typing: (inout Attributes) -> Void,
        apply: (NSTextStorage, NSRange) -> Void
    ) {
        guard let storage = textView.textStorage else { return }
        let ranges = (textView.rangesForUserCharacterAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }

        guard !ranges.isEmpty else {
            var attributes = textView.typingAttributes
            typing(&attributes)
            textView.typingAttributes = attributes
            return
        }

        guard textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) else { return }
        storage.beginEditing()
        for range in ranges { apply(storage, range) }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
    }

    static func changeFonts(in textView: NSTextView, actionName: String, _ transform: (NSFont) -> NSFont) {
        changeCharacterAttributes(in: textView, actionName: actionName, typing: { attributes in
            attributes[.font] = transform(attributes[.font] as? NSFont ?? StyleCatalog.bodyFont)
        }, apply: { storage, range in
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                storage.addAttribute(.font, value: transform(value as? NSFont ?? StyleCatalog.bodyFont), range: run)
            }
        })
    }

    static func setAttribute(_ key: NSAttributedString.Key, to value: Any?, in textView: NSTextView, actionName: String) {
        changeCharacterAttributes(in: textView, actionName: actionName, typing: { attributes in
            attributes[key] = value
        }, apply: { storage, range in
            if let value {
                storage.addAttribute(key, value: value, range: range)
            } else {
                storage.removeAttribute(key, range: range)
            }
        })
    }

    // MARK: - Paragraph attributes

    /// Transforms the paragraph style of every paragraph touched by the selection.
    static func changeParagraphs(in textView: NSTextView, actionName: String, _ transform: (NSMutableParagraphStyle) -> Void) {
        guard let storage = textView.textStorage else { return }
        let ranges = (textView.rangesForUserParagraphAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }

        func transformed(_ style: NSParagraphStyle?) -> NSParagraphStyle {
            let mutable = ((style ?? textView.defaultParagraphStyle ?? .default).mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            transform(mutable)
            return mutable.copy() as? NSParagraphStyle ?? mutable
        }

        if !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) {
            storage.beginEditing()
            for range in ranges {
                storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                    storage.addAttribute(.paragraphStyle, value: transformed(value as? NSParagraphStyle), range: run)
                }
            }
            storage.endEditing()
            textView.didChangeText()
            textView.undoManager?.setActionName(actionName)
        }

        // Keep the insertion point's paragraph formatting in step, which also
        // covers the empty last paragraph of a document.
        var typing = textView.typingAttributes
        typing[.paragraphStyle] = transformed(typing[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = typing
    }

    // MARK: - Named styles

    static func applyStyle(_ kind: ParagraphStyleKind, in textView: NSTextView) {
        applyStyle(id: kind.rawValue, sheet: .standard, in: textView)
    }

    static func applyStyle(id: String, sheet: StyleSheet, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let styleAttributes = sheet.attributes(for: id)
        let resolved = sheet.resolve(id)
        let manager = NSFontManager.shared

        func merged(_ existing: NSParagraphStyle?) -> NSParagraphStyle {
            guard let result = resolved.paragraph.mutableCopy() as? NSMutableParagraphStyle else { return resolved.paragraph }
            if let existing {
                // Structure (tables, lists) and explicit alignment belong to the paragraph.
                result.textBlocks = existing.textBlocks
                if sheet.definition(id)?.alignment == nil && existing.alignment != .natural {
                    result.alignment = existing.alignment
                }
                if !existing.textLists.isEmpty {
                    result.textLists = existing.textLists
                    result.headIndent = existing.headIndent
                    result.firstLineHeadIndent = existing.firstLineHeadIndent
                    result.tabStops = existing.tabStops
                }
            }
            return result
        }

        func styledFont(from existing: NSFont?) -> NSFont {
            // Preserve deliberate italics inside a paragraph when restyling it.
            guard let existing, manager.traits(of: existing).contains(.italicFontMask) else { return resolved.font }
            return manager.convert(resolved.font, toHaveTrait: .italicFontMask)
        }

        func flags(_ existing: Any?) -> String? {
            var tokens = FlagTokens.set(existing)
            if resolved.keepWithNext { tokens.insert(ParagraphFlags.keepWithNext) } else { tokens.remove(ParagraphFlags.keepWithNext) }
            return FlagTokens.string(tokens)
        }

        let ranges = (textView.rangesForUserParagraphAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }
        if !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) {
            storage.beginEditing()
            for range in ranges {
                storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                    storage.addAttribute(.paragraphStyle, value: merged(value as? NSParagraphStyle), range: run)
                }
                storage.enumerateAttribute(.font, in: range) { value, run, _ in
                    storage.addAttribute(.font, value: styledFont(from: value as? NSFont), range: run)
                }
                storage.enumerateAttribute(.wpParaFlags, in: range) { value, run, _ in
                    if let string = flags(value) { storage.addAttribute(.wpParaFlags, value: string, range: run) }
                    else { storage.removeAttribute(.wpParaFlags, range: run) }
                }
                storage.addAttribute(.foregroundColor, value: resolved.color, range: range)
                if resolved.underline {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                storage.addAttribute(.wpParagraphStyle, value: id, range: range)
            }
            storage.endEditing()
            textView.didChangeText()
            textView.undoManager?.setActionName(sheet.displayName(id))
        }

        var typing = textView.typingAttributes
        for (key, value) in styleAttributes where key != .paragraphStyle { typing[key] = value }
        typing[.paragraphStyle] = merged(typing[.paragraphStyle] as? NSParagraphStyle)
        textView.typingAttributes = typing
    }

    /// Re-applies every paragraph's named style (after the theme or a style
    /// definition changes), keeping italics and structure.
    static func restyleDocument(_ storage: NSTextStorage, sheet: StyleSheet, in textView: NSTextView, actionName: String) {
        guard storage.length > 0 else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard textView.shouldChangeText(in: full, replacementString: nil) else { return }
        let manager = NSFontManager.shared
        storage.beginEditing()
        storage.enumerateAttribute(.wpParagraphStyle, in: full) { value, range, _ in
            let id = value as? String ?? ParagraphStyleKind.normal.rawValue
            let resolved = sheet.resolve(id)
            storage.enumerateAttribute(.font, in: range) { fontValue, run, _ in
                let existing = fontValue as? NSFont
                let traits = existing.map { manager.traits(of: $0) } ?? []
                var font = resolved.font
                if traits.contains(.italicFontMask) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
                if traits.contains(.boldFontMask) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
                storage.addAttribute(.font, value: font, range: run)
            }
            storage.enumerateAttribute(.paragraphStyle, in: range) { styleValue, run, _ in
                guard let existing = styleValue as? NSParagraphStyle, let updated = resolved.paragraph.mutableCopy() as? NSMutableParagraphStyle else { return }
                updated.textBlocks = existing.textBlocks
                updated.alignment = existing.alignment == .natural ? updated.alignment : existing.alignment
                if !existing.textLists.isEmpty {
                    updated.textLists = existing.textLists
                    updated.headIndent = existing.headIndent
                    updated.firstLineHeadIndent = existing.firstLineHeadIndent
                    updated.tabStops = existing.tabStops
                }
                storage.addAttribute(.paragraphStyle, value: updated, range: run)
            }
            storage.addAttribute(.foregroundColor, value: resolved.color, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
    }

    /// Resets character formatting in the selection to the Normal style while
    /// keeping links, images, lists and tables.
    static func clearFormatting(in textView: NSTextView) {
        let normal = StyleCatalog.attributes(for: .normal)
        let normalParagraph = StyleCatalog.paragraphStyle(for: .normal)
        let cleared: [NSAttributedString.Key] = [.underlineStyle, .strikethroughStyle, .backgroundColor, .baselineOffset, .superscript, .kern, .shadow, .obliqueness, .expansion]

        func paragraph(from existing: NSParagraphStyle?) -> NSParagraphStyle {
            guard let result = normalParagraph.mutableCopy() as? NSMutableParagraphStyle else { return normalParagraph }
            if let existing {
                result.textBlocks = existing.textBlocks
                if !existing.textLists.isEmpty {
                    result.textLists = existing.textLists
                    result.headIndent = existing.headIndent
                    result.firstLineHeadIndent = existing.firstLineHeadIndent
                    result.tabStops = existing.tabStops
                }
            }
            return result
        }

        changeCharacterAttributes(in: textView, actionName: "Clear Formatting", typing: { attributes in
            for key in cleared { attributes.removeValue(forKey: key) }
            attributes[.font] = normal[.font]
            attributes[.foregroundColor] = normal[.foregroundColor]
            attributes[.wpParagraphStyle] = ParagraphStyleKind.normal.rawValue
            attributes[.paragraphStyle] = paragraph(from: attributes[.paragraphStyle] as? NSParagraphStyle)
        }, apply: { storage, range in
            for key in cleared { storage.removeAttribute(key, range: range) }
            storage.addAttributes([
                .font: normal[.font] as Any,
                .foregroundColor: normal[.foregroundColor] as Any,
                .wpParagraphStyle: ParagraphStyleKind.normal.rawValue,
            ], range: range)
            let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
            storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, run, _ in
                storage.addAttribute(.paragraphStyle, value: paragraph(from: value as? NSParagraphStyle), range: run)
            }
        })
    }

    // MARK: - Insertion

    /// Replaces the selection with attributed content as a single undoable step.
    static func replaceSelection(
        in textView: NSTextView,
        with content: NSAttributedString,
        actionName: String,
        selectAfter: NSRange? = nil
    ) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: content.string) else { return }
        storage.replaceCharacters(in: range, with: content)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        let selection = selectAfter ?? NSRange(location: range.location + content.length, length: 0)
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
    }

    /// Attributes suitable for inserted structural content (no links or attachments).
    static func baseAttributes(for textView: NSTextView) -> Attributes {
        var attributes = textView.typingAttributes
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .attachment)
        return attributes
    }

    static func isAtParagraphStart(_ location: Int, in string: NSString) -> Bool {
        guard location > 0 else { return true }
        let previous = string.character(at: location - 1)
        return previous == 0x0A || previous == 0x0D || previous == 0x2029 || previous == 0x0C
    }
}
