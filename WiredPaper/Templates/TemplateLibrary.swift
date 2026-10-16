import AppKit

enum TemplateLibrary {
    static let all: [DocumentTemplate] = [blank, letter, report, resume, notes]

    static let blank = DocumentTemplate(
        id: "blank",
        name: "Blank",
        summary: "An empty page.",
        symbol: "doc"
    ) { _ in }

    static let letter = DocumentTemplate(
        id: "letter",
        name: "Letter",
        summary: "A formal letter with sender and recipient blocks.",
        symbol: "envelope"
    ) { w in
        w.paragraph("Your Name", .heading2, spacingAfter: 2)
        w.paragraph("123 Street Address · City, State 00000", color: Theme.secondaryInk, spacingAfter: 0)
        w.paragraph("you@example.com · (555) 010-0000", color: Theme.secondaryInk, spacingAfter: 4)
        w.rule()
        w.paragraph(Self.today, spacingAfter: 18)
        w.paragraph("Recipient Name", spacingAfter: 0)
        w.paragraph("Title", spacingAfter: 0)
        w.paragraph("Company", spacingAfter: 0)
        w.paragraph("Street Address", spacingAfter: 0)
        w.paragraph("City, State 00000", spacingAfter: 18)
        w.paragraph("Dear Recipient Name,")
        w.paragraph("Open with a sentence that states why you are writing. Keep it direct: the reader should know your purpose by the end of the first paragraph.")
        w.paragraph("Use the middle paragraphs to give the supporting details — dates, facts or context the reader needs. To replace any text in this template, just select it and start typing.")
        w.paragraph("Close by stating the next step you would like to happen, and thank the reader for their time.")
        w.paragraph("Sincerely,", spacingAfter: 36)
        w.paragraph("Your Name")
    }

    static let report = DocumentTemplate(
        id: "report",
        name: "Report",
        summary: "Title, headings, lists and a results table.",
        symbol: "chart.bar.doc.horizontal"
    ) { w in
        w.paragraph("Project Report", .title)
        w.paragraph("Prepared for the Leadership Team · \(Self.today)", .subtitle)
        w.paragraph("Executive Summary", .heading1)
        w.paragraph("Summarize the purpose of the report, the most important findings and your recommendation in one or two short paragraphs. Many readers will stop here, so make it count.")
        w.paragraph("Background", .heading1)
        w.paragraph("Describe the situation that prompted this work: the problem, the goals and any constraints that shaped the approach.")
        w.paragraph("Key Findings", .heading2)
        w.bullets([
            "State the first finding in a single, clear sentence.",
            "Support each finding with evidence from the results below.",
            "Note any surprises or open questions.",
        ])
        w.paragraph("Results", .heading2)
        w.table([
            ["Measure", "Target", "Actual"],
            ["Customer satisfaction", "90%", "93%"],
            ["Delivery time", "5 days", "4 days"],
            ["Cost per unit", "$12.00", "$11.40"],
        ])
        w.paragraph("Recommendations", .heading1)
        w.numbered([
            "Describe the most important action to take.",
            "Explain the second action and who should own it.",
            "Set a date to review progress.",
        ])
        w.paragraph("Conclusion", .heading1)
        w.paragraph("Restate the main point and what success will look like.")
    }

    static let resume = DocumentTemplate(
        id: "resume",
        name: "Resume",
        summary: "A clean one-page résumé.",
        symbol: "person.text.rectangle"
    ) { w in
        w.paragraph("Your Name", .title)
        w.paragraph("City, State · you@example.com · (555) 010-0000 · linkedin.com/in/you", .subtitle, spacingAfter: 4)
        w.rule()
        w.paragraph("Profile", .heading2)
        w.paragraph("Two or three sentences about who you are professionally, what you are great at and the kind of role you are looking for.")
        w.paragraph("Experience", .heading2)
        w.paragraph("Job Title, Company", .heading3, rightTabText: "2022 – Present")
        w.bullets([
            "Lead with an accomplishment and its measurable result.",
            "Describe the scope of your responsibility.",
            "Highlight a project you are proud of.",
        ])
        w.paragraph("Job Title, Company", .heading3, rightTabText: "2018 – 2022")
        w.bullets([
            "Show progression: promotions, growth or new responsibilities.",
            "Quantify impact wherever you can.",
        ])
        w.paragraph("Education", .heading2)
        w.paragraph("Degree, School", .heading3, rightTabText: "2018")
        w.paragraph("Honors, relevant coursework or activities.")
        w.paragraph("Skills", .heading2)
        w.paragraph("Skill one · Skill two · Skill three · Skill four · Skill five")
    }

    static let notes = DocumentTemplate(
        id: "notes",
        name: "Notes",
        summary: "Meeting notes with agenda and action items.",
        symbol: "note.text"
    ) { w in
        w.paragraph("Meeting Notes", .title)
        w.paragraph(Self.today, .subtitle)
        w.paragraph("Attendees", .heading3)
        w.bullets(["Name", "Name", "Name"])
        w.paragraph("Agenda", .heading3)
        w.numbered(["First topic", "Second topic", "Third topic"])
        w.paragraph("Discussion", .heading3)
        w.paragraph("Capture decisions and the reasoning behind them.")
        w.paragraph("Action Items", .heading3)
        w.bullets(["☐  Task — owner — due date", "☐  Task — owner — due date"])
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
}

/// Caches rendered first-page previews of templates.
enum TemplateThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(for template: DocumentTemplate, width: CGFloat = 150) -> NSImage {
        let key = "\(template.id)-\(template.summary)-\(Int(width))"
        if let cached = cache[key] { return cached }
        let view: PrintPagesView
        if template.isUserTemplate, let contents = try? template.readContents() {
            let setup = contents.pageSetup.flatMap { $0.isValid ? $0 : nil } ?? AppSettings.shared.defaultPageSetup
            var configuration = PrintConfiguration(text: contents.text, pageSetup: setup)
            if let metadata = contents.metadata {
                configuration.geometry = PageGeometry(setup: setup, decoration: metadata.decoration)
                configuration.decoration = metadata.decoration
                configuration.headerFooter = metadata.headerFooter
            }
            view = PrintPagesView(configuration: configuration, maxPages: 1)
        } else {
            let setup = AppSettings.shared.defaultPageSetup
            view = PrintPagesView(text: template.makeContent(setup), pageSetup: setup, maxPages: 1)
        }
        let image = view.firstPageImage(width: width)
        cache[key] = image
        return image
    }

    static func invalidate(_ template: DocumentTemplate) {
        cache = cache.filter { !$0.key.hasPrefix(template.id + "-") }
    }
}

/// Templates the user saved with File ▸ Save as Template…. Each one is a
/// `.paper` file in ~/Library/Application Support/Wired Paper/Templates, named
/// after the template, so it keeps text, images, styles and page setup.
final class UserTemplateStore: ObservableObject {
    static let shared = UserTemplateStore()

    @Published private(set) var templates: [DocumentTemplate] = []

    /// Overridable so tests can use a scratch folder.
    var directory: URL {
        didSet { reload() }
    }

    init(directory: URL = BackupManager.supportDirectory.appendingPathComponent("Templates", isDirectory: true)) {
        self.directory = directory
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        templates = urls
            .filter { $0.pathExtension == DocumentFormat.paper.fileExtension }
            .map(DocumentTemplate.init(userTemplateAt:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Turns user input into a usable file name, or nil if nothing is left.
    static func sanitizedName(_ name: String) -> String? {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? nil : String(cleaned.prefix(120))
    }

    func url(forName name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension(DocumentFormat.paper.fileExtension)
    }

    func template(named name: String) -> DocumentTemplate? {
        templates.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Saves (or replaces) a template from a `.paper` file wrapper.
    @discardableResult
    func save(_ paperFile: FileWrapper, name: String) throws -> DocumentTemplate {
        guard let name = Self.sanitizedName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing = template(named: name), let url = existing.fileURL {
            TemplateThumbnails.invalidate(existing)
            try? FileManager.default.removeItem(at: url)
        }
        let url = url(forName: name)
        try paperFile.write(to: url, options: .atomic, originalContentsURL: nil)
        reload()
        return template(named: name) ?? DocumentTemplate(userTemplateAt: url)
    }

    @discardableResult
    func rename(_ template: DocumentTemplate, to newName: String) throws -> DocumentTemplate {
        guard let source = template.fileURL else { return template }
        guard let name = Self.sanitizedName(newName) else { throw CocoaError(.fileWriteInvalidFileName) }
        if name == template.name { return template }
        if let other = self.template(named: name), other != template {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSLocalizedDescriptionKey: "A template named “\(name)” already exists.",
            ])
        }
        let destination = url(forName: name)
        // A case-only rename on a case-insensitive volume needs a detour.
        let temporary = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: source, to: temporary)
        try FileManager.default.moveItem(at: temporary, to: destination)
        TemplateThumbnails.invalidate(template)
        reload()
        return self.template(named: name) ?? DocumentTemplate(userTemplateAt: destination)
    }

    func delete(_ template: DocumentTemplate) throws {
        guard let url = template.fileURL else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        TemplateThumbnails.invalidate(template)
        reload()
    }
}
