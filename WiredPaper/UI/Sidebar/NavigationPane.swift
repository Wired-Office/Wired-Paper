import AppKit
import SwiftUI

/// Left sidebar: headings outline, page thumbnails and search results.
struct NavigationPane: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Navigation").font(.headline)
                Spacer()
                Button { sidebar.left = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Picker("", selection: $sidebar.navigationTab) {
                ForEach(SidebarModel.NavigationTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            switch sidebar.navigationTab {
            case .headings: HeadingsList(editor: editor, sidebar: sidebar)
            case .pages: PagesList(editor: editor)
            case .results: SearchResultsList(editor: editor, sidebar: sidebar)
            }
        }
        .background(Color(nsColor: Theme.barBackground))
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct HeadingsList: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        if sidebar.outline.isEmpty {
            EmptyPaneMessage(symbol: "list.bullet.indent", title: "No Headings", message: "Apply Heading styles to see your document’s structure here.")
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(sidebar.outline) { item in
                        HeadingRow(item: item, isCurrent: sidebar.currentOutlineID == item.id)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { editor.reveal(NSRange(location: item.range.location, length: 0)) }
                            .contextMenu {
                                Button("Select Section") { editor.selectSection(item) }
                                Divider()
                                Button("Move Up") { editor.moveSection(item, up: true) }
                                Button("Move Down") { editor.moveSection(item, up: false) }
                                Divider()
                                Button("Promote") { editor.changeHeadingLevel(item, by: -1) }.disabled(item.level <= 1)
                                Button("Demote") { editor.changeHeadingLevel(item, by: 1) }.disabled(item.level == 0 || item.level >= 9)
                                Divider()
                                Button("Delete Section", role: .destructive) { editor.deleteSection(item) }
                            }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: sidebar.currentOutlineID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }
}

private struct HeadingRow: View {
    let item: OutlineItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: item.level <= 1 ? 12.5 : 12, weight: item.level <= 1 ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.accentColor : .primary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("\(item.page)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.leading, CGFloat(max(item.level - 1, 0)) * 12)
        .padding(.vertical, 2)
    }
}

private struct PagesList: View {
    @ObservedObject var editor: EditorController

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(0..<editor.pageCount, id: \.self) { index in
                    PageThumbnail(editor: editor, index: index)
                }
            }
            .padding(14)
        }
    }
}

private struct PageThumbnail: View {
    @ObservedObject var editor: EditorController
    let index: Int
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color.white).aspectRatio(editor.geometry.paperSize.width / editor.geometry.paperSize.height, contentMode: .fit)
                }
            }
            .frame(width: 150)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(editor.currentPage == index + 1 ? Theme.accentColor : .clear, lineWidth: 2).padding(-3))
            Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { editor.scrollToPage(index) }
        .task(id: editor.sidebar.revision) {
            image = editor.pageThumbnail(index, width: 300)
        }
    }
}

private struct SearchResultsList: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var sidebar: SidebarModel
    @State private var replacedCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search document", text: $sidebar.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit(runSearch)
            HStack(spacing: 10) {
                Toggle("Aa", isOn: $sidebar.searchOptions.matchCase).help("Match case")
                Toggle("Word", isOn: $sidebar.searchOptions.wholeWords).help("Whole words only")
                Toggle(".*", isOn: $sidebar.searchOptions.useRegex).help("Regular expression")
                Toggle("*?", isOn: $sidebar.searchOptions.useWildcards).help("Wildcards: * any text, ? one character")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            HStack {
                TextField("Replace with", text: $sidebar.replacement)
                    .textFieldStyle(.roundedBorder)
                Button("Replace All") {
                    replacedCount = editor.replaceAll(sidebar.searchQuery, with: sidebar.replacement, options: sidebar.searchOptions)
                    runSearch()
                }
                .disabled(sidebar.searchQuery.isEmpty)
            }
            .controlSize(.small)
            if let replacedCount {
                Text("\(replacedCount) replaced").font(.caption).foregroundStyle(.secondary)
            } else if !sidebar.searchQuery.isEmpty {
                Text("\(sidebar.searchResults.count) results").font(.caption).foregroundStyle(.secondary)
            }
            List(sidebar.searchResults) { result in
                VStack(alignment: .leading, spacing: 2) {
                    (Text(result.before).foregroundStyle(.secondary)
                     + Text(result.match).bold().foregroundStyle(Theme.accentColor)
                     + Text(result.after).foregroundStyle(.secondary))
                        .font(.system(size: 11.5))
                        .lineLimit(2)
                    Text("Page \(result.page)").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { editor.reveal(result.range) }
            }
            .listStyle(.plain)
        }
        .padding(.horizontal, 10)
        .onChange(of: sidebar.searchQuery) { _, _ in runSearch() }
        .onChange(of: sidebar.searchOptions) { _, _ in runSearch() }
        .onDisappear { editor.clearSearchHighlights() }
    }

    private func runSearch() {
        replacedCount = nil
        sidebar.searchResults = editor.search(sidebar.searchQuery, options: sidebar.searchOptions)
    }
}

struct EmptyPaneMessage: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(message).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}
