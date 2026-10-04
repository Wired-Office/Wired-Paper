import XCTest
@testable import WiredPaper

final class UpdateCheckerTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, assets: String = "") throws -> ReleaseInfo {
        let json = """
            {"tag_name": "\(tag)", "name": "Wired Paper", "body": "## What's new\\n- **Tab** accepts\\n\\n🤖 Generated with [Claude Code](https://claude.com/claude-code)",
             "html_url": "https://github.com/Wired-Office/Wired-Paper/releases/tag/\(tag)",
             "draft": \(draft), "prerelease": \(prerelease), "assets": [\(assets)]}
            """
        return try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
    }

    func testVersionParsingAndOrdering() {
        XCTAssertEqual(AppVersion("v1.2")?.components, [1, 2])
        XCTAssertEqual(AppVersion("1.10.0-beta")?.components, [1, 10, 0])
        XCTAssertNil(AppVersion("latest"))
        XCTAssertEqual(AppVersion("1.1"), AppVersion("1.1.0"))
        XCTAssertLessThan(AppVersion("1.9")!, AppVersion("1.10")!)
        XCTAssertLessThan(AppVersion("1.1")!, AppVersion("v1.1.1")!)
        XCTAssertFalse(AppVersion("2.0")! < AppVersion("1.9.9")!)
    }

    func testOffersOnlyNewerPublishedReleases() throws {
        let current = AppVersion("1.1")
        XCTAssertNotNil(UpdateChecker.update(from: try release("v1.2"), current: current, skipped: nil, userInitiated: false))
        XCTAssertNil(UpdateChecker.update(from: try release("v1.1"), current: current, skipped: nil, userInitiated: true))
        XCTAssertNil(UpdateChecker.update(from: try release("v1.0"), current: current, skipped: nil, userInitiated: true))
        XCTAssertNil(UpdateChecker.update(from: try release("v1.2", draft: true), current: current, skipped: nil, userInitiated: true))
        XCTAssertNil(UpdateChecker.update(from: try release("v1.2", prerelease: true), current: current, skipped: nil, userInitiated: true))
    }

    func testSkippedVersionIsOnlyShownWhenAsked() throws {
        let current = AppVersion("1.1")
        XCTAssertNil(UpdateChecker.update(from: try release("v1.2"), current: current, skipped: "1.2", userInitiated: false))
        XCTAssertNotNil(UpdateChecker.update(from: try release("v1.2"), current: current, skipped: "1.2", userInitiated: true))
        XCTAssertNotNil(UpdateChecker.update(from: try release("v1.3"), current: current, skipped: "1.2", userInitiated: false))
    }

    func testDownloadPrefersDiskImage() throws {
        let page = try release("v1.2")
        XCTAssertEqual(page.downloadURL, page.htmlURL)
        let dmg = try release("v1.2", assets: """
            {"name": "Source.zip", "browser_download_url": "https://example.com/Source.zip"},
            {"name": "Wired-Paper-1.2.dmg", "browser_download_url": "https://example.com/Wired-Paper-1.2.dmg"}
            """)
        XCTAssertEqual(dmg.downloadURL.lastPathComponent, "Wired-Paper-1.2.dmg")
    }

    func testNotesDropMarkupAndFooter() throws {
        let notes = try release("v1.2").notes.string
        XCTAssertEqual(notes, "What's new\n• Tab accepts")
    }
}
