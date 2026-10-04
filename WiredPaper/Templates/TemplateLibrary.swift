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
        let key = "\(template.id)-\(Int(width))"
        if let cached = cache[key] { return cached }
        let setup = AppSettings.shared.defaultPageSetup
        let view = PrintPagesView(text: template.makeContent(setup), pageSetup: setup, maxPages: 1)
        let image = view.firstPageImage(width: width)
        cache[key] = image
        return image
    }
}
