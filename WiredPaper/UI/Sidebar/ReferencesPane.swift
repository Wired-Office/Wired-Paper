import AppKit
import SwiftUI

/// Citation manager: sources, citation style, citing and the bibliography.
struct ReferencesPane: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @State private var selection = Set<String>()
    @State private var editing: CitationSource?
    @State private var filter = ""

    var body: some View {
        let sources = (editor.document?.metadata.sources ?? []).filter {
            filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.authors.joined(separator: " ").localizedCaseInsensitiveContains(filter)
        }
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: Binding(get: { editor.citationStyle }, set: { editor.setCitationStyle($0) })) {
                ForEach(CitationStyle.allCases) { Text($0.displayName).tag($0) }
            }
            HStack {
                Button { editing = CitationSource() } label: { Label("Add Source", systemImage: "plus") }
                Spacer()
                Button("Cite") { editor.insertCitation(sourceIDs: sources.filter { selection.contains($0.id) }.map(\.id)) }
                    .disabled(selection.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            TextField("Filter sources", text: $filter).textFieldStyle(.roundedBorder)
            if sources.isEmpty {
                EmptyPaneMessage(symbol: "books.vertical", title: "No Sources", message: "Add books, articles and websites, then cite them in your text.")
            } else {
                List(selection: $selection) {
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title.isEmpty ? "Untitled" : source.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text([source.authors.first.map { CitationFormatter.Name($0).last } ?? "", source.year, source.type.displayName]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        .tag(source.id)
                        .contextMenu {
                            Button("Cite") { editor.insertCitation(sourceIDs: [source.id]) }
                            Button("Edit…") { editing = source }
                            Divider()
                            Button("Delete", role: .destructive) { editor.deleteSource(source.id) }
                        }
                        .onTapGesture(count: 2) { editing = source }
                    }
                }
                .listStyle(.plain)
            }
            Divider()
            Button { editor.insertBibliography() } label: { Label("Insert or Update Bibliography", systemImage: "list.bullet.rectangle") }
            Button { editor.updateAllTables() } label: { Label("Update Citations & Tables", systemImage: "arrow.clockwise") }
        }
        .controlSize(.small)
        .padding(10)
        .sheet(item: $editing) { source in
            SourceEditorSheet(source: source, onSave: { saved in
                editor.saveSource(saved)
                editing = nil
            }, onCancel: { editing = nil })
        }
        .id(sidebar.revision)
    }
}

struct SourceEditorSheet: View {
    @State var source: CitationSource
    let onSave: (CitationSource) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetScaffold(title: "Source", primaryTitle: "Save", primaryDisabled: source.title.trimmingCharacters(in: .whitespaces).isEmpty,
                      width: 480, onPrimary: { onSave(source) }, onCancel: onCancel) {
            Form {
                Picker("Type", selection: $source.type) {
                    ForEach(SourceType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Authors", text: Binding(
                    get: { source.authors.joined(separator: "; ") },
                    set: { source.authors = $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ), prompt: Text("Last, First; Last, First"))
                TextField("Title", text: $source.title)
                TextField(containerLabel, text: $source.containerTitle)
                TextField("Year", text: $source.year)
                if source.type == .journalArticle || source.type == .conference {
                    TextField("Volume", text: $source.volume)
                    TextField("Issue", text: $source.issue)
                }
                if source.type != .website {
                    TextField("Pages", text: $source.pages)
                    TextField("Publisher", text: $source.publisher)
                    TextField("Place", text: $source.place)
                }
                if source.type == .book { TextField("Edition", text: $source.edition) }
                TextField("URL", text: $source.url)
                TextField("DOI", text: $source.doi)
                if source.type == .website { TextField("Accessed", text: $source.accessed) }
            }
            .formStyle(.grouped)
            .frame(height: 440)
        }
    }

    private var containerLabel: String {
        switch source.type {
        case .journalArticle: "Journal"
        case .website: "Website Name"
        case .chapter: "Book Title"
        case .conference: "Proceedings"
        default: "Series"
        }
    }
}

// MARK: - Captions, cross-references, bookmarks, index

struct CaptionSheet: View {
    let onInsert: (String, String) -> Void
    let onCancel: () -> Void
    @State private var label = "Figure"
    @State private var text = ""

    var body: some View {
        SheetScaffold(title: "Insert Caption", primaryTitle: "Insert", width: 400, onPrimary: { onInsert(label, text) }, onCancel: onCancel) {
            Form {
                Picker("Label", selection: $label) {
                    ForEach(EditorController.captionLabels, id: \.self) { Text($0).tag($0) }
                }
                TextField("Caption", text: $text, prompt: Text("Describe the \(label.lowercased())"))
                Text("Preview: \(label) 1\(text.isEmpty ? "" : ": " + text)").font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

struct CrossReferenceSheet: View {
    let targets: [EditorController.CrossReferenceTarget]
    let onInsert: (EditorController.CrossReferenceTarget, CrossReferenceDisplay, Bool) -> Void
    let onCancel: () -> Void
    @State private var selection: String?
    @State private var display: CrossReferenceDisplay = .text
    @State private var asLink = true

    var body: some View {
        SheetScaffold(title: "Cross-reference", primaryTitle: "Insert", primaryDisabled: selection == nil, width: 460, onPrimary: {
            if let target = targets.first(where: { $0.id == selection }) { onInsert(target, display, asLink) }
        }, onCancel: onCancel) {
            VStack(alignment: .leading, spacing: 10) {
                List(targets, selection: $selection) { target in
                    HStack {
                        Image(systemName: icon(for: target)).foregroundStyle(.secondary)
                        Text(target.title).lineLimit(1)
                    }
                    .tag(target.id)
                }
                .frame(height: 220)
                Picker("Insert", selection: $display) {
                    ForEach(CrossReferenceDisplay.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Insert as link", isOn: $asLink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private func icon(for target: EditorController.CrossReferenceTarget) -> String {
        switch target {
        case .heading: "textformat.size"
        case .caption: "photo.on.rectangle"
        case .bookmark: "bookmark"
        }
    }
}

struct BookmarkSheet: View {
    let existing: [String]
    let onAdd: (String) -> Void
    let onGoTo: (String) -> Void
    let onDelete: (String) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var selection: String?

    var body: some View {
        SheetScaffold(title: "Bookmarks", primaryTitle: "Add", primaryDisabled: !isValid, width: 380, onPrimary: { onAdd(name) }, onCancel: onCancel) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Bookmark name", text: $name).textFieldStyle(.roundedBorder)
                List(existing.filter { !$0.hasPrefix("_") }, id: \.self, selection: $selection) { Text($0).tag($0) }
                    .frame(height: 160)
                HStack {
                    Button("Go To") { if let selection { onGoTo(selection) } }.disabled(selection == nil)
                    Button("Delete") { if let selection { onDelete(selection) } }.disabled(selection == nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains(" ") && !trimmed.hasPrefix("_")
    }
}
