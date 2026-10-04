import AppKit

/// A spelling or grammar issue found by the Editor pane.
struct ProofingIssue: Identifiable, Equatable {
    enum Kind: String { case spelling, grammar }

    let id = UUID()
    let kind: Kind
    let range: NSRange
    let text: String
    let message: String
    let suggestions: [String]

    static func == (lhs: ProofingIssue, rhs: ProofingIssue) -> Bool { lhs.id == rhs.id }
}

/// Readability figures for the Editor pane.
struct ReadabilityStats: Equatable {
    var words = 0
    var sentences = 0
    var syllables = 0

    var wordsPerSentence: Double { sentences == 0 ? 0 : Double(words) / Double(sentences) }
    var syllablesPerWord: Double { words == 0 ? 0 : Double(syllables) / Double(words) }

    /// Flesch Reading Ease (0–100, higher is easier).
    var readingEase: Double {
        guard words > 0, sentences > 0 else { return 0 }
        return min(max(206.835 - 1.015 * wordsPerSentence - 84.6 * syllablesPerWord, 0), 100)
    }

    /// Flesch–Kincaid grade level.
    var gradeLevel: Double {
        guard words > 0, sentences > 0 else { return 0 }
        return max(0.39 * wordsPerSentence + 11.8 * syllablesPerWord - 15.59, 0)
    }

    static func syllableCount(_ word: String) -> Int {
        let vowels = Set("aeiouyäöüàáâèéêìíîòóôùúû")
        var count = 0
        var previousWasVowel = false
        for character in word.lowercased() {
            let isVowel = vowels.contains(character)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if word.lowercased().hasSuffix("e") && count > 1 { count -= 1 }
        return max(count, 1)
    }

    static func measure(_ text: String) -> ReadabilityStats {
        var stats = ReadabilityStats()
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word else { return }
            stats.words += 1
            stats.syllables += syllableCount(word)
        }
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, sentence.contains(where: \.isLetter) { stats.sentences += 1 }
        }
        return stats
    }
}

/// Document-wide spelling and grammar checking for the Editor pane.
extension EditorController {
    func checkDocument() -> [ProofingIssue] {
        let string = textStorage.string
        guard !string.isEmpty else { return [] }
        let checker = NSSpellChecker.shared
        let tag = textView.spellCheckerDocumentTag
        let results = checker.check(string, range: NSRange(location: 0, length: (string as NSString).length),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue | NSTextCheckingResult.CheckingType.grammar.rawValue,
                                    options: nil, inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)
        let nsString = string as NSString
        var issues: [ProofingIssue] = []
        for result in results {
            switch result.resultType {
            case .spelling:
                let word = nsString.substring(with: result.range)
                // Skip hidden text, field codes and object characters.
                if word.contains("\u{FFFC}") { continue }
                let guesses = checker.guesses(forWordRange: result.range, in: string, language: checker.language(), inSpellDocumentWithTag: tag) ?? []
                issues.append(ProofingIssue(kind: .spelling, range: result.range, text: word,
                                            message: "Possible spelling mistake", suggestions: Array(guesses.prefix(5))))
            case .grammar:
                for detail in result.grammarDetails ?? [] {
                    let detailRange = (detail["NSGrammarRange"] as? NSValue)?.rangeValue ?? NSRange(location: 0, length: result.range.length)
                    let range = NSRange(location: result.range.location + detailRange.location, length: detailRange.length)
                    guard NSMaxRange(range) <= nsString.length else { continue }
                    issues.append(ProofingIssue(kind: .grammar, range: range, text: nsString.substring(with: range),
                                                message: detail["NSGrammarUserDescription"] as? String ?? "Possible grammar issue",
                                                suggestions: Array(((detail["NSGrammarCorrections"] as? [String]) ?? []).prefix(5))))
                }
            default:
                break
            }
        }
        return issues.sorted { $0.range.location < $1.range.location }
    }

    /// Replaces an issue's text if it's still there.
    @discardableResult
    func resolveIssue(_ issue: ProofingIssue, with replacement: String) -> Bool {
        guard NSMaxRange(issue.range) <= textStorage.length,
              (textStorage.string as NSString).substring(with: issue.range) == issue.text else { return false }
        let textView = self.textView(containingCharacterAt: issue.range.location).textView
        guard textView.shouldChangeText(in: issue.range, replacementString: replacement) else { return false }
        textStorage.replaceCharacters(in: issue.range, with: replacement)
        textView.didChangeText()
        textView.undoManager?.setActionName("Correct Spelling")
        return true
    }

    func ignoreIssue(_ issue: ProofingIssue) {
        NSSpellChecker.shared.ignoreWord(issue.text, inSpellDocumentWithTag: textView.spellCheckerDocumentTag)
    }

    func learnWord(_ issue: ProofingIssue) {
        NSSpellChecker.shared.learnWord(issue.text)
    }

    var readability: ReadabilityStats { ReadabilityStats.measure(textStorage.string) }
}
