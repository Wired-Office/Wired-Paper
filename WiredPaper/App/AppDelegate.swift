import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recentDocumentsMenu = RecentDocumentsMenuController()

    /// True when the app is hosting unit tests: stay in the background and open no windows.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests {
            NSApp.setActivationPolicy(.prohibited)
            UserDefaults.standard.setVolatileDomain(["ApplePersistenceIgnoreState": true], forName: UserDefaults.argumentDomain)
        }
        NSApp.mainMenu = MainMenuBuilder.build(recentDocumentsDelegate: recentDocumentsMenu)
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.isRunningTests { UpdateChecker.shared.start() }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if Self.isRunningTests { return false }
        guard AppSettings.shared.showTemplateChooserOnLaunch else { return true }
        TemplateChooserWindowController.shared.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Actions

    @objc func showTemplateChooser(_ sender: Any?) {
        TemplateChooserWindowController.shared.show()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateChecker.shared.check(userInitiated: true)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "A calm, capable word processor for macOS.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Wired Paper",
            .credits: credits,
        ])
    }
}
