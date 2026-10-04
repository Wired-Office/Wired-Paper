import AppKit

/// Installs the right attachment cell for an object.
enum ObjectCells {
    static func install(for attachment: NSTextAttachment, object: DocumentObject) {
        switch object.kind {
        case .field, .footnote, .endnote, .checkbox, .dropdown, .date:
            if let cell = attachment.attachmentCell as? LiveTextCell {
                cell.object = object
            } else {
                attachment.attachmentCell = LiveTextCell(object: object)
            }
        default:
            // Graphic objects display a freshly rendered image, so edits and
            // renderer improvements always show.
            if let cell = attachment.attachmentCell as? ObjectImageCell, cell.json == object.json { return }
            guard let image = ObjectRenderer.image(for: object) else {
                if attachment.attachmentCell is LiveTextCell { attachment.attachmentCell = nil }
                return
            }
            let cell = ObjectImageCell(imageCell: image)
            cell.json = object.json
            attachment.attachmentCell = cell
        }
    }
}

/// Displays a rendered graphic object; remembers which object state it shows.
final class ObjectImageCell: NSTextAttachmentCell {
    var json = ""

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -3)
    }
}

/// An attachment cell that draws text computed at layout time: page numbers,
/// dates, caption numbers, cross-references, note reference marks and form
/// control values. Its width follows the text, so the line reflows when the
/// value changes.
final class LiveTextCell: NSTextAttachmentCell {
    var object: DocumentObject

    init(object: DocumentObject) {
        self.object = object
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        object = DocumentObject(kind: .field)
        super.init(coder: coder)
    }

    private var isNoteReference: Bool { object.kind == .footnote || object.kind == .endnote }

    // MARK: Content

    func text(characterIndex: Int, layoutManager: NSLayoutManager?, container: NSTextContainer?) -> String {
        let manager = layoutManager as? WPLayoutManager
        switch object.kind {
        case .footnote:
            return String(manager?.noteNumbers[object.id] ?? 1)
        case .endnote:
            return PageNumberFormat.lowerRoman.format(manager?.noteNumbers[object.id] ?? 1)
        case .checkbox, .dropdown, .date:
            return object.form?.displayText ?? ""
        case .field:
            guard let field = object.field else { return "" }
            return FieldEvaluator.text(for: field, objectID: object.id, characterIndex: characterIndex, layoutManager: manager, container: container)
        default:
            return ""
        }
    }

    func attributes(characterIndex: Int, layoutManager: NSLayoutManager?) -> [NSAttributedString.Key: Any] {
        var font = NSFont.systemFont(ofSize: 12)
        var color = NSColor.black
        if let storage = layoutManager?.textStorage, characterIndex < storage.length {
            let attributes = storage.attributes(at: characterIndex, effectiveRange: nil)
            font = attributes[.font] as? NSFont ?? font
            color = attributes[.foregroundColor] as? NSColor ?? color
        }
        if isNoteReference {
            font = NSFontManager.shared.convert(font, toSize: max(font.pointSize * 0.62, 6))
        }
        if object.kind == .dropdown || object.kind == .date {
            color = NSColor(srgbRed: 0.05, green: 0.36, blue: 0.45, alpha: 1)
        }
        return [.font: font, .foregroundColor: color]
    }

    private func metrics(characterIndex: Int, layoutManager: NSLayoutManager?, container: NSTextContainer?) -> (String, [NSAttributedString.Key: Any], NSSize, NSFont) {
        let text = text(characterIndex: characterIndex, layoutManager: layoutManager, container: container)
        let attributes = attributes(characterIndex: characterIndex, layoutManager: layoutManager)
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 12)
        var size = (text as NSString).size(withAttributes: attributes)
        size.width = max(ceil(size.width) + (object.kind == .dropdown ? 12 : 0), 2)
        return (text, attributes, size, font)
    }

    // MARK: Layout

    override func cellSize() -> NSSize {
        NSSize(width: 12, height: 14)
    }

    override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let (_, _, size, font) = metrics(characterIndex: charIndex, layoutManager: textContainer.layoutManager, container: textContainer)
        let height = ceil(font.ascender - font.descender)
        var y = floor(font.descender)
        if isNoteReference {
            // Superscript: lift the mark to the cap height of the surrounding text.
            y += height * 0.9
        }
        return NSRect(x: 0, y: y, width: size.width, height: height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
        let container = glyph < layoutManager.numberOfGlyphs ? layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil) : nil
        let (text, attributes, _, _) = metrics(characterIndex: charIndex, layoutManager: layoutManager, container: container)

        // Subtle shading marks live fields while editing (not when printing).
        if NSGraphicsContext.currentContextDrawingToScreen(), object.kind == .field || object.kind == .dropdown || object.kind == .date {
            NSColor(srgbRed: 0.84, green: 0.90, blue: 0.92, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2).fill()
        }
        (text as NSString).draw(at: NSPoint(x: cellFrame.minX, y: cellFrame.minY), withAttributes: attributes)
        if object.kind == .dropdown {
            let arrow = NSBezierPath()
            let x = cellFrame.maxX - 8, y = cellFrame.midY
            arrow.move(to: NSPoint(x: x, y: y - 1.5))
            arrow.line(to: NSPoint(x: x + 5, y: y - 1.5))
            arrow.line(to: NSPoint(x: x + 2.5, y: y + 1.5))
            arrow.close()
            NSColor.darkGray.setFill()
            arrow.fill()
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let text = object.form?.displayText ?? "·"
        (text as NSString).draw(at: cellFrame.origin, withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
    }

    /// Form controls react to clicks; other live text behaves like text.
    override func wantsToTrackMouse() -> Bool {
        object.kind == .checkbox || object.kind == .dropdown || object.kind == .date
    }
}

/// Computes field values.
enum FieldEvaluator {
    static func text(for field: FieldSpec, objectID: String, characterIndex: Int, layoutManager: WPLayoutManager?, container: NSTextContainer?) -> String {
        let values = layoutManager?.fieldValues ?? FieldValues()
        switch field.kind {
        case .page:
            let page = container.flatMap { layoutManager?.pageIndex(of: $0) } ?? 0
            return values.numberFormat.format(page + values.startingPageNumber)
        case .numPages:
            return String(layoutManager?.pageCountProvider() ?? 1)
        case .date:
            return field.fixedValue ?? DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
        case .time:
            return field.fixedValue ?? DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        case .title:
            return values.title.isEmpty ? values.filename : values.title
        case .author:
            return values.author
        case .subject:
            return values.subject
        case .filename:
            return values.filename
        case .sequence:
            return String(layoutManager?.sequenceNumbers[objectID] ?? 1)
        case .crossReference:
            return layoutManager?.crossReferenceText(field) ?? "[\(field.argument)]"
        case .mergeField:
            if let preview = layoutManager?.mergePreview?[field.argument] { return preview }
            return "«\(field.argument)»"
        case .formula:
            return layoutManager?.computedValues[objectID] ?? "0"
        }
    }
}
