import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: SettingsView(settings: .shared))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WiredPaperSettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        if window?.isVisible == false { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            EditingSettings(settings: settings)
                .tabItem { Label("Editing", systemImage: "character.cursor.ibeam") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Show template chooser when Wired Paper opens", isOn: $settings.showTemplateChooserOnLaunch)
            }
            Section("New Documents") {
                Picker("Paper size", selection: $settings.defaultPaper) {
                    ForEach(PaperPreset.allCases) { preset in
                        Text("\(preset.displayName) (\(preset.dimensionsDescription))").tag(preset)
                    }
                }
                Picker("Measurement units", selection: $settings.measurementUnit) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }
            Section("Windows") {
                Toggle("Show ribbon", isOn: $settings.showFormatBar)
                Toggle("Show ruler", isOn: $settings.showRuler)
                Toggle("Show status bar", isOn: $settings.showStatusBar)
                Text("Applies to newly opened windows. Use the View menu to change the current window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for new versions automatically", isOn: $settings.checkForUpdates)
                LabeledContent("Version \(AppVersion.current?.description ?? "")") {
                    Button("Check Now") { UpdateChecker.shared.check(userInitiated: true) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}

private struct EditingSettings: View {
    @ObservedObject var settings: AppSettings

    private static let families = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Form {
            Section("Default Font") {
                Picker("Font", selection: $settings.defaultFontFamily) {
                    ForEach(Self.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $settings.defaultFontSize, in: 6...72, step: 1) {
                    LabeledContent("Size", value: "\(Int(settings.defaultFontSize)) pt")
                }
                Text("The quick brown fox jumps over the lazy dog.")
                    .font(Font(FontResolver.font(family: settings.defaultFontFamily, size: CGFloat(settings.defaultFontSize))))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Section("While Typing") {
                Toggle("Check spelling", isOn: $settings.checkSpellingWhileTyping)
                Toggle("Use smart quotes", isOn: $settings.smartQuotes)
                Toggle("Use smart dashes", isOn: $settings.smartDashes)
                Toggle("Detect links automatically", isOn: $settings.autoLinkDetection)
            }
            Section("Writing Suggestions") {
                Toggle("Suggest how to continue sentences", isOn: $settings.inlineSuggestions)
                Text(CompletionProviders.unavailableReason
                     ?? "Suggestions appear in gray at the end of a paragraph. Press Tab to accept, Option-Right Arrow to accept one word, or Escape to dismiss. Runs on this Mac; your text never leaves it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
