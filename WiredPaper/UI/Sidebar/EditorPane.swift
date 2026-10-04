import SwiftUI

/// Home ▸ Editor: spelling and grammar suggestions plus readability.
struct EditorPane: View {
    @ObservedObject var editor: EditorController
    @State private var issues: [ProofingIssue] = []
    @State private var stats = ReadabilityStats()
    @State private var checked = false

    private var spelling: [ProofingIssue] { issues.filter { $0.kind == .spelling } }
    private var grammar: [ProofingIssue] { issues.filter { $0.kind == .grammar } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editor Score").font(.caption).foregroundStyle(.secondary)
                        Text(checked ? "\(score)%" : "—").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                    }
                    Spacer()
                    Button("Check Again", action: recheck)
                }

                HStack(spacing: 10) {
                    summary("Spelling", count: spelling.count, symbol: "textformat.abc.dottedunderline", color: .red)
                    summary("Grammar", count: grammar.count, symbol: "text.badge.checkmark", color: .blue)
                }

                if checked && issues.isEmpty {
                    Label("No spelling or grammar suggestions.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                ForEach(issues) { issue in
                    IssueCard(issue: issue, onSelect: { editor.reveal(issue.range) }, onReplace: { replacement in
                        if editor.resolveIssue(issue, with: replacement) { recheck() }
                    }, onIgnore: {
                        editor.ignoreIssue(issue)
                        recheck()
                    }, onLearn: issue.kind == .spelling ? {
                        editor.learnWord(issue)
                        recheck()
                    } : nil)
                }

                Divider()
                Text("Readability").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    row("Words", "\(stats.words)")
                    row("Sentences", "\(stats.sentences)")
                    row("Words per sentence", String(format: "%.1f", stats.wordsPerSentence))
                    row("Reading ease", String(format: "%.0f / 100", stats.readingEase))
                    row("Grade level", String(format: "%.1f", stats.gradeLevel))
                }
                .font(.callout)
            }
            .padding(14)
        }
        .onAppear(perform: recheck)
    }

    /// 100% with no issues; each issue per 100 words costs points.
    private var score: Int {
        guard stats.words > 0 else { return 100 }
        let perHundred = Double(issues.count) / Double(stats.words) * 100
        return max(0, min(100, Int((100 - perHundred * 8).rounded())))
    }

    private func recheck() {
        issues = editor.checkDocument()
        stats = editor.readability
        checked = true
    }

    private func summary(_ title: String, count: Int, symbol: String, color: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text("\(count)").font(.headline).monospacedDigit()
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}

private struct IssueCard: View {
    let issue: ProofingIssue
    let onSelect: () -> Void
    let onReplace: (String) -> Void
    let onIgnore: () -> Void
    let onLearn: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(issue.kind == .spelling ? Color.red : Color.blue).frame(width: 7, height: 7)
                Text(issue.kind == .spelling ? "Spelling" : "Grammar").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button(action: onSelect) {
                Text(issue.text).strikethrough(issue.kind == .spelling, color: .red).font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            Text(issue.message).font(.caption).foregroundStyle(.secondary)
            if !issue.suggestions.isEmpty {
                FlowButtons(items: issue.suggestions, action: onReplace)
            }
            HStack {
                Button("Ignore", action: onIgnore)
                if let onLearn { Button("Add to Dictionary", action: onLearn) }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

private struct FlowButtons: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button(item) { action(item) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentColor)
                    .controlSize(.small)
            }
        }
    }
}

/// Home ▸ Styles Pane: every style with a live preview, plus management.
struct StylesPane: View {
    @ObservedObject var editor: EditorController
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter styles", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(styles) { style in
                        Button {
                            editor.applyStyle(id: style.id)
                            editor.focusTextView()
                        } label: {
                            HStack {
                                Text(style.name)
                                    .font(Font(editor.styleSheet.resolve(style.id).font.withSize(min(editor.styleSheet.resolve(style.id).font.pointSize, 18))))
                                    .foregroundStyle(Color(nsColor: editor.styleSheet.resolve(style.id).color))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: style.isBuiltIn ? "paragraphsign" : "person.crop.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(editor.formatting.styleID == style.id ? Theme.accentColor.opacity(0.16) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            Divider()
            HStack {
                Button("Manage Styles…") {
                    NSApp.sendAction(#selector(DocumentViewController.showStylesManager(_:)), to: nil, from: nil)
                }
                Spacer()
                Button("Clear Formatting", action: editor.clearFormatting)
            }
            .controlSize(.small)
            .padding(10)
        }
    }

    private var styles: [StyleDefinition] {
        let all = editor.styleSheet.allStyles
        guard !filter.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }
}
