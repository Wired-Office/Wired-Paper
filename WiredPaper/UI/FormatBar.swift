import AppKit
import SwiftUI

/// The formatting ribbon beneath the toolbar. Reflects the formatting at the
/// insertion point and applies changes through the EditorController.
struct FormatBar: View {
    @ObservedObject var editor: EditorController

    private var state: FormattingState { editor.formatting }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                StylePicker(currentID: state.styleID, currentName: state.styleName, styles: editor.styleSheet.allStyles, onSelect: { editor.applyStyle(id: $0) }, onClear: editor.clearFormatting)
                    .frame(width: 124)

                FormatDivider()

                FontFamilyPicker(family: state.fontFamily, onSelect: editor.setFontFamily)
                    .frame(width: 168)
                    .padding(.trailing, 4)
                FontSizeField(size: state.fontSize, onCommit: editor.setFontSize)
                    .frame(width: 58)
                FormatIconButton(symbol: "textformat.size.larger", help: "Increase Font Size") { editor.adjustFontSize(larger: true) }
                FormatIconButton(symbol: "textformat.size.smaller", help: "Decrease Font Size") { editor.adjustFontSize(larger: false) }

                FormatDivider()

                FormatIconButton(symbol: "bold", help: "Bold (⌘B)", isOn: state.isBold, action: editor.toggleBold)
                FormatIconButton(symbol: "italic", help: "Italic (⌘I)", isOn: state.isItalic, action: editor.toggleItalic)
                FormatIconButton(symbol: "underline", help: "Underline (⌘U)", isOn: state.isUnderlined, action: editor.toggleUnderline)
                FormatIconButton(symbol: "strikethrough", help: "Strikethrough (⇧⌘X)", isOn: state.isStruckThrough, action: editor.toggleStrikethrough)

                ColorSplitButton(
                    symbol: "character",
                    help: "Text Color",
                    color: editor.lastTextColor,
                    kind: .text,
                    onApply: editor.setTextColor,
                    onMore: { HighlightColorRelay.beginTextColor(for: editor) }
                )
                ColorSplitButton(
                    symbol: "highlighter",
                    help: "Highlight",
                    color: editor.lastHighlightColor,
                    kind: .highlight,
                    onApply: editor.setHighlight,
                    onMore: { HighlightColorRelay.shared.begin(for: editor) }
                )

                FormatDivider()

                FormatIconButton(symbol: "text.alignleft", help: "Align Left (⌘{)", isOn: state.effectiveAlignment == .left) { editor.setAlignment(.left) }
                FormatIconButton(symbol: "text.aligncenter", help: "Center (⌘|)", isOn: state.effectiveAlignment == .center) { editor.setAlignment(.center) }
                FormatIconButton(symbol: "text.alignright", help: "Align Right (⌘})", isOn: state.effectiveAlignment == .right) { editor.setAlignment(.right) }
                FormatIconButton(symbol: "text.justify", help: "Justify", isOn: state.effectiveAlignment == .justified) { editor.setAlignment(.justified) }

                FormatDivider()

                FormatIconButton(symbol: "list.bullet", help: "Bulleted List (⇧⌘L)", isOn: state.listKind == .bullet) { editor.toggleList(.bullet) }
                FormatIconButton(symbol: "list.number", help: "Numbered List (⌥⌘L)", isOn: state.listKind == .numbered) { editor.toggleList(.numbered) }
                FormatIconButton(symbol: "decrease.indent", help: "Decrease Indent (⌘[)") { editor.changeIndent(by: -36) }
                FormatIconButton(symbol: "increase.indent", help: "Increase Indent (⌘])") { editor.changeIndent(by: 36) }
                LineSpacingMenu(current: state.lineHeightMultiple, onSelect: editor.setLineSpacing)

                FormatDivider()

                FormatIconButton(symbol: "eraser", help: "Clear Formatting", action: editor.clearFormatting)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.barBackground))
    }
}

private struct StylePicker: View {
    let currentID: String
    let currentName: String
    let styles: [StyleDefinition]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            ForEach(styles) { style in
                Toggle(style.name, isOn: Binding(
                    get: { style.id == currentID },
                    set: { _ in onSelect(style.id) }
                ))
            }
            Divider()
            Button("Clear Formatting", action: onClear)
            Button("Manage Styles…") {
                NSApp.sendAction(#selector(DocumentViewController.showStylesManager(_:)), to: nil, from: nil)
            }
        } label: {
            Text(currentName)
        }
        .help("Paragraph Style")
    }
}

private struct LineSpacingMenu: View {
    let current: CGFloat
    let onSelect: (CGFloat) -> Void
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(LineSpacingOption.all) { option in
                Toggle(option.title, isOn: Binding(
                    get: { abs(current - option.multiple) < 0.01 },
                    set: { _ in onSelect(option.multiple) }
                ))
            }
            Divider()
            Button("Paragraph Options…") {
                NSApp.sendAction(#selector(DocumentViewController.showParagraphOptions(_:)), to: nil, from: nil)
            }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(FormatButtonStyle(hovering: hovering))
        .menuIndicator(.hidden)
        .frame(width: 30, height: 26)
        .onHover { hovering = $0 }
        .help("Line Spacing")
    }
}
