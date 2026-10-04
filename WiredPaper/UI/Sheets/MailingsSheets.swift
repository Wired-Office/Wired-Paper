import SwiftUI
import UniformTypeIdentifiers

/// Mailings ▸ Envelopes.
struct EnvelopeSheet: View {
    @State var delivery: String
    @State var returnAddress: String
    @State private var size = EnvelopeSize.dl
    let onCreate: (String, String, EnvelopeSize) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetScaffold(title: "Envelopes", primaryTitle: "Create Envelope", primaryDisabled: delivery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      width: 460, onPrimary: { onCreate(delivery, returnAddress, size) }, onCancel: onCancel) {
            Form {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivery address").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $delivery).frame(height: 90).border(Color.secondary.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Return address").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $returnAddress).frame(height: 70).border(Color.secondary.opacity(0.3))
                }
                Picker("Envelope size", selection: $size) {
                    ForEach(EnvelopeSize.allCases) { Text($0.displayName).tag($0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
}

/// Mailings ▸ Labels.
struct LabelsSheet: View {
    @State var text: String
    let hasRecipients: Bool
    @State private var layout = LabelLayout.avery5160
    @State private var useRecipients: Bool
    let onCreate: (String, LabelLayout, Bool) -> Void
    let onCancel: () -> Void

    init(text: String, hasRecipients: Bool, onCreate: @escaping (String, LabelLayout, Bool) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.hasRecipients = hasRecipients
        _useRecipients = State(initialValue: hasRecipients)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var body: some View {
        SheetScaffold(title: "Labels", primaryTitle: "Create Labels",
                      primaryDisabled: !useRecipients && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      width: 460, onPrimary: { onCreate(text, layout, useRecipients) }, onCancel: onCancel) {
            Form {
                if hasRecipients {
                    Picker("Content", selection: $useRecipients) {
                        Text("One label per recipient (address block)").tag(true)
                        Text("The same text on every label").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                }
                if !useRecipients {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label text").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $text).frame(height: 90).border(Color.secondary.opacity(0.3))
                    }
                }
                Picker("Label", selection: $layout) {
                    ForEach(LabelLayout.allCases) { Text($0.displayName).tag($0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }
}

/// Mailings ▸ Edit Recipient List / Type a New List.
struct RecipientsSheet: View {
    @State var data: MailMergeData
    let onSave: (MailMergeData) -> Void
    let onCancel: () -> Void
    @State private var newColumn = ""

    var body: some View {
        SheetScaffold(title: "Recipients", primaryTitle: "Save", width: 760, onPrimary: { onSave(data) }, onCancel: onCancel) {
            VStack(alignment: .leading, spacing: 10) {
                if !data.sourceName.isEmpty {
                    Text("Source: \(data.sourceName)").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 3) {
                        GridRow {
                            Text("Use").font(.caption.weight(.semibold))
                            ForEach(data.headers.indices, id: \.self) { column in
                                TextField("Field", text: Binding(get: { data.headers[column] }, set: { data.headers[column] = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.callout.weight(.semibold))
                                    .frame(width: 120)
                            }
                        }
                        ForEach(data.records.indices, id: \.self) { row in
                            GridRow {
                                Toggle("", isOn: Binding(get: { !data.excluded.contains(row) }, set: { use in
                                    if use { data.excluded.remove(row) } else { data.excluded.insert(row) }
                                }))
                                .labelsHidden()
                                ForEach(data.headers.indices, id: \.self) { column in
                                    TextField("", text: cell(row, column))
                                        .textFieldStyle(.squareBorder)
                                        .frame(width: 120)
                                }
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(height: 300)
                .border(Color.secondary.opacity(0.25))
                HStack {
                    Button("Add Recipient") { data.records.append(Array(repeating: "", count: data.headers.count)) }
                        .disabled(data.headers.isEmpty)
                    Button("Remove Last") {
                        if !data.records.isEmpty {
                            data.excluded.remove(data.records.count - 1)
                            data.records.removeLast()
                        }
                    }
                    .disabled(data.records.isEmpty)
                    Spacer()
                    TextField("New field name", text: $newColumn).frame(width: 150)
                    Button("Add Field") {
                        let name = newColumn.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !data.headers.contains(name) else { return }
                        data.headers.append(name)
                        for index in data.records.indices { data.records[index].append("") }
                        newColumn = ""
                    }
                }
                .controlSize(.small)
                Text("\(data.includedIndices.count) of \(data.records.count) recipients will be merged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private func cell(_ row: Int, _ column: Int) -> Binding<String> {
        Binding(get: { column < data.records[row].count ? data.records[row][column] : "" }, set: { value in
            while data.records[row].count <= column { data.records[row].append("") }
            data.records[row][column] = value
        })
    }
}

/// Review ▸ Word Count.
struct WordCountSheet: View {
    let statistics: DocumentStatistics
    let selection: DocumentStatistics?
    let pages: Int
    let onClose: () -> Void

    var body: some View {
        SheetScaffold(title: "Word Count", primaryTitle: "Close", width: 360, onPrimary: onClose, onCancel: onClose) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                if selection != nil {
                    GridRow {
                        Text("")
                        Text("Selection").foregroundStyle(.secondary)
                        Text("Document").foregroundStyle(.secondary)
                    }
                }
                row("Pages", nil, pages)
                row("Words", selection?.words, statistics.words)
                row("Characters (with spaces)", selection?.characters, statistics.characters)
                row("Characters (no spaces)", selection?.charactersExcludingSpaces, statistics.charactersExcludingSpaces)
                row("Paragraphs", selection?.paragraphs, statistics.paragraphs)
            }
            .monospacedDigit()
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func row(_ title: String, _ selected: Int?, _ total: Int) -> some View {
        GridRow {
            Text(title)
            if selection != nil { Text(selected.map { $0.formatted() } ?? "—") }
            Text(total.formatted())
        }
    }
}

/// Review ▸ Check Accessibility.
struct AccessibilitySheet: View {
    let issues: [AccessibilityIssue]
    let onSelect: (AccessibilityIssue) -> Void
    let onClose: () -> Void

    var body: some View {
        SheetScaffold(title: "Accessibility", primaryTitle: "Done", width: 520, onPrimary: onClose, onCancel: onClose) {
            VStack(alignment: .leading, spacing: 8) {
                if issues.isEmpty {
                    Label("No accessibility issues found.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(issues.count) issue\(issues.count == 1 ? "" : "s") found. Click one to go there.")
                        .font(.callout).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(issues) { issue in
                                Button { onSelect(issue) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: icon(issue.severity)).foregroundStyle(color(issue.severity))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(issue.title).font(.body.weight(.medium))
                                            Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer()
                                        Text(issue.severity.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(issue.range == nil)
                            }
                        }
                    }
                    .frame(height: 320)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private func icon(_ severity: AccessibilityIssue.Severity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .tip: "lightbulb.fill"
        }
    }

    private func color(_ severity: AccessibilityIssue.Severity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .tip: .blue
        }
    }
}

/// Insert ▸ Table: pick a size by hovering a grid.
struct TableGridPicker: View {
    let onPick: (Int, Int) -> Void
    let onMore: () -> Void
    @State private var hover = (row: 0, column: 0)
    private let rows = 8, columns = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hover.row > 0 ? "\(hover.column) × \(hover.row) Table" : "Insert Table")
                .font(.callout.weight(.medium))
            VStack(spacing: 3) {
                ForEach(1...rows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(1...columns, id: \.self) { column in
                            let on = row <= hover.row && column <= hover.column
                            RoundedRectangle(cornerRadius: 2)
                                .fill(on ? Theme.accentColor.opacity(0.35) : Color.primary.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(on ? Theme.accentColor : Color.primary.opacity(0.3), lineWidth: 1))
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                                .onHover { inside in if inside { hover = (row, column) } }
                                .onTapGesture { onPick(row, column) }
                        }
                    }
                }
            }
            Divider()
            Button("Insert Table…", action: onMore).buttonStyle(.plain)
        }
        .padding(12)
    }
}
