import SwiftUI

struct LinkSheet: View {
    let isEditingExisting: Bool
    let onApply: (_ text: String, _ url: String) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var url: String

    init(
        text: String,
        url: String,
        isEditingExisting: Bool,
        onApply: @escaping (String, String) -> Void,
        onRemove: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = State(initialValue: text)
        _url = State(initialValue: url)
        self.isEditingExisting = isEditingExisting
        self.onApply = onApply
        self.onRemove = onRemove
        self.onCancel = onCancel
    }

    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(isEditingExisting ? "Edit Link" : "Insert Link", systemImage: "link")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Text:").gridColumnAlignment(.trailing)
                    TextField("Text to display", text: $text)
                }
                GridRow {
                    Text("Address:")
                    TextField("https://example.com or name@example.com", text: $url)
                }
            }

            HStack {
                if isEditingExisting {
                    Button("Remove Link", role: .destructive, action: onRemove)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isEditingExisting ? "Update" : "Insert") { onApply(text, trimmedURL) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedURL.isEmpty || EditorController.normalizedURL(trimmedURL) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
