import SwiftUI

struct StatusBar: View {
    @ObservedObject var editor: EditorController
    @State private var showingStatistics = false

    var body: some View {
        HStack(spacing: 10) {
            Text("Page \(editor.currentPage) of \(editor.pageCount)")
                .monospacedDigit()

            separator

            Button {
                showingStatistics.toggle()
            } label: {
                Text(wordsLabel).monospacedDigit()
            }
            .buttonStyle(.plain)
            .help("Show document statistics")
            .popover(isPresented: $showingStatistics, arrowEdge: .top) {
                StatisticsPopover(statistics: editor.statistics, selection: editor.selectionStatistics, pages: editor.pageCount)
            }

            separator

            Text(charactersLabel)
                .monospacedDigit()

            Spacer(minLength: 12)

            ZoomControl(editor: editor)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.barBackground))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 11)
    }

    private var wordsLabel: String {
        let total = editor.statistics.words
        let unit = total == 1 ? "word" : "words"
        if let selection = editor.selectionStatistics {
            return "\(selection.words.formatted()) of \(total.formatted()) \(unit)"
        }
        return "\(total.formatted()) \(unit)"
    }

    private var charactersLabel: String {
        let count = editor.selectionStatistics?.characters ?? editor.statistics.characters
        return "\(count.formatted()) \(count == 1 ? "character" : "characters")"
    }
}

private struct StatisticsPopover: View {
    let statistics: DocumentStatistics
    let selection: DocumentStatistics?
    let pages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Word Count").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
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
            .font(.system(size: 12))
        }
        .padding(16)
        .fixedSize()
    }

    @ViewBuilder
    private func row(_ title: String, _ selected: Int?, _ total: Int) -> some View {
        GridRow {
            Text(title)
            if selection != nil {
                Text(selected.map { $0.formatted() } ?? "—").monospacedDigit().gridColumnAlignment(.trailing)
            }
            Text(total.formatted()).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}

struct ZoomControl: View {
    @ObservedObject var editor: EditorController
    private static let presets: [CGFloat] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]

    var body: some View {
        HStack(spacing: 6) {
            Button(action: editor.zoomOut) {
                Image(systemName: "minus").frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zoom Out (⌘-)")

            Slider(value: Binding(
                get: { Self.position(for: editor.zoom) },
                set: { editor.setZoom(Self.zoom(for: $0), animated: false) }
            ), in: 0...1)
            .controlSize(.mini)
            .frame(width: 110)
            .help("Zoom")

            Button(action: editor.zoomIn) {
                Image(systemName: "plus").frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zoom In (⌘=)")

            Menu {
                ForEach(Self.presets, id: \.self) { preset in
                    Button("\(Int(preset * 100))%") { editor.setZoom(preset) }
                }
                Divider()
                Button("Fit Page Width", action: editor.zoomToPageWidth)
            } label: {
                Text("\(Int((editor.zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Piecewise slider mapping so 100% sits in the middle, like most editors.
    static func position(for zoom: CGFloat) -> Double {
        let minZoom = EditorController.minZoom, maxZoom = EditorController.maxZoom
        if zoom <= 1 { return Double((zoom - minZoom) / (1 - minZoom) * 0.5) }
        return Double(0.5 + (zoom - 1) / (maxZoom - 1) * 0.5)
    }

    static func zoom(for position: Double) -> CGFloat {
        let p = CGFloat(position)
        let minZoom = EditorController.minZoom, maxZoom = EditorController.maxZoom
        let value = p <= 0.5 ? minZoom + p / 0.5 * (1 - minZoom) : 1 + (p - 0.5) / 0.5 * (maxZoom - 1)
        return abs(value - 1) < 0.04 ? 1 : value
    }
}
