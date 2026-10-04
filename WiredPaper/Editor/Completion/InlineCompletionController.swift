import AppKit

/// Inline writing suggestions ("ghost text"). After a short pause in typing at
/// the end of a paragraph, asks the provider for a continuation and shows it in
/// gray after the insertion point. Tab accepts it, Escape dismisses it, and
/// typing the suggested characters keeps the rest of it.
final class InlineCompletionController {
    struct Suggestion: Equatable {
        /// Where the suggestion would be inserted.
        var location: Int
        var text: String
    }

    /// Pause in typing before a suggestion is requested.
    var typingDelay: TimeInterval = 0.6

    private weak var editor: EditorController?
    private let providerFactory: () -> TextCompletionProvider?
    private var provider: TextCompletionProvider?
    private var debounce: Timer?
    private var request: Task<Void, Never>?
    /// Increments on every change so stale results are ignored.
    private var generation = 0
    private(set) var suggestion: Suggestion? {
        didSet { if suggestion != oldValue { onChange?(oldValue, suggestion) } }
    }
    /// Called when the suggestion appears, changes or goes away.
    var onChange: ((_ old: Suggestion?, _ new: Suggestion?) -> Void)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                provider = provider ?? providerFactory()
                provider?.prepare()
            } else {
                dismiss()
            }
        }
    }

    init(editor: EditorController?, providerFactory: @escaping () -> TextCompletionProvider? = CompletionProviders.makeDefault) {
        self.editor = editor
        self.providerFactory = providerFactory
    }

    deinit {
        debounce?.invalidate()
        request?.cancel()
    }

    // MARK: Events from the editor

    /// The text changed. Keeps a suggestion the user is typing along with;
    /// otherwise drops it and schedules a new request.
    func textDidChange(in textView: NSTextView) {
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        if let current = suggestion, selection.length == 0, selection.location > current.location,
           selection.location - current.location < (current.text as NSString).length,
           NSMaxRange(selection) <= string.length {
            let typed = string.substring(with: NSRange(location: current.location, length: selection.location - current.location))
            let remaining = current.text as NSString
            if remaining.hasPrefix(typed) {
                generation += 1
                suggestion = Suggestion(location: selection.location, text: remaining.substring(from: typed.utf16.count))
                return
            }
        }
        dismiss()
        schedule(for: textView)
    }

    /// The selection moved without an edit.
    func selectionDidChange(in textView: NSTextView) {
        guard let current = suggestion else { return }
        let selection = textView.selectedRange()
        if selection.length != 0 || selection.location != current.location { dismiss() }
    }

    /// Inserts the suggestion as if typed. Returns false when there is none.
    @discardableResult
    func accept(in textView: NSTextView) -> Bool {
        guard let current = suggestion, textView.selectedRange() == NSRange(location: current.location, length: 0) else { return false }
        suggestion = nil
        generation += 1
        textView.insertText(current.text, replacementRange: textView.selectedRange())
        return true
    }

    /// Inserts the next word of the suggestion. Returns false when there is none.
    @discardableResult
    func acceptWord(in textView: NSTextView) -> Bool {
        guard let current = suggestion, textView.selectedRange() == NSRange(location: current.location, length: 0) else { return false }
        let text = current.text
        let wordStart = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        let wordEnd = text[wordStart...].firstIndex { $0.isWhitespace } ?? text.endIndex
        // textDidChange keeps the rest of the suggestion.
        textView.insertText(String(text[..<wordEnd]), replacementRange: textView.selectedRange())
        return true
    }

    func dismiss() {
        generation += 1
        debounce?.invalidate()
        debounce = nil
        request?.cancel()
        request = nil
        suggestion = nil
    }

    // MARK: Requests

    private func schedule(for textView: NSTextView) {
        guard isEnabled else { return }
        // The model may finish downloading or be turned on while the app runs.
        if provider == nil { provider = providerFactory() }
        guard provider?.isAvailable == true else { return }
        let token = generation
        debounce = Timer.scheduledTimer(withTimeInterval: typingDelay, repeats: false) { [weak self, weak textView] _ in
            guard let self, let textView, token == self.generation else { return }
            self.requestSuggestion(for: textView)
        }
    }

    private func requestSuggestion(for textView: NSTextView) {
        guard let provider, editor?.isViewing != true, !textView.hasMarkedText(),
              textView.window == nil || textView.window?.firstResponder === textView else { return }
        let selection = textView.selectedRange()
        let string = textView.string as NSString
        guard selection.length == 0, CompletionText.shouldSuggest(in: string, at: selection.location),
              editor?.allowsEdit(in: selection) != false else { return }
        let context = CompletionText.context(in: string, at: selection.location)
        let token = generation
        request = Task { @MainActor [weak self] in
            let raw = try? await provider.complete(context)
            guard let self, !Task.isCancelled, token == self.generation, let raw,
                  let text = CompletionText.clean(raw, after: context.before),
                  textView.selectedRange() == selection else { return }
            self.suggestion = Suggestion(location: selection.location, text: text)
        }
    }
}
