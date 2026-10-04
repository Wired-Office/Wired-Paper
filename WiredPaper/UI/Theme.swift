import AppKit
import SwiftUI

/// Wired Paper's visual identity: a restrained teal accent over neutral chrome.
enum Theme {
    private static func dynamic(light: NSColor, dark: NSColor, name: String) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let accent = dynamic(
        light: NSColor(srgbRed: 0.075, green: 0.47, blue: 0.54, alpha: 1),
        dark: NSColor(srgbRed: 0.33, green: 0.74, blue: 0.80, alpha: 1),
        name: "WPAccent"
    )

    /// The desk the pages sit on.
    static let canvas = dynamic(
        light: NSColor(srgbRed: 0.905, green: 0.915, blue: 0.925, alpha: 1),
        dark: NSColor(srgbRed: 0.135, green: 0.14, blue: 0.15, alpha: 1),
        name: "WPCanvas"
    )

    static let barBackground = dynamic(
        light: NSColor(srgbRed: 0.975, green: 0.978, blue: 0.982, alpha: 1),
        dark: NSColor(srgbRed: 0.17, green: 0.175, blue: 0.185, alpha: 1),
        name: "WPBarBackground"
    )

    // Document ink colors. Pages are always paper-white, so these are static.
    static let headingInk = NSColor(srgbRed: 0.07, green: 0.29, blue: 0.35, alpha: 1)
    static let secondaryInk = NSColor(srgbRed: 0.36, green: 0.39, blue: 0.42, alpha: 1)
    static let linkInk = NSColor(srgbRed: 0.05, green: 0.40, blue: 0.62, alpha: 1)
    /// Inline writing suggestions (ghost text).
    static let suggestionInk = NSColor(srgbRed: 0.60, green: 0.62, blue: 0.65, alpha: 1)

    static var accentColor: Color { Color(nsColor: accent) }
}
