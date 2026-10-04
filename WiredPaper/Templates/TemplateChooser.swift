import AppKit
import SwiftUI

final class TemplateChooserWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TemplateChooserWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "New Document"
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }
        // Rebuild so the recent list and default fonts are current.
        window.contentViewController = NSHostingController(rootView: TemplateChooserView(
            onCreate: { [weak self] template in
                self?.close()
                (NSDocumentController.shared as? WiredPaperDocumentController)?.newDocument(from: template)
            },
            onOpen: { [weak self] url in
                self?.close()
                if let url {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error { NSApp.presentError(error) }
                    }
                } else {
                    NSDocumentController.shared.openDocument(nil)
                }
            },
            onCancel: { [weak self] in self?.close() }
        ))
        window.setContentSize(NSSize(width: 820, height: 560))
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }
}

struct TemplateChooserView: View {
    let onCreate: (DocumentTemplate) -> Void
    let onOpen: (URL?) -> Void
    let onCancel: () -> Void

    @State private var selection: DocumentTemplate = TemplateLibrary.blank
    private let recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(8))

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Color(nsColor: Theme.barBackground))

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 22)], spacing: 22) {
                        ForEach(TemplateLibrary.all) { template in
                            TemplateCard(template: template, isSelected: template == selection)
                                .onTapGesture(count: 2) { onCreate(template) }
                                .onTapGesture { selection = template }
                        }
                    }
                    .padding(28)
                }

                Divider()

                HStack {
                    Button("Open…") { onOpen(nil) }
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Create") { onCreate(selection) }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
            .background(Color(nsColor: Theme.canvas))
        }
        .frame(minWidth: 760, minHeight: 520)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { moveSelection(by: -1) }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -3) }
        .onKeyPress(.downArrow) { moveSelection(by: 3) }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let all = TemplateLibrary.all
        guard let index = all.firstIndex(of: selection) else { return .ignored }
        selection = all[min(max(index + offset, 0), all.count - 1)]
        return .handled
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wired Paper").font(.system(size: 15, weight: .semibold))
                    Text("Choose a template").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 36)

            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if recents.isEmpty {
                    Text("No recent documents")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url) { onOpen(url) }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

private struct TemplateCard: View {
    let template: DocumentTemplate
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: TemplateThumbnails.image(for: template))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .shadow(color: .black.opacity(hovering ? 0.22 : 0.14), radius: hovering ? 6 : 3, y: hovering ? 3 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accentColor : .clear, lineWidth: 3)
                        .padding(-5)
                )
                .scaleEffect(hovering ? 1.02 : 1)

            VStack(spacing: 2) {
                Text(template.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text(template.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 28, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(FileManager.default.displayName(atPath: url.path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}
