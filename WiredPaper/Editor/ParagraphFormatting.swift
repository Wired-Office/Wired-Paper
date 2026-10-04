import AppKit

// MARK: - Borders & shading

struct ParagraphBorderSettings: Equatable {
    var top = false
    var bottom = false
    var left = false
    var right = false
    var width: CGFloat = 1
    var color: NSColor = .black
    var shading: NSColor?
    var padding: CGFloat = 4

    var hasBorder: Bool { top || bottom || left || right }
    var isEmpty: Bool { !hasBorder && shading == nil }

    static let box = ParagraphBorderSettings(top: true, bottom: true, left: true, right: true)
}

/// Borders and shading around paragraphs, using TextKit's NSTextBlock.
/// Consecutive paragraphs styled together share one block and so one box.
enum ParagraphBorders {
    static func block(in style: NSParagraphStyle?) -> NSTextBlock? {
        style?.textBlocks.last.flatMap { $0 is NSTextTableBlock ? nil : $0 }
    }

    static func current(in textView: NSTextView) -> ParagraphBorderSettings {
        guard let storage = textView.textStorage else { return ParagraphBorderSettings() }
        let location = min(textView.selectedRange().location, max(storage.length - 1, 0))
        guard storage.length > 0,
              let block = block(in: storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        else { return ParagraphBorderSettings() }
        var settings = ParagraphBorderSettings()
        settings.left = block.width(for: .border, edge: .minX) > 0
        settings.right = block.width(for: .border, edge: .maxX) > 0
        settings.top = block.width(for: .border, edge: .minY) > 0
        settings.bottom = block.width(for: .border, edge: .maxY) > 0
        settings.width = [NSRectEdge.minX, .maxX, .minY, .maxY].map { block.width(for: .border, edge: $0) }.max() ?? 1
        settings.color = block.borderColor(for: .minY) ?? block.borderColor(for: .minX) ?? .black
        settings.shading = block.backgroundColor
        settings.padding = block.width(for: .padding, edge: .minX)
        return settings
    }

    static func makeBlock(_ settings: ParagraphBorderSettings) -> NSTextBlock {
        let block = NSTextBlock()
        let edges: [(NSRectEdge, Bool)] = [(.minX, settings.left), (.maxX, settings.right), (.minY, settings.top), (.maxY, settings.bottom)]
        for (edge, on) in edges {
            block.setWidth(on ? settings.width : 0, type: .absoluteValueType, for: .border, edge: edge)
            block.setBorderColor(settings.color, for: edge)
        }
        block.setWidth(settings.padding, type: .absoluteValueType, for: .padding)
        block.setWidth(2, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(2, type: .absoluteValueType, for: .margin, edge: .maxY)
        block.backgroundColor = settings.shading
        return block
    }

    static func apply(_ settings: ParagraphBorderSettings, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let ranges = (textView.rangesForUserParagraphAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) else { return }
        let block = settings.isEmpty ? nil : makeBlock(settings)
        storage.beginEditing()
        for range in ranges {
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                let existing = value as? NSParagraphStyle ?? .default
                // Table cells keep their table structure.
                guard !existing.textBlocks.contains(where: { $0 is NSTextTableBlock }),
                      let updated = existing.mutableCopy() as? NSMutableParagraphStyle else { return }
                updated.textBlocks = block.map { [$0] } ?? []
                storage.addAttribute(.paragraphStyle, value: updated, range: run)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(settings.isEmpty ? "Remove Borders" : "Borders and Shading")
    }
}

// MARK: - Tab stops & leaders

enum TabLeader: String, CaseIterable, Identifiable {
    case none, dot, dash, line
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .dot: "Dots ……"
        case .dash: "Dashes – – –"
        case .line: "Line ____"
        }
    }
}

struct TabStopSpec: Identifiable, Equatable {
    var id = UUID()
    var location: CGFloat
    var alignment: NSTextAlignment = .left
    var leader: TabLeader = .none
    var isDecimal = false
}

enum TabStops {
    /// Parses the paragraph-level leader map: "360:dot;432:line" (or a bare leader for all tabs).
    static func leaderMap(_ value: Any?) -> [CGFloat: String] {
        guard let string = value as? String, string.contains(":") else { return [:] }
        var map: [CGFloat: String] = [:]
        for entry in string.split(separator: ";") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let location = Double(parts[0]) { map[CGFloat(location)] = String(parts[1]) }
        }
        return map
    }

    static func current(in textView: NSTextView) -> ([TabStopSpec], CGFloat) {
        guard let storage = textView.textStorage else { return ([], 36) }
        let location = textView.selectedRange().location
        let attributes = location < storage.length ? storage.attributes(at: location, effectiveRange: nil) : textView.typingAttributes
        let style = attributes[.paragraphStyle] as? NSParagraphStyle ?? .default
        let leaders = leaderMap(attributes[.wpTabLeader])
        let tabs = style.tabStops.map { tab in
            TabStopSpec(
                location: tab.location,
                alignment: tab.alignment,
                leader: leaders[tab.location].flatMap(TabLeader.init(rawValue:)) ?? .none,
                isDecimal: tab.options[.columnTerminators] != nil
            )
        }
        return (tabs, style.defaultTabInterval == 0 ? 36 : style.defaultTabInterval)
    }

    static func apply(_ tabs: [TabStopSpec], defaultInterval: CGFloat, in textView: NSTextView) {
        let sorted = tabs.sorted { $0.location < $1.location }
        let leaderValue = sorted.filter { $0.leader != .none }.map { "\(Int($0.location.rounded())):\($0.leader.rawValue)" }.joined(separator: ";")
        TextFormatter.changeParagraphs(in: textView, actionName: "Tabs") { style in
            style.tabStops = sorted.map { spec in
                var options: [NSTextTab.OptionKey: Any] = [:]
                if spec.isDecimal {
                    options[.columnTerminators] = NSTextTab.columnTerminators(for: .current)
                }
                return NSTextTab(textAlignment: spec.isDecimal ? .right : spec.alignment, location: spec.location.rounded(), options: options)
            }
            style.defaultTabInterval = max(defaultInterval, 6)
        }
        // Leaders live on the paragraphs as a location→leader map.
        guard let storage = textView.textStorage else { return }
        let ranges = (textView.rangesForUserParagraphAttributeChange ?? []).map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty, textView.shouldChangeText(inRanges: ranges as [NSValue], replacementStrings: nil) else { return }
        for range in ranges {
            if leaderValue.isEmpty {
                storage.removeAttribute(.wpTabLeader, range: range)
            } else {
                storage.addAttribute(.wpTabLeader, value: leaderValue, range: range)
            }
        }
        textView.didChangeText()
    }
}
