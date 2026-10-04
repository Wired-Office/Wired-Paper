import AppKit
import Combine

enum MeasurementUnit: String, CaseIterable, Identifiable {
    case inches, centimeters, points

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inches: "Inches"
        case .centimeters: "Centimeters"
        case .points: "Points"
        }
    }

    var abbreviation: String {
        switch self {
        case .inches: "in"
        case .centimeters: "cm"
        case .points: "pt"
        }
    }

    var pointsPerUnit: CGFloat {
        switch self {
        case .inches: 72
        case .centimeters: 72 / 2.54
        case .points: 1
        }
    }

    var rulerUnitName: NSRulerView.UnitName {
        switch self {
        case .inches: .inches
        case .centimeters: .centimeters
        case .points: .points
        }
    }

    func fromPoints(_ points: CGFloat) -> Double { Double(points / pointsPerUnit) }
    func toPoints(_ value: Double) -> CGFloat { CGFloat(value) * pointsPerUnit }
}

/// User preferences, persisted in UserDefaults. Observable from SwiftUI and
/// broadcast to open editors via `AppSettings.didChange`.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let didChange = Notification.Name("WPAppSettingsDidChange")

    private enum Key: String {
        case showTemplateChooserOnLaunch, defaultFontFamily, defaultFontSize, measurementUnit, defaultPaper
        case checkSpellingWhileTyping, smartQuotes, smartDashes, autoLinkDetection
        case showRuler, showFormatBar, showStatusBar
        case authorName, automaticBackups, fixDateFieldsOnInsert, autoSave
        case inlineSuggestions
    }

    private let defaults: UserDefaults

    @Published var showTemplateChooserOnLaunch: Bool { didSet { store(showTemplateChooserOnLaunch, .showTemplateChooserOnLaunch) } }
    @Published var defaultFontFamily: String { didSet { store(defaultFontFamily, .defaultFontFamily) } }
    @Published var defaultFontSize: Double { didSet { store(defaultFontSize, .defaultFontSize) } }
    @Published var measurementUnit: MeasurementUnit { didSet { store(measurementUnit.rawValue, .measurementUnit) } }
    @Published var defaultPaper: PaperPreset { didSet { store(defaultPaper.rawValue, .defaultPaper) } }
    @Published var checkSpellingWhileTyping: Bool { didSet { store(checkSpellingWhileTyping, .checkSpellingWhileTyping) } }
    @Published var smartQuotes: Bool { didSet { store(smartQuotes, .smartQuotes) } }
    @Published var smartDashes: Bool { didSet { store(smartDashes, .smartDashes) } }
    @Published var autoLinkDetection: Bool { didSet { store(autoLinkDetection, .autoLinkDetection) } }
    @Published var showRuler: Bool { didSet { store(showRuler, .showRuler) } }
    @Published var showFormatBar: Bool { didSet { store(showFormatBar, .showFormatBar) } }
    @Published var showStatusBar: Bool { didSet { store(showStatusBar, .showStatusBar) } }
    /// Name recorded on comments, tracked changes and new documents.
    @Published var authorName: String { didSet { store(authorName, .authorName) } }
    @Published var automaticBackups: Bool { didSet { store(automaticBackups, .automaticBackups) } }
    @Published var fixDateFieldsOnInsert: Bool { didSet { store(fixDateFieldsOnInsert, .fixDateFieldsOnInsert) } }
    /// Save changes to the file continuously (title bar ▸ AutoSave).
    @Published var autoSave: Bool { didSet { store(autoSave, .autoSave) } }
    /// Suggest how to continue a sentence (on-device model; Tab accepts).
    @Published var inlineSuggestions: Bool { didSet { store(inlineSuggestions, .inlineSuggestions) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let usesMetric = Locale.current.measurementSystem != .us
        defaults.register(defaults: [
            Key.showTemplateChooserOnLaunch.rawValue: true,
            Key.defaultFontFamily.rawValue: "Helvetica Neue",
            Key.defaultFontSize.rawValue: 12.0,
            Key.measurementUnit.rawValue: (usesMetric ? MeasurementUnit.centimeters : .inches).rawValue,
            Key.defaultPaper.rawValue: (usesMetric ? PaperPreset.a4 : .letter).rawValue,
            Key.checkSpellingWhileTyping.rawValue: true,
            Key.smartQuotes.rawValue: true,
            Key.smartDashes.rawValue: true,
            Key.autoLinkDetection.rawValue: false,
            Key.showRuler.rawValue: true,
            Key.showFormatBar.rawValue: true,
            Key.showStatusBar.rawValue: true,
            Key.authorName.rawValue: NSFullUserName(),
            Key.automaticBackups.rawValue: true,
            Key.fixDateFieldsOnInsert.rawValue: false,
            Key.autoSave.rawValue: true,
            Key.inlineSuggestions.rawValue: true,
        ])

        showTemplateChooserOnLaunch = defaults.bool(forKey: Key.showTemplateChooserOnLaunch.rawValue)
        defaultFontFamily = defaults.string(forKey: Key.defaultFontFamily.rawValue) ?? "Helvetica Neue"
        defaultFontSize = defaults.double(forKey: Key.defaultFontSize.rawValue)
        measurementUnit = MeasurementUnit(rawValue: defaults.string(forKey: Key.measurementUnit.rawValue) ?? "") ?? .inches
        defaultPaper = PaperPreset(rawValue: defaults.string(forKey: Key.defaultPaper.rawValue) ?? "") ?? .letter
        checkSpellingWhileTyping = defaults.bool(forKey: Key.checkSpellingWhileTyping.rawValue)
        smartQuotes = defaults.bool(forKey: Key.smartQuotes.rawValue)
        smartDashes = defaults.bool(forKey: Key.smartDashes.rawValue)
        autoLinkDetection = defaults.bool(forKey: Key.autoLinkDetection.rawValue)
        showRuler = defaults.bool(forKey: Key.showRuler.rawValue)
        showFormatBar = defaults.bool(forKey: Key.showFormatBar.rawValue)
        showStatusBar = defaults.bool(forKey: Key.showStatusBar.rawValue)
        authorName = defaults.string(forKey: Key.authorName.rawValue) ?? NSFullUserName()
        automaticBackups = defaults.bool(forKey: Key.automaticBackups.rawValue)
        fixDateFieldsOnInsert = defaults.bool(forKey: Key.fixDateFieldsOnInsert.rawValue)
        autoSave = defaults.bool(forKey: Key.autoSave.rawValue)
        inlineSuggestions = defaults.bool(forKey: Key.inlineSuggestions.rawValue)
    }

    var defaultPageSetup: PageSetup { .standard(defaultPaper) }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
