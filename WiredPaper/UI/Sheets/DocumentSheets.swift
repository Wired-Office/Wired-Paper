import AppKit
import SwiftUI

// MARK: - Header & footer

struct HeaderFooterSheet: View {
    let onApply: (HeaderFooterSettings) -> Void
    let onCancel: () -> Void
    @State private var settings: HeaderFooterSettings
    @State private var variant = 0

    init(initial: HeaderFooterSettings, onApply: @escaping (HeaderFooterSettings) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _settings = State(initialValue: initial)
    }

    private static let fields: [(String, String)] = [
        ("Page Number", "{PAGE}"), ("Page Count", "{PAGES}"), ("Date", "{DATE}"), ("Time", "{TIME}"),
        ("Title", "{TITLE}"), ("Author", "{AUTHOR}"), ("Subject", "{SUBJECT}"), ("File Name", "{FILENAME}"),
    ]

    var body: some View {
        SheetScaffold(title: "Header & Footer", primaryTitle: "Apply", width: 620, onPrimary: { onApply(settings) }, onCancel: onCancel) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $variant) {
                    Text("All Pages").tag(0)
                    if settings.differentFirstPage { Text("First Page").tag(1) }
                    if settings.differentOddEven { Text("Even Pages").tag(2) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Form {
                    Section("Header") { slots(header: true) }
                    Section("Footer") { slots(header: false) }
                    Section("Options") {
                        Toggle("Different first page", isOn: $settings.differentFirstPage)
                        Toggle("Different odd & even pages", isOn: $settings.differentOddEven)
                        Toggle("Separator lines", isOn: $settings.showSeparators)
                        Picker("Page numbers", selection: $settings.numberFormat) {
                            ForEach(PageNumberFormat.allCases) { Text($0.displayName).tag($0) }
                        }
                        Stepper(value: $settings.startingPageNumber, in: 0...9999) {
                            LabeledContent("Start at", value: "\(settings.startingPageNumber)")
                        }
                        Stepper(value: $settings.fontSize, in: 6...18) {
                            LabeledContent("Font size", value: "\(Int(settings.fontSize)) pt")
                        }
                        Stepper(value: $settings.headerDistance, in: 12...108, step: 2) {
                            LabeledContent("Header from top", value: "\(Int(settings.headerDistance)) pt")
                        }
                        Stepper(value: $settings.footerDistance, in: 12...108, step: 2) {
                            LabeledContent("Footer from bottom", value: "\(Int(settings.footerDistance)) pt")
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(height: 470)
            }
        }
    }

    private func binding(header: Bool) -> Binding<HeaderFooterText> {
        switch (variant, header) {
        case (1, true): $settings.firstHeader
        case (1, false): $settings.firstFooter
        case (2, true): $settings.evenHeader
        case (2, false): $settings.evenFooter
        case (_, true): $settings.header
        default: $settings.footer
        }
    }

    @ViewBuilder
    private func slots(header: Bool) -> some View {
        let content = binding(header: header)
        slot("Left", content.left)
        slot("Center", content.center)
        slot("Right", content.right)
    }

    private func slot(_ title: String, _ text: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: text).labelsHidden()
                Menu {
                    ForEach(Self.fields, id: \.1) { field in
                        Button(field.0) { text.wrappedValue += field.1 }
                    }
                } label: {
                    Image(systemName: "curlybraces")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert a field")
            }
        }
    }
}

// MARK: - Insert field

struct InsertFieldSheet: View {
    let bookmarks: [String]
    let onInsert: (FieldSpec) -> Void
    let onCancel: () -> Void
    @State private var kind: FieldKind = .page
    @State private var argument = "Figure"
    @State private var display: CrossReferenceDisplay = .text
    @State private var fixed = false

    var body: some View {
        SheetScaffold(title: "Insert Field", primaryTitle: "Insert", width: 420, onPrimary: insert, onCancel: onCancel) {
            Form {
                Picker("Field", selection: $kind) {
                    ForEach(FieldKind.allCases) { Text($0.displayName).tag($0) }
                }
                switch kind {
                case .sequence:
                    Picker("Label", selection: $argument) {
                        ForEach(["Figure", "Table", "Equation", "Chart", "Listing"], id: \.self) { Text($0).tag($0) }
                    }
                case .crossReference:
                    Picker("Bookmark", selection: $argument) {
                        ForEach(bookmarks, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(bookmarks.isEmpty)
                    Picker("Insert", selection: $display) {
                        ForEach(CrossReferenceDisplay.allCases) { Text($0.displayName).tag($0) }
                    }
                case .mergeField:
                    TextField("Field name", text: $argument)
                case .formula:
                    TextField("Formula", text: $argument, prompt: Text("=SUM(ABOVE)"))
                case .date, .time:
                    Toggle("Keep the current value (don’t update)", isOn: $fixed)
                default:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .onChange(of: kind) { _, newKind in
                switch newKind {
                case .crossReference: argument = bookmarks.first ?? ""
                case .sequence: argument = "Figure"
                case .formula: argument = "=SUM(ABOVE)"
                case .mergeField: argument = "FirstName"
                default: argument = ""
                }
            }
        }
    }

    private func insert() {
        var spec = FieldSpec(kind: kind, argument: argument)
        spec.display = display
        if fixed {
            spec.fixedValue = kind == .date
                ? DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
                : DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        }
        onInsert(spec)
    }
}

// MARK: - Document properties

struct DocumentPropertiesSheet: View {
    let statistics: DocumentStatistics
    let pages: Int
    let created: Date
    let modified: Date?
    let location: URL?
    let onApply: (DocumentProperties) -> Void
    let onCancel: () -> Void
    @State private var properties: DocumentProperties

    init(properties: DocumentProperties, statistics: DocumentStatistics, pages: Int, created: Date, modified: Date?, location: URL?,
         onApply: @escaping (DocumentProperties) -> Void, onCancel: @escaping () -> Void) {
        self.statistics = statistics
        self.pages = pages
        self.created = created
        self.modified = modified
        self.location = location
        self.onApply = onApply
        self.onCancel = onCancel
        _properties = State(initialValue: properties)
    }

    var body: some View {
        SheetScaffold(title: "Document Properties", primaryTitle: "Save", width: 480, onPrimary: { onApply(properties) }, onCancel: onCancel) {
            Form {
                Section("Summary") {
                    TextField("Title", text: $properties.title)
                    TextField("Subject", text: $properties.subject)
                    TextField("Author", text: $properties.author)
                    TextField("Company", text: $properties.company)
                    TextField("Category", text: $properties.category)
                    TextField("Keywords", text: $properties.keywords, prompt: Text("Comma separated"))
                    TextField("Comments", text: $properties.comments, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Statistics") {
                    LabeledContent("Pages", value: pages.formatted())
                    LabeledContent("Words", value: statistics.words.formatted())
                    LabeledContent("Characters", value: statistics.characters.formatted())
                    LabeledContent("Paragraphs", value: statistics.paragraphs.formatted())
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    if let modified { LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened)) }
                    if let location { LabeledContent("Location", value: location.deletingLastPathComponent().path) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 520)
        }
    }
}
