import SwiftUI

struct InsertTableSheet: View {
    let onInsert: (_ rows: Int, _ columns: Int) -> Void
    let onCancel: () -> Void

    @State private var rows = 3
    @State private var columns = 3

    private let gridRows = 8
    private let gridColumns = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Table")
                .font(.headline)

            VStack(spacing: 3) {
                ForEach(0..<gridRows, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<gridColumns, id: \.self) { column in
                            let selected = row < rows && column < columns
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(selected ? Theme.accentColor.opacity(0.35) : Color.primary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .strokeBorder(selected ? Theme.accentColor : Color.primary.opacity(0.18), lineWidth: selected ? 1 : 0.5)
                                )
                                .frame(width: 22, height: 16)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    guard inside else { return }
                                    rows = row + 1
                                    columns = column + 1
                                }
                                .onTapGesture { onInsert(row + 1, column + 1) }
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.08), value: rows)
            .animation(.easeOut(duration: 0.08), value: columns)

            Text("\(columns) × \(rows) table")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 20) {
                Stepper("Columns: \(columns)", value: $columns, in: 1...20)
                Stepper("Rows: \(rows)", value: $rows, in: 1...200)
            }
            .monospacedDigit()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { onInsert(rows, columns) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}
