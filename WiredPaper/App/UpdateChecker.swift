import AppKit

/// A dotted version number such as "1.2" or "v1.2.3". Missing components count as zero.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" { trimmed.removeFirst() }
        // Ignore suffixes like "-beta" or "+build".
        let core = trimmed.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        components = parts.compactMap { $0 }
    }

    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A published release, as returned by the GitHub Releases API.
struct ReleaseInfo: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case htmlURL = "html_url"
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// The disk image to download, or the release page when there is none.
    var downloadURL: URL {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL
    }

    /// Release notes as plain-ish text: Markdown markup removed, generator footer dropped.
    var notes: NSAttributedString {
        let lines = (body ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.contains("Generated with [Claude Code]") }
            .map { line -> String in
                // Headings and quotes read fine without their markers.
                var line = line
                while line.hasPrefix("#") || line.hasPrefix(">") { line.removeFirst() }
                line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
                return line
            }
        let markdown = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        let result = NSMutableAttributedString(parsed)
        let full = NSRange(location: 0, length: result.length)
        result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        result.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            let intent = (value as? NSNumber).map { InlinePresentationIntent(rawValue: $0.uintValue) } ?? []
            let size = NSFont.smallSystemFontSize
            let font: NSFont
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: size - 1, weight: .regular)
            } else {
                font = intent.contains(.stronglyEmphasized) ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            }
            result.addAttribute(.font, value: font, range: range)
        }
        return result
    }
}

/// Checks GitHub for a newer release and offers to download it. Runs at
/// launch and then about once a day (when enabled in Settings), or on demand
/// from Wired Paper ▸ Check for Updates….
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let releasesURL = URL(string: "https://api.github.com/repos/Wired-Office/Wired-Paper/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private enum Key {
        static let lastCheck = "UpdateCheckerLastCheck"
        static let skippedVersion = "UpdateCheckerSkippedVersion"
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var timer: Timer?
    private var isChecking = false

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    // MARK: Scheduling

    /// Starts automatic checks: shortly after launch, then periodically.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard AppSettings.shared.checkForUpdates else { return }
        let last = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        check(userInitiated: false)
    }

    // MARK: Checking

    /// The release to offer, or nil when the app is current, the release is
    /// unusable, or the user skipped that version (unless they asked to check).
    static func update(from release: ReleaseInfo, current: AppVersion?, skipped: String?, userInitiated: Bool) -> ReleaseInfo? {
        guard !release.draft, !release.prerelease, let version = release.version, let current, current < version else { return nil }
        if !userInitiated, let skipped, let skippedVersion = AppVersion(skipped), skippedVersion == version { return nil }
        return release
    }

    func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true
        var request = URLRequest(url: Self.releasesURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wired-Paper/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = data.flatMap { try? JSONDecoder().decode(ReleaseInfo.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                guard let release, status == 200 else {
                    if userInitiated { self.showFailure(error) }
                    return
                }
                self.defaults.set(Date(), forKey: Key.lastCheck)
                let skipped = self.defaults.string(forKey: Key.skippedVersion)
                if let update = Self.update(from: release, current: .current, skipped: skipped, userInitiated: userInitiated) {
                    self.offer(update)
                } else if userInitiated {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    // MARK: Alerts

    private func offer(_ release: ReleaseInfo) {
        let version = release.version?.description ?? release.tagName
        let alert = NSAlert()
        alert.messageText = "Wired Paper \(version) is available"
        alert.informativeText = "You have version \(AppVersion.current?.description ?? "?"). Download the new version, then replace Wired Paper in your Applications folder."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        let notes = release.notes
        if notes.length > 0 {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
            scrollView.hasVerticalScroller = true
            scrollView.borderType = .bezelBorder
            let textView = NSTextView(frame: scrollView.bounds)
            textView.isEditable = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.autoresizingMask = [.width]
            textView.textStorage?.setAttributedString(notes)
            scrollView.documentView = textView
            alert.accessoryView = scrollView
        }

        NSApp.activate(ignoringOtherApps: false)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn:
            defaults.set(version, forKey: Key.skippedVersion)
        default:
            break
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Wired Paper \(AppVersion.current?.description ?? "") is the newest version available."
        alert.runModal()
    }

    private func showFailure(_ error: Error?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error?.localizedDescription ?? "GitHub didn't return release information. Try again later."
        alert.runModal()
    }
}
