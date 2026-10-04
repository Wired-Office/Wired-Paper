import AppKit
import SwiftUI

/// Right sidebar: a tab strip over comments, review, notes, citations and Wired AI.
struct RightSidebar: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SidebarModel.RightPane.allCases) { pane in
                    Button {
                        sidebar.right = pane
                    } label: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 13))
                            .frame(width: 30, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FormatButtonStyle(isOn: sidebar.right == pane))
                    .help(pane.title)
                }
                Spacer()
                Button { sidebar.right = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            Group {
                switch sidebar.right {
                case .comments: CommentsPane(editor: editor, sidebar: sidebar)
                case .review: ReviewPane(editor: editor, sidebar: sidebar)
                case .notes: NotesPane(editor: editor, sidebar: sidebar)
                case .references: ReferencesPane(editor: editor, sidebar: sidebar)
                case .styles: StylesPane(editor: editor)
                case .editor: EditorPane(editor: editor)
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: Theme.barBackground))
        .overlay(alignment: .leading) { Divider() }
    }
}

// MARK: - Shared bits

struct AuthorBadge: View {
    let name: String

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials.isEmpty ? "?" : initials.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(nsColor: RevisionMarkup.color(forAuthor: name))))
    }
}

/// Renders @mentions in the accent color.
func mentionText(_ text: String) -> Text {
    var result = Text("")
    for (index, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
        let piece = (index > 0 ? " " : "") + word
        result = result + (word.hasPrefix("@") ? Text(piece).foregroundColor(Theme.accentColor).bold() : Text(piece))
    }
    return result
}

// MARK: - Comments

struct CommentsPane: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @ObservedObject private var document: WiredPaperDocument

    init(editor: EditorController, sidebar: SidebarModel) {
        self.editor = editor
        self.sidebar = sidebar
        self.document = editor.document ?? WiredPaperDocument()
    }

    var body: some View {
        let threads = editor.commentThreads(includeResolved: sidebar.showResolvedComments)
        VStack(spacing: 0) {
            HStack {
                Button { editor.addComment() } label: { Label("New Comment", systemImage: "plus.bubble") }
                Spacer()
                Toggle("Resolved", isOn: $sidebar.showResolvedComments)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Menu {
                    Button("Delete All Resolved") { editor.deleteAllComments(resolvedOnly: true) }
                    Button("Delete All Comments", role: .destructive) { editor.deleteAllComments() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            .controlSize(.small)
            .padding(10)

            if threads.isEmpty {
                EmptyPaneMessage(symbol: "text.bubble", title: "No Comments", message: "Select text and choose New Comment (⌥⌘A).")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(threads, id: \.thread.id) { item in
                                CommentCard(editor: editor, sidebar: sidebar, thread: item.thread, anchor: item.anchor,
                                            isActive: editor.activeCommentID == item.thread.id)
                                    .id(item.thread.id)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: editor.activeCommentID) { _, id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }
}

private struct CommentCard: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    let thread: CommentThread
    let anchor: String
    let isActive: Bool
    @State private var draft = ""
    @State private var reply = ""
    @FocusState private var editorFocused: Bool

    private static let reactions = ["👍", "❤️", "😄", "🎉", "👀"]
    private var isEditing: Bool { sidebar.editingCommentID == thread.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AuthorBadge(name: thread.author)
                VStack(alignment: .leading, spacing: 0) {
                    Text(thread.author).font(.system(size: 12, weight: .semibold))
                    Text(thread.date, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { editor.toggleCommentResolved(thread.id) } label: {
                    Image(systemName: thread.resolved ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .buttonStyle(.borderless)
                .help(thread.resolved ? "Reopen" : "Resolve")
                Menu {
                    Button("Edit") { draft = thread.text; sidebar.editingCommentID = thread.id }
                    Button("Delete", role: .destructive) { editor.deleteComment(thread.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            if !anchor.isEmpty {
                Text(anchor)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 6)
                    .overlay(Rectangle().fill(Color(nsColor: RevisionMarkup.color(forAuthor: thread.author))).frame(width: 2), alignment: .leading)
            }
            if isEditing {
                TextField("Add a comment… use @Name to mention", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
                    .focused($editorFocused)
                    .onAppear {
                        draft = thread.text
                        editorFocused = true
                    }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        sidebar.editingCommentID = nil
                        if thread.text.isEmpty { editor.deleteComment(thread.id) }
                    }
                    Button("Post") {
                        editor.setCommentText(thread.id, text: draft)
                        sidebar.editingCommentID = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
            } else {
                mentionText(thread.text)
                    .font(.system(size: 12))
                    .strikethrough(thread.resolved)
                    .textSelection(.enabled)
            }

            ForEach(thread.replies) { item in
                HStack(alignment: .top, spacing: 6) {
                    AuthorBadge(name: item.author).scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.author).font(.system(size: 11, weight: .semibold))
                        mentionText(item.text).font(.system(size: 11.5))
                    }
                }
                .padding(.leading, 8)
            }

            HStack(spacing: 4) {
                ForEach(Self.reactions, id: \.self) { emoji in
                    let people = thread.reactions[emoji] ?? []
                    Button {
                        editor.toggleReaction(emoji, on: thread.id)
                    } label: {
                        Text(people.isEmpty ? emoji : "\(emoji) \(people.count)")
                            .font(.system(size: 11))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(people.contains(AppSettings.shared.authorName) ? Theme.accentColor.opacity(0.2) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(people.joined(separator: ", "))
                    .opacity(people.isEmpty ? 0.55 : 1)
                }
            }

            if !isEditing && !thread.resolved {
                HStack {
                    TextField("Reply…", text: $reply)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(sendReply)
                    Button(action: sendReply) { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
            }
            if !thread.mentions.isEmpty {
                Text("Mentions: " + thread.mentions.map { "@" + $0 }.joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isActive ? 0.18 : 0.06), radius: isActive ? 5 : 2, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isActive ? Theme.accentColor : .clear, lineWidth: 1.5))
        .opacity(thread.resolved ? 0.65 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editor.selectComment(thread.id) }
        .animation(.easeOut(duration: 0.15), value: isActive)
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        editor.replyToComment(thread.id, text: text)
        reply = ""
    }
}

// MARK: - Review (Track Changes)

struct ReviewPane: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @State private var authorFilter: String?

    var body: some View {
        let entries = editor.revisionEntries().filter { authorFilter == nil || $0.author == authorFilter }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Track Changes", isOn: Binding(get: { editor.isTrackingChanges }, set: { editor.setTracking($0) }))
                    .toggleStyle(.switch)
                    .disabled(editor.document?.metadata.protection.restriction == .trackedChanges)
                Picker("Show", selection: Binding(get: { editor.markupMode }, set: { editor.setMarkupMode($0) })) {
                    ForEach(MarkupMode.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Button { editor.moveToChange(forward: false) } label: { Image(systemName: "chevron.up") }.help("Previous Change")
                    Button { editor.moveToChange(forward: true) } label: { Image(systemName: "chevron.down") }.help("Next Change")
                    Spacer()
                    Menu("Accept") {
                        Button("Accept This Change") { editor.acceptCurrentChange(true) }
                        Button("Accept All Changes") { editor.resolveAllChanges(accept: true) }
                        ForEach(editor.knownAuthors, id: \.self) { author in
                            Button("Accept All by \(author)") { editor.resolveAllChanges(accept: true, author: author) }
                        }
                    }
                    .fixedSize()
                    Menu("Reject") {
                        Button("Reject This Change") { editor.acceptCurrentChange(false) }
                        Button("Reject All Changes") { editor.resolveAllChanges(accept: false) }
                        ForEach(editor.knownAuthors, id: \.self) { author in
                            Button("Reject All by \(author)") { editor.resolveAllChanges(accept: false, author: author) }
                        }
                    }
                    .fixedSize()
                }
                Picker("Author", selection: $authorFilter) {
                    Text("All Reviewers").tag(String?.none)
                    ForEach(editor.knownAuthors, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            .controlSize(.small)
            .padding(10)
            Divider()
            if entries.isEmpty {
                EmptyPaneMessage(symbol: "pencil.and.list.clipboard", title: "No Changes",
                                 message: editor.isTrackingChanges ? "Edits you make now are tracked." : "Turn on Track Changes (⇧⌘E) to record edits.")
            } else {
                Text("\(entries.count) change\(entries.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 6)
                List(entries) { entry in
                    RevisionRow(entry: entry, editor: editor)
                }
                .listStyle(.plain)
            }
        }
        .id(sidebar.revision)
    }
}

private struct RevisionRow: View {
    let entry: RevisionEntry
    @ObservedObject var editor: EditorController

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(Color(nsColor: RevisionMarkup.color(forAuthor: entry.author))).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.kind == .insertion ? "Inserted" : entry.kind == .deletion ? "Deleted" : "Formatted")
                        .font(.system(size: 11, weight: .semibold))
                    Text(entry.author).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text(entry.excerpt)
                    .font(.system(size: 11.5))
                    .strikethrough(entry.kind == .deletion)
                    .lineLimit(3)
                HStack {
                    Button("Accept") { editor.resolveRevision(entry, accept: true) }
                    Button("Reject") { editor.resolveRevision(entry, accept: false) }
                }
                .controlSize(.mini)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editor.reveal(entry.range) }
    }
}

// MARK: - Notes

struct NotesPane: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        let notes = editor.noteEntries()
        VStack(spacing: 0) {
            HStack {
                Button { editor.insertNote(isEndnote: false) } label: { Label("Footnote", systemImage: "plus") }
                Button { editor.insertNote(isEndnote: true) } label: { Label("Endnote", systemImage: "plus") }
                Spacer()
            }
            .controlSize(.small)
            .padding(10)
            if notes.isEmpty {
                EmptyPaneMessage(symbol: "note.text", title: "No Notes", message: "Insert a footnote (⌥⇧⌘F) or endnote (⌥⇧⌘E) at the insertion point.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(notes) { note in
                            NoteCard(note: note, editor: editor, sidebar: sidebar)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .id(sidebar.revision)
    }
}

private struct NoteCard: View {
    let note: NoteEntry
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.isEndnote ? "Endnote \(PageNumberFormat.lowerRoman.format(note.number))" : "Footnote \(note.number)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { editor.goToNoteReference(note.id) } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(.borderless).help("Go to reference")
                Button { editor.deleteNote(note.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete note")
            }
            TextField("Note text", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { editor.setNoteText(note.id, text: text) }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, text != note.text { editor.setNoteText(note.id, text: text) }
                }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .onAppear {
            text = note.text
            if sidebar.editingCommentID == note.id {
                focused = true
                sidebar.editingCommentID = nil
            }
        }
    }
}
