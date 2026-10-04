import AppKit
import XCTest
@testable import WiredPaper

/// `.paper` files must open in both Wired Paper for Mac and the Windows/Linux
/// app (cross-platform/). The fixtures live in cross-platform/tests/fixtures.
final class CrossPlatformCompatibilityTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cross-platform/tests/fixtures")

    func testOpensPaperWrittenByWindowsAndLinuxApp() throws {
        let wrapper = try FileWrapper(url: Self.fixtures.appendingPathComponent("cross-sample.paper"))
        let contents = try PaperFileCodec().read(from: wrapper, defaultAttributes: [:])
        let text = contents.text
        let string = text.string as NSString

        XCTAssertEqual(text.string, "Größe € Title\nbold plain red18\u{2028}link\u{FFFC}\n\t•\tBullet A\n\t•\tBullet B\n\t1.\tNumber 1\nc1\nc2\nQuote 😀\nEnd\n")
        XCTAssertEqual(contents.pageSetup?.paperSize.width ?? 0, 595.28, accuracy: 0.01)
        XCTAssertEqual(contents.metadata?.generator.hasPrefix("Wired Paper"), true)

        // Named styles come back from Document.json.
        XCTAssertEqual(text.attribute(.wpParagraphStyle, at: 0, effectiveRange: nil) as? String, "heading1")
        XCTAssertEqual(text.attribute(.wpParagraphStyle, at: string.range(of: "Quote").location, effectiveRange: nil) as? String, "quote")

        let bold = text.attribute(.font, at: string.range(of: "bold").location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        let red = text.attribute(.font, at: string.range(of: "red18").location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(red?.pointSize, 18)
        XCTAssertNotNil(text.attribute(.link, at: string.range(of: "link").location, effectiveRange: nil))
        XCTAssertNotNil(text.attribute(.attachment, at: string.range(of: "\u{FFFC}").location, effectiveRange: nil))

        let bullet = text.attribute(.paragraphStyle, at: string.range(of: "Bullet A").location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(bullet?.textLists.first.map { ListKind(markerFormat: $0.markerFormat) }, .bullet)
        let cell = text.attribute(.paragraphStyle, at: string.range(of: "c2").location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual((cell?.textBlocks.first as? NSTextTableBlock)?.startingColumn, 1)
    }

    /// Regenerates the fixture the cross-platform tests read:
    /// `TEST_RUNNER_WP_WRITE_FIXTURES=1 xcodebuild test …`
    func testWriteMacFixtureForCrossPlatformApp() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WP_WRITE_FIXTURES"] != nil, "Set WP_WRITE_FIXTURES to regenerate.")
        let body = StyleCatalog.attributes(for: .normal)
        let text = NSMutableAttributedString()
        func add(_ string: String, _ extra: [NSAttributedString.Key: Any] = [:], style: String? = nil) {
            var attributes = body
            attributes.merge(extra) { $1 }
            if let style { attributes[.wpParagraphStyle] = style }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        add("Mac Title\n", [.font: StyleCatalog.font(for: .title)], style: "title")
        add("Section\n", [.font: StyleCatalog.font(for: .heading2)], style: "heading2")
        add("Plain and ")
        add("italic", [.font: NSFontManager.shared.convert(StyleCatalog.bodyFont, toHaveTrait: .italicFontMask)])
        add(".\n")
        add("A quotation.\n", style: "quote")
        let textView = NSTextView()
        textView.textStorage?.setAttributedString(text)
        textView.setSelectedRange(NSRange(location: text.length, length: 0))
        textView.insertText("First\nSecond", replacementRange: textView.selectedRange())
        textView.setSelectedRange(NSRange(location: text.length, length: 12))
        ListFormatter.toggle(.numbered, in: textView)

        let contents = DocumentContents(text: textView.textStorage!, pageSetup: .standard(.letter), metadata: DocumentMetadata())
        let wrapper = try PaperFileCodec().write(contents)
        try wrapper.regularFileContents!.write(to: Self.fixtures.appendingPathComponent("mac-sample.paper"))
    }
}
