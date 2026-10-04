import AppKit
import XCTest
@testable import WiredPaper

/// Answers every request with a fixed string.
private final class StubCompletionProvider: TextCompletionProvider {
    var response: String
    private(set) var requests: [CompletionContext] = []

    init(_ response: String) { self.response = response }

    var isAvailable: Bool { true }
    func prepare() {}
    func complete(_ context: CompletionContext) async throws -> String {
        requests.append(context)
        return response
    }
}

final class CompletionTests: XCTestCase {
    // MARK: Cleaning model output

    func testCleanDropsLeadingSpaceAfterSpace() {
        XCTAssertEqual(CompletionText.clean(" brown fox jumps.", after: "The quick "), "brown fox jumps.")
    }

    func testCleanAddsSpaceBetweenWords() {
        XCTAssertEqual(CompletionText.clean(" brown fox", after: "The quick"), " brown fox")
    }

    func testCleanFinishesWordWithoutSpace() {
        XCTAssertEqual(CompletionText.clean("ick brown fox", after: "The qu"), "ick brown fox")
    }

    func testCleanStopsAfterFirstSentenceAndLine() {
        XCTAssertEqual(CompletionText.clean("over the dog. Then it ran.\nMore", after: "It jumped "), "over the dog.")
    }

    func testCleanStripsQuotesAndEcho() {
        XCTAssertEqual(CompletionText.clean("\"the meeting starts at noon\"", after: "Remember that "), "the meeting starts at noon")
        XCTAssertEqual(CompletionText.clean("Remember that the meeting starts", after: "Please note: Remember that "), "the meeting starts")
    }

    func testCleanRejectsEmptyOutput() {
        XCTAssertNil(CompletionText.clean("  \n ", after: "Hello "))
        XCTAssertNil(CompletionText.clean("...", after: "Hello "))
    }

    func testCleanLimitsLengthAtWordBoundary() {
        let long = String(repeating: "word ", count: 60)
        let cleaned = CompletionText.clean(long, after: "Some ")!
        XCTAssertLessThanOrEqual(cleaned.count, CompletionText.maxLength)
        XCTAssertTrue(cleaned.hasSuffix("word"))
    }

    // MARK: When to suggest

    func testSuggestsOnlyAtParagraphEndAfterSomeWords() {
        let text = "We went to the market\nNext" as NSString
        XCTAssertTrue(CompletionText.shouldSuggest(in: text, at: 21))
        XCTAssertFalse(CompletionText.shouldSuggest(in: text, at: 10), "middle of a paragraph")
        XCTAssertFalse(CompletionText.shouldSuggest(in: text, at: text.length), "too few words")
        XCTAssertFalse(CompletionText.shouldSuggest(in: "The end." as NSString, at: 8), "finished sentence")
    }

    func testContextWindowIsBounded() {
        let text = String(repeating: "a", count: 5000) as NSString
        let context = CompletionText.context(in: text, at: 3000)
        XCTAssertEqual(context.before.count, CompletionText.maxBefore)
        XCTAssertEqual(context.after.count, CompletionText.maxAfter)
    }

    // MARK: Controller

    private func makeTextView(_ string: String) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 600))
        textView.string = string
        textView.setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        return textView
    }

    private func makeController(_ provider: StubCompletionProvider) -> InlineCompletionController {
        let controller = InlineCompletionController(editor: nil) { provider }
        controller.typingDelay = 0.01
        controller.isEnabled = true
        return controller
    }

    private func waitForSuggestion(_ controller: InlineCompletionController) {
        let appeared = expectation(description: "suggestion")
        controller.onChange = { _, new in if new != nil { appeared.fulfill() } }
        wait(for: [appeared], timeout: 2)
        controller.onChange = nil
    }

    func testSuggestsAcceptsAndTypesAlong() {
        let provider = StubCompletionProvider(" brown fox jumps over the dog.")
        let controller = makeController(provider)
        let textView = makeTextView("The very quick ")

        controller.textDidChange(in: textView)
        waitForSuggestion(controller)
        XCTAssertEqual(controller.suggestion, .init(location: 15, text: "brown fox jumps over the dog."))
        XCTAssertEqual(provider.requests.first?.before, "The very quick ")

        // Typing the suggested characters keeps the rest.
        textView.insertText("bro", replacementRange: textView.selectedRange())
        controller.textDidChange(in: textView)
        XCTAssertEqual(controller.suggestion, .init(location: 18, text: "wn fox jumps over the dog."))

        // Option-Right takes one word; Tab takes the rest.
        XCTAssertTrue(controller.acceptWord(in: textView))
        controller.textDidChange(in: textView)
        XCTAssertEqual(textView.string, "The very quick brown")
        XCTAssertTrue(controller.accept(in: textView))
        XCTAssertEqual(textView.string, "The very quick brown fox jumps over the dog.")
        XCTAssertNil(controller.suggestion)
    }

    func testTypingSomethingElseOrMovingDismisses() {
        let controller = makeController(StubCompletionProvider("brown fox"))
        let textView = makeTextView("The very quick ")
        controller.textDidChange(in: textView)
        waitForSuggestion(controller)

        textView.insertText("x", replacementRange: textView.selectedRange())
        controller.textDidChange(in: textView)
        XCTAssertNil(controller.suggestion)
        XCTAssertFalse(controller.accept(in: textView), "Tab falls through when nothing is suggested")

        textView.string = "The very quick "
        textView.setSelectedRange(NSRange(location: 15, length: 0))
        controller.textDidChange(in: textView)
        waitForSuggestion(controller)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        controller.selectionDidChange(in: textView)
        XCTAssertNil(controller.suggestion)
    }

    func testDisabledControllerNeverAsks() {
        let provider = StubCompletionProvider("brown fox")
        let controller = makeController(provider)
        controller.isEnabled = false
        let textView = makeTextView("The very quick ")
        controller.textDidChange(in: textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertNil(controller.suggestion)
    }
}
