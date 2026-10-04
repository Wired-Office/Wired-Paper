import AppKit

/// Appends a "Comments" section listing every thread, for printing and export.
enum CommentPrinter {
    static func appendingComments(to text: NSAttributedString, threads: [CommentThread]) -> NSAttributedString {
        guard !threads.isEmpty else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        let order = anchorOrder(in: text)
        let sorted = threads.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let pageBreak = NSMutableAttributedString(string: "\u{0C}", attributes: StyleCatalog.attributes(for: .normal))
        result.append(pageBreak)
        result.append(NSAttributedString(string: "Comments\n", attributes: StyleCatalog.attributes(for: .heading1)))
        for (index, thread) in sorted.enumerated() {
            let anchor = anchorText(for: thread.id, in: text)
            var heading = StyleCatalog.attributes(for: .heading3)
            heading[.foregroundColor] = RevisionMarkup.color(forAuthor: thread.author)
            result.append(NSAttributedString(string: "\(index + 1). \(thread.author) — \(dateFormatter.string(from: thread.date))\(thread.resolved ? " (resolved)" : "")\n", attributes: heading))
            if !anchor.isEmpty {
                result.append(NSAttributedString(string: "“\(anchor)”\n", attributes: StyleCatalog.attributes(for: .quote)))
            }
            result.append(NSAttributedString(string: thread.text + "\n", attributes: StyleCatalog.attributes(for: .normal)))
            for reply in thread.replies {
                var replyAttributes = StyleCatalog.attributes(for: .normal)
                let paragraph = (replyAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.headIndent = 24
                paragraph.firstLineHeadIndent = 24
                replyAttributes[.paragraphStyle] = paragraph
                result.append(NSAttributedString(string: "↳ \(reply.author): \(reply.text)\n", attributes: replyAttributes))
            }
        }
        return result
    }

    static func anchorOrder(in text: NSAttributedString) -> [String: Int] {
        var order: [String: Int] = [:]
        text.enumerateAttribute(.wpComment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let ids = value as? String else { return }
            for id in ids.split(separator: " ") where order[String(id)] == nil {
                order[String(id)] = range.location
            }
        }
        return order
    }

    static func anchorRange(for id: String, in text: NSAttributedString) -> NSRange? {
        var result: NSRange?
        text.enumerateAttribute(.wpComment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let ids = value as? String, ids.split(separator: " ").contains(Substring(id)) else { return }
            result = result.map { NSUnionRange($0, range) } ?? range
        }
        return result
    }

    static func anchorText(for id: String, in text: NSAttributedString) -> String {
        guard let range = anchorRange(for: id, in: text) else { return "" }
        let string = (text.string as NSString).substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
        return string.count > 160 ? String(string.prefix(160)) + "…" : string
    }
}
