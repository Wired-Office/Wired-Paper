import AppKit
import UniformTypeIdentifiers

// MARK: - Horizontal rule

/// A full-width divider line. Stored as an image attachment with a well-known
/// filename so it survives RTFD round-trips (and degrades to a line image in
/// other apps); on load the attachment gets a cell that spans the text column.
enum HorizontalRule {
    static let filename = "wp-horizontal-rule.png"

    static func isRule(_ attachment: NSTextAttachment) -> Bool {
        attachment.attachmentCell is HorizontalRuleCell
            || attachment.fileWrapper?.preferredFilename?.hasPrefix("wp-horizontal-rule") == true
            || attachment.fileWrapper?.filename?.hasPrefix("wp-horizontal-rule") == true
    }

    static func makeAttachment() -> NSTextAttachment {
        let wrapper = FileWrapper(regularFileWithContents: pngData)
        wrapper.preferredFilename = filename
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = HorizontalRuleCell()
        return attachment
    }

    private static let pngData: Data = {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 936, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        HorizontalRuleCell.lineColor.setFill()
        NSRect(x: 0, y: 2, width: 936, height: 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }()
}

final class HorizontalRuleCell: NSTextAttachmentCell {
    static let lineColor = NSColor(srgbRed: 0.70, green: 0.73, blue: 0.75, alpha: 1)
    private static let height: CGFloat = 16

    override init() {
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize {
        NSSize(width: 100, height: Self.height)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -4)
    }

    override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let width = max(lineFrag.width - position.x - textContainer.lineFragmentPadding * 2, 1)
        return NSRect(x: 0, y: -4, width: width, height: Self.height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        Self.lineColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.midY.rounded(.down), width: cellFrame.width, height: 1).fill()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }

    override func wantsToTrackMouse() -> Bool { false }
}

// MARK: - Image fitting

/// Image cell scaled to fit the page. Records the limits it was fitted to so
/// normalization is idempotent.
final class FittedImageCell: NSTextAttachmentCell {
    var fittedTo: CGSize = .zero
}

enum AttachmentNormalizer {
    /// Ensures images fit within `maxSize` (an image taller than a page would
    /// otherwise never fit in any page) and restores special cells.
    static func normalize(_ storage: NSTextStorage, in range: NSRange? = nil, maxSize: CGSize) {
        let range = range ?? NSRange(location: 0, length: storage.length)
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        storage.enumerateAttribute(.attachment, in: range) { value, run, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            if let object = DocumentObject.decode(storage.attribute(.wpObject, at: run.location, effectiveRange: nil)) {
                ObjectCells.install(for: attachment, object: object)
                if attachment.attachmentCell is LiveTextCell || attachment.attachmentCell is ObjectImageCell { return }
            }
            normalize(attachment, maxSize: maxSize)
        }
    }

    static func normalize(_ attachment: NSTextAttachment, maxSize: CGSize) {
        if HorizontalRule.isRule(attachment) {
            if !(attachment.attachmentCell is HorizontalRuleCell) {
                attachment.attachmentCell = HorizontalRuleCell()
            }
            return
        }
        if let fitted = attachment.attachmentCell as? FittedImageCell, fitted.fittedTo == maxSize { return }
        guard let image = sourceImage(for: attachment) else { return }

        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return }
        let scale = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
        let target = NSSize(width: floor(natural.width * scale), height: floor(natural.height * scale))

        guard scale < 1 || attachment.attachmentCell is FittedImageCell else { return }
        guard let scaled = image.copy() as? NSImage else { return }
        scaled.size = target
        let cell = FittedImageCell(imageCell: scaled)
        cell.fittedTo = maxSize
        attachment.attachmentCell = cell
    }

    private static func sourceImage(for attachment: NSTextAttachment) -> NSImage? {
        if let wrapper = attachment.fileWrapper, wrapper.isRegularFile {
            let name = wrapper.preferredFilename ?? wrapper.filename ?? ""
            let ext = (name as NSString).pathExtension
            if !ext.isEmpty, let type = UTType(filenameExtension: ext), !(type.conforms(to: .image) || type.conforms(to: .pdf)) {
                return nil
            }
            if let data = wrapper.regularFileContents, let image = NSImage(data: data) {
                return image
            }
        }
        return attachment.image
    }
}

// MARK: - Inserting images

enum ImageInserter {
    static func chooseAndInsert(into textView: NSTextView, window: NSWindow, maxSize: CGSize) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Insert"
        panel.message = "Choose one or more images to insert."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            do {
                try insert(urls: panel.urls, into: textView, maxSize: maxSize)
            } catch {
                window.presentError(error)
            }
        }
    }

    static func insert(urls: [URL], into textView: NSTextView, maxSize: CGSize) throws {
        let base = TextFormatter.baseAttributes(for: textView)
        let content = NSMutableAttributedString()
        for url in urls {
            let wrapper = try FileWrapper(url: url, options: .immediate)
            wrapper.preferredFilename = url.lastPathComponent
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            AttachmentNormalizer.normalize(attachment, maxSize: maxSize)
            let piece = NSMutableAttributedString(attachment: attachment)
            piece.addAttributes(base, range: NSRange(location: 0, length: piece.length))
            content.append(piece)
        }
        guard content.length > 0 else { return }
        TextFormatter.replaceSelection(in: textView, with: content, actionName: urls.count == 1 ? "Insert Image" : "Insert Images")
    }
}
