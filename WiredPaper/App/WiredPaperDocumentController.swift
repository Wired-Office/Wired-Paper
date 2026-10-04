import AppKit

/// Adds template-based document creation to the standard document controller.
final class WiredPaperDocumentController: NSDocumentController {
    func newDocument(from template: DocumentTemplate) {
        do {
            let type = defaultType ?? DocumentFormat.paper.typeIdentifier
            guard let document = try makeUntitledDocument(ofType: type) as? WiredPaperDocument else { return }
            document.load(template: template)
            addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        } catch {
            presentError(error)
        }
    }

    /// Opens a new untitled document holding generated content.
    @discardableResult
    func newDocument(text: NSAttributedString, pageSetup: PageSetup, metadata: DocumentMetadata = DocumentMetadata()) -> WiredPaperDocument? {
        do {
            let type = defaultType ?? DocumentFormat.paper.typeIdentifier
            guard let document = try makeUntitledDocument(ofType: type) as? WiredPaperDocument else { return nil }
            document.loadGenerated(text, pageSetup: pageSetup, metadata: metadata)
            addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            return document
        } catch {
            presentError(error)
            return nil
        }
    }
}

/// Populates File ▸ Open Recent from the document controller's recent list.
final class RecentDocumentsMenuController: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs

        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for url in urls {
            let item = NSMenuItem(
                title: FileManager.default.displayName(atPath: url.path),
                action: #selector(openRecentDocument(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        ))
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
