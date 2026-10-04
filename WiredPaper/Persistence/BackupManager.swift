import Foundation

/// Keeps automatic backups (the previous version of a file before each save)
/// and named snapshots in ~/Library/Application Support/Wired Paper.
enum BackupManager {
    static let maxBackupsPerDocument = 10

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Wired Paper", isDirectory: true)
    }

    static func backupsDirectory(documentID: String) -> URL {
        supportDirectory.appendingPathComponent("Backups/\(documentID)", isDirectory: true)
    }

    static func snapshotsDirectory(documentID: String) -> URL {
        supportDirectory.appendingPathComponent("Snapshots/\(documentID)", isDirectory: true)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// Copies the file as it is on disk (the previous save) into the backup folder.
    static func backUp(_ url: URL, documentID: String) {
        guard AppSettings.shared.automaticBackups, FileManager.default.fileExists(atPath: url.path) else { return }
        let directory = backupsDirectory(documentID: documentID)
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let name = "\(stampFormatter.string(from: Date())) \(url.lastPathComponent)"
                try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(name))
                prune(directory)
            } catch {
                NSLog("Wired Paper backup failed: \(error.localizedDescription)")
            }
        }
    }

    private static func prune(_ directory: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let sorted = items.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in sorted.dropFirst(maxBackupsPerDocument) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    struct Entry: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
        var name: String
    }

    static func entries(in directory: URL) -> [Entry] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return Entry(url: url, date: date, name: url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.date > $1.date }
    }

    /// Saves a named snapshot of the document's current contents.
    static func saveSnapshot(of document: WiredPaperDocument, name: String) throws -> URL {
        let directory = snapshotsDirectory(documentID: document.metadata.documentID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let url = directory.appendingPathComponent("\(safe.isEmpty ? stampFormatter.string(from: Date()) : safe).paper")
        let wrapper = try document.fileWrapper(ofType: DocumentFormat.paper.typeIdentifier)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }
}
