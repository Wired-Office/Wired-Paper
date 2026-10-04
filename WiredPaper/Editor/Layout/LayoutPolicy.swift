import AppKit
import CoreText

/// Decisions made while TextKit generates glyphs: which text is hidden
/// (hidden text, tracked changes in the chosen markup view), which is shown in
/// capitals, and where a paragraph must start on a new page or column.
final class LayoutPolicy {
    var showHiddenText = false
    var markupMode: MarkupMode = .all
    /// Paragraph start indices pushed to the next container by pagination rules
    /// (keep with next, keep lines together, widow/orphan control).
    var dynamicBreaks = Set<Int>()

    func isHidden(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if !showHiddenText, attributes[.wpHidden] != nil { return true }
        if let revision = attributes[.wpRevision] as? String {
            switch markupMode {
            case .none, .simple: return revision.hasPrefix("del:")
            case .original: return revision.hasPrefix("ins:")
            case .all: return false
            }
        }
        return false
    }

    // MARK: Glyph generation

    func generateGlyphs(
        _ layoutManager: NSLayoutManager,
        glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        let first = characterIndexes[0]
        let last = characterIndexes[count - 1]
        guard first >= 0, last < storage.length, last >= first else { return 0 }
        let characterRange = NSRange(location: first, length: last - first + 1)

        // Fast path: nothing special in this run.
        var special = false
        storage.enumerateAttributes(in: characterRange) { attributes, _, stop in
            if attributes[.wpHidden] != nil || attributes[.wpRevision] != nil || attributes[.wpCharFlags] != nil {
                special = true
                stop.pointee = true
            }
        }
        guard special else { return 0 }

        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        let string = storage.string as NSString
        var changed = false

        for index in 0..<count {
            let characterIndex = characterIndexes[index]
            let attributes = storage.attributes(at: characterIndex, effectiveRange: nil)
            if isHidden(attributes) {
                newProperties[index] = .null
                changed = true
                continue
            }
            if FlagTokens.contains(attributes[.wpCharFlags], CharacterFlags.allCaps) {
                let character = string.character(at: characterIndex)
                let upper = String(utf16CodeUnits: [character], count: 1).uppercased().utf16
                if upper.count == 1, let upperCharacter = upper.first, upperCharacter != character {
                    var unichars = [upperCharacter]
                    var glyph = CGGlyph(0)
                    if CTFontGetGlyphsForCharacters(font as CTFont, &unichars, &glyph, 1) {
                        newGlyphs[index] = glyph
                        changed = true
                    }
                }
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }

    // MARK: Control characters

    func controlCharacterAction(
        _ layoutManager: NSLayoutManager,
        proposed action: NSLayoutManager.ControlCharacterAction,
        at characterIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, characterIndex + 1 < storage.length else { return action }
        let character = (storage.string as NSString).character(at: characterIndex)
        guard character == 0x0A || character == 0x2029 else { return action }
        let next = characterIndex + 1
        if dynamicBreaks.contains(next) || startsNewPage(paragraphAt: next, in: storage) {
            return .containerBreak
        }
        return action
    }

    func startsNewPage(paragraphAt index: Int, in storage: NSAttributedString) -> Bool {
        guard index < storage.length else { return false }
        return FlagTokens.contains(storage.attribute(.wpParaFlags, at: index, effectiveRange: nil), ParagraphFlags.pageBreakBefore)
    }

    /// Whether the character at `index` ends a page (not just a column).
    func isPageBreak(at index: Int, in storage: NSAttributedString) -> Bool {
        let string = storage.string as NSString
        guard index < string.length else { return false }
        let character = string.character(at: index)
        if character == 0x0C {
            return (storage.attribute(.wpBreakKind, at: index, effectiveRange: nil) as? String) != "column"
        }
        if character == 0x0A || character == 0x2029 {
            return startsNewPage(paragraphAt: index + 1, in: storage)
        }
        return false
    }
}
