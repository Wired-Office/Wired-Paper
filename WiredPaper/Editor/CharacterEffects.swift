import AppKit
import CoreText

/// Character-level effects beyond basic font traits: small caps, all caps,
/// double underline, text effects, character spacing, hidden text and case changes.
enum CharacterEffects {
    // MARK: Small caps

    /// A version of `font` with small capitals, using the font's own small caps
    /// when it has them.
    static func smallCaps(_ font: NSFont) -> NSFont {
        let settings: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLowerCaseType, .selectorIdentifier: kLowerCaseSmallCapsSelector],
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    static func withoutSmallCaps(_ font: NSFont) -> NSFont {
        var attributes = font.fontDescriptor.fontAttributes
        attributes[.featureSettings] = nil
        return NSFont(descriptor: NSFontDescriptor(fontAttributes: attributes), size: font.pointSize) ?? font
    }

    /// Font features aren't stored in RTF, so re-apply small caps from the flag on load.
    static func restoreSmallCaps(in storage: NSTextStorage) {
        guard storage.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.wpCharFlags, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard FlagTokens.contains(value, CharacterFlags.smallCaps) else { return }
            storage.enumerateAttribute(.font, in: range) { fontValue, fontRange, _ in
                guard let font = fontValue as? NSFont else { return }
                storage.addAttribute(.font, value: smallCaps(font), range: fontRange)
            }
        }
        storage.endEditing()
    }

    // MARK: Flags

    /// Adds or removes a character flag token on the selection.
    static func setFlag(_ token: String, on: Bool, in textView: NSTextView, actionName: String) {
        func updated(_ value: Any?) -> String? {
            var tokens = FlagTokens.set(value)
            if on { tokens.insert(token) } else { tokens.remove(token) }
            return FlagTokens.string(tokens)
        }
        TextFormatter.changeCharacterAttributes(in: textView, actionName: actionName, typing: { attributes in
            attributes[.wpCharFlags] = updated(attributes[.wpCharFlags])
            if token == CharacterFlags.smallCaps, let font = attributes[.font] as? NSFont {
                attributes[.font] = on ? smallCaps(font) : withoutSmallCaps(font)
            }
        }, apply: { storage, range in
            storage.enumerateAttribute(.wpCharFlags, in: range) { value, run, _ in
                if let string = updated(value) {
                    storage.addAttribute(.wpCharFlags, value: string, range: run)
                } else {
                    storage.removeAttribute(.wpCharFlags, range: run)
                }
            }
            if token == CharacterFlags.smallCaps {
                storage.enumerateAttribute(.font, in: range) { value, run, _ in
                    guard let font = value as? NSFont else { return }
                    storage.addAttribute(.font, value: on ? smallCaps(font) : withoutSmallCaps(font), range: run)
                }
            }
        })
    }

    static func hasFlag(_ token: String, attributes: [NSAttributedString.Key: Any]) -> Bool {
        FlagTokens.contains(attributes[.wpCharFlags], token)
    }

    // MARK: Text effects

    enum Effect: String, CaseIterable, Identifiable {
        case none, shadow, outline, glow, emboss
        var id: String { rawValue }
        var displayName: String { rawValue == "none" ? "No Effect" : rawValue.capitalized }
    }

    static func apply(_ effect: Effect, in textView: NSTextView) {
        func attributes(for font: NSFont?, color: NSColor?) -> [NSAttributedString.Key: Any?] {
            let base = color ?? .black
            switch effect {
            case .none:
                return [.shadow: nil, .strokeWidth: nil, .strokeColor: nil]
            case .shadow:
                let shadow = NSShadow()
                shadow.shadowOffset = NSSize(width: 1.5, height: -1.5)
                shadow.shadowBlurRadius = 2
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                return [.shadow: shadow, .strokeWidth: nil, .strokeColor: nil]
            case .outline:
                return [.shadow: nil, .strokeWidth: 3.0, .strokeColor: base]
            case .glow:
                let shadow = NSShadow()
                shadow.shadowOffset = .zero
                shadow.shadowBlurRadius = 5
                shadow.shadowColor = NSColor(srgbRed: 0.2, green: 0.75, blue: 0.85, alpha: 0.9)
                return [.shadow: shadow, .strokeWidth: nil, .strokeColor: nil]
            case .emboss:
                let shadow = NSShadow()
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 0
                shadow.shadowColor = NSColor.white
                return [.shadow: shadow, .strokeWidth: -1.0, .strokeColor: NSColor(white: 0.35, alpha: 1)]
            }
        }
        TextFormatter.changeCharacterAttributes(in: textView, actionName: "Text Effect", typing: { typing in
            for (key, value) in attributes(for: typing[.font] as? NSFont, color: typing[.foregroundColor] as? NSColor) {
                typing[key] = value
            }
        }, apply: { storage, range in
            storage.enumerateAttribute(.foregroundColor, in: range) { color, run, _ in
                for (key, value) in attributes(for: nil, color: color as? NSColor) {
                    if let value { storage.addAttribute(key, value: value, range: run) } else { storage.removeAttribute(key, range: run) }
                }
            }
        })
    }

    // MARK: Character spacing

    static func setSpacing(_ points: CGFloat?, in textView: NSTextView) {
        TextFormatter.setAttribute(.kern, to: points.map { NSNumber(value: Double($0)) }, in: textView, actionName: "Character Spacing")
    }

    // MARK: Change case

    enum CaseChange: String, CaseIterable, Identifiable {
        case sentence, lower, upper, capitalize, toggle
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .sentence: "Sentence case."
            case .lower: "lowercase"
            case .upper: "UPPERCASE"
            case .capitalize: "Capitalize Each Word"
            case .toggle: "tOGGLE cASE"
            }
        }

        func apply(_ text: String) -> String {
            switch self {
            case .lower: return text.lowercased()
            case .upper: return text.uppercased()
            case .capitalize: return text.capitalized
            case .toggle:
                return String(text.map { character in
                    let string = String(character)
                    return string == string.uppercased() ? Character(string.lowercased()) : Character(string.uppercased())
                })
            case .sentence:
                var result = ""
                var capitalizeNext = true
                for character in text.lowercased() {
                    if capitalizeNext, character.isLetter {
                        result += String(character).uppercased()
                        capitalizeNext = false
                    } else {
                        result.append(character)
                    }
                    if ".!?\n".contains(character) { capitalizeNext = true }
                }
                return result
            }
        }
    }

    /// Changes case in place, keeping formatting (character-by-character when lengths match).
    static func changeCase(_ change: CaseChange, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        var range = textView.selectedRange()
        if range.length == 0 {
            range = (storage.string as NSString).rangeOfWord(at: range.location)
        }
        guard range.length > 0 else { return }
        let original = (storage.string as NSString).substring(with: range)
        let converted = change.apply(original)
        guard converted != original else { return }
        guard textView.shouldChangeText(in: range, replacementString: converted) else { return }
        if (converted as NSString).length == range.length {
            storage.replaceCharacters(in: range, with: converted)
        } else {
            let attributes = storage.attributes(at: range.location, effectiveRange: nil)
            storage.replaceCharacters(in: range, with: NSAttributedString(string: converted, attributes: attributes))
        }
        textView.didChangeText()
        textView.undoManager?.setActionName("Change Case")
        textView.setSelectedRange(NSRange(location: range.location, length: (converted as NSString).length))
    }
}

extension NSString {
    /// The word surrounding `location` (empty range if none).
    func rangeOfWord(at location: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let probe = min(max(location, 0), length - 1)
        var result = NSRange(location: location, length: 0)
        enumerateSubstrings(in: NSRange(location: 0, length: length), options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if NSLocationInRange(probe, range) || NSMaxRange(range) == location {
                result = range
                stop.pointee = true
            } else if range.location > probe {
                stop.pointee = true
            }
        }
        return result
    }
}
