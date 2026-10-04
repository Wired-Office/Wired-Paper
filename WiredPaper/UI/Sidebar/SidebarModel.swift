import AppKit
import Combine

/// Which side panes are open and their shared state.
final class SidebarModel: ObservableObject {
    enum LeftPane: String, CaseIterable, Identifiable {
        case navigation, files
        var id: String { rawValue }
    }

    enum RightPane: String, CaseIterable, Identifiable {
        case comments, review, notes, references, styles, editor
        var id: String { rawValue }

        var title: String {
            switch self {
            case .styles: "Styles"
            case .editor: "Editor"
            case .comments: "Comments"
            case .review: "Review"
            case .notes: "Notes"
            case .references: "Citations"
            }
        }

        var symbol: String {
            switch self {
            case .comments: "text.bubble"
            case .review: "pencil.and.list.clipboard"
            case .notes: "note.text"
            case .references: "books.vertical"
            case .styles: "textformat"
            case .editor: "pencil.and.scribble"
            }
        }
    }

    enum NavigationTab: String, CaseIterable, Identifiable {
        case headings, pages, results
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Published var left: LeftPane?
    @Published var right: RightPane?
    @Published var navigationTab: NavigationTab = .headings

    @Published var outline: [OutlineItem] = []
    @Published var currentOutlineID: Int?

    @Published var searchQuery = ""
    @Published var replacement = ""
    @Published var searchOptions = SearchOptions()
    @Published var searchResults: [SearchResult] = []

    @Published var editingCommentID: String?
    @Published var showResolvedComments = true

    /// Incremented when the document's comments, revisions or notes may have changed.
    @Published var revision = 0

    func toggleLeft(_ pane: LeftPane) {
        left = left == pane ? nil : pane
    }

    func toggleRight(_ pane: RightPane) {
        right = right == pane ? nil : pane
    }
}
