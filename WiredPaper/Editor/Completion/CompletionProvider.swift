import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The text around the insertion point that a completion is requested for.
struct CompletionContext: Equatable {
    /// Text before the insertion point (trimmed to a window that fits the model).
    var before: String
    /// Text after the insertion point, for context only.
    var after: String
}

/// Produces a short continuation for the text before the insertion point.
protocol TextCompletionProvider: AnyObject {
    /// Whether the provider can currently produce suggestions.
    var isAvailable: Bool { get }
    /// Loads model resources ahead of the first request.
    func prepare()
    /// The raw continuation; callers clean it up with `CompletionText.clean`.
    func complete(_ context: CompletionContext) async throws -> String
}

enum CompletionProviders {
    /// The best provider on this Mac, or nil when none is available.
    static func makeDefault() -> TextCompletionProvider? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let provider = OnDeviceCompletionProvider()
            return provider.isAvailable ? provider : nil
        }
        #endif
        return nil
    }

    /// Why suggestions are unavailable, for Settings.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to use suggestions."
            case .unavailable(.modelNotReady): return "The on-device model is still downloading."
            case .unavailable: return "The on-device model is unavailable."
            }
        }
        #endif
        return "Writing suggestions require macOS 26 or later."
    }
}

#if canImport(FoundationModels)
/// Completions from Apple's on-device language model: private, offline, free.
@available(macOS 26, *)
final class OnDeviceCompletionProvider: TextCompletionProvider {
    private static let instructions = """
        You are an autocomplete engine inside a word processor. Continue the user's text \
        with the next few words they are most likely to write, matching their language, \
        tone, tense and point of view. Reply with the continuation only: no quotes, no \
        explanations, no repetition of the existing text. If the text ends in the middle \
        of a word, finish that word first. Stop at the end of the current sentence and \
        never write more than about 15 words.
        """

    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)

    var isAvailable: Bool { model.isAvailable }

    func prepare() {
        LanguageModelSession(model: model, instructions: Self.instructions).prewarm()
    }

    func complete(_ context: CompletionContext) async throws -> String {
        // A fresh session per request: completions are independent and a
        // growing transcript would only cost context window.
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        var prompt = "Text before the cursor:\n<<<\(context.before)>>>"
        if !context.after.isEmpty {
            prompt += "\n\nText after the cursor (do not repeat it):\n<<<\(context.after)>>>"
        }
        prompt += "\n\nContinuation:"
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 40)
        return try await session.respond(to: prompt, options: options).content
    }
}
#endif

/// Pure text helpers for completions, kept separate so they can be tested.
enum CompletionText {
    static let maxBefore = 2000
    static let maxAfter = 400
    static let maxLength = 140

    /// The context window around `location` in `string`.
    static func context(in string: NSString, at location: Int) -> CompletionContext {
        let start = max(0, location - maxBefore)
        let end = min(string.length, location + maxAfter)
        return CompletionContext(
            before: string.substring(with: NSRange(location: start, length: location - start)),
            after: string.substring(with: NSRange(location: location, length: end - location))
        )
    }

    /// Whether the insertion point is a good place to suggest: at the end of a
    /// paragraph, after some real text, and not right after a sentence or
    /// paragraph was finished with no space yet.
    static func shouldSuggest(in string: NSString, at location: Int) -> Bool {
        guard location > 0, location <= string.length else { return false }
        if location < string.length {
            let next = string.character(at: location)
            guard next == 0x0A || next == 0x0D || next == 0x2029 else { return false }
        }
        let paragraph = string.paragraphRange(for: NSRange(location: location - 1, length: 0))
        let typed = string.substring(with: NSRange(location: paragraph.location, length: location - paragraph.location))
        // Attachments, list markers and tabs don't count as words.
        let words = typed.split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 1 }
        guard words.count >= 3, let last = typed.unicodeScalars.last else { return false }
        return CharacterSet.letters.contains(last) || last == " " || last == ","
    }

    /// Turns raw model output into text that can be inserted after `before`,
    /// or nil when there is nothing useful to suggest.
    static func clean(_ raw: String, after before: String) -> String? {
        var text = raw.replacingOccurrences(of: "\r", with: "")
        if let newline = text.firstIndex(of: "\n") {
            let firstLine = text[..<newline]
            text = firstLine.trimmingCharacters(in: .whitespaces).isEmpty ? String(text[newline...]) : String(firstLine)
            text = text.trimmingCharacters(in: .newlines)
            if let next = text.firstIndex(of: "\n") { text = String(text[..<next]) }
        }
        for marker in ["<<<", ">>>", "Continuation:"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        // Strip quotes the model sometimes wraps its answer in.
        let quotes: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("„", "“"), ("'", "'")]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for (open, close) in quotes where trimmed.count > 2 && trimmed.first == open && trimmed.last == close {
            text = String(trimmed.dropFirst().dropLast())
            if text.first?.isWhitespace == false, raw.first?.isWhitespace == true { text = " " + text }
        }

        // Drop an echo of the text that is already there.
        let tail = before.suffix(80)
        let core = text.trimmingCharacters(in: .whitespaces)
        if !core.isEmpty {
            for length in stride(from: min(tail.count, core.count), through: 12, by: -1) {
                let overlap = tail.suffix(length)
                if core.hasPrefix(overlap) {
                    text = String(core.dropFirst(length))
                    break
                }
            }
        }

        // Spacing at the join.
        let endsWithSpace = before.last?.isWhitespace ?? true
        if endsWithSpace {
            text = String(text.drop { $0 == " " || $0 == "\t" })
        } else if let first = text.first, first.isWhitespace {
            text = " " + text.drop { $0 == " " || $0 == "\t" }
        }

        // Keep it short: stop after the first sentence, then at a word boundary.
        if let end = text.firstIndex(where: { ".!?…".contains($0) }) {
            text = String(text[...end])
        }
        if text.count > maxLength {
            let prefix = text.prefix(maxLength)
            text = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? String(prefix)
        }
        text = String(text.reversed().drop { $0 == " " }.reversed())
        return text.contains(where: { $0.isLetter || $0.isNumber }) ? text : nil
    }
}
