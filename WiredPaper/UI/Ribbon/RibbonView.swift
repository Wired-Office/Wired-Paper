import AppKit
import SwiftUI

/// The Word-style ribbon: a row of tabs over the selected tab's commands.
/// Double-click a tab (or use the chevron) to collapse it to just the tabs.
struct RibbonView: View {
    @ObservedObject var model: RibbonModel
    @ObservedObject var editor: EditorController
    @ObservedObject var document: WiredPaperDocument
    let isFocusMode: () -> Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            if !model.isCollapsed {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        content(width: proxy.size.width)
                            .padding(.horizontal, 10)
                            .frame(height: RibbonModel.contentHeight, alignment: .center)
                    }
                }
                .frame(height: RibbonModel.contentHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: Theme.barBackground))
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(RibbonModel.Tab.allCases) { tab in
                RibbonTabButton(title: tab.title, isSelected: model.tab == tab && !model.isCollapsed) {
                    if model.tab == tab && !model.isCollapsed { return }
                    model.tab = tab
                    if model.isCollapsed { model.isCollapsed = false }
                } onDoubleClick: {
                    model.tab = tab
                    model.isCollapsed.toggle()
                }
            }
            Spacer(minLength: 8)
            Button {
                model.isCollapsed.toggle()
            } label: {
                Image(systemName: model.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RibbonButtonStyle())
            .help(model.isCollapsed ? "Show the Ribbon" : "Collapse the Ribbon")
        }
        .padding(.horizontal, 12)
        .frame(height: RibbonModel.tabHeight)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch model.tab {
        case .home: HomeTab(editor: editor, sidebar: editor.sidebar, availableWidth: width)
        case .insert: InsertTab(editor: editor)
        case .draw: DrawTab(editor: editor)
        case .design: DesignTab(editor: editor, document: document)
        case .layout: LayoutTab(editor: editor, document: document)
        case .references: ReferencesTab(editor: editor, sidebar: editor.sidebar)
        case .mailings: MailingsTab(editor: editor, document: document)
        case .review: ReviewTab(editor: editor, sidebar: editor.sidebar, document: document)
        case .view: ViewTab(editor: editor, sidebar: editor.sidebar, isFocusMode: isFocusMode())
        }
    }
}

private struct RibbonTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.78))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering && !isSelected ? Color.primary.opacity(0.07) : .clear)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? Theme.accentColor : .clear)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onDoubleClick)
            .onTapGesture(count: 1, perform: action)
            .onHover { hovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}
