import AppKit
import FinderPlusCore

/// Every icon change FinderPlus made, with a PNG backup of any custom icon it replaced.
public struct FolderIconHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var folderPath: String
    public var appliedAt: Date
    public var spec: FolderIconSpec?
    /// Backup of the previous custom icon, if the folder had one.
    public var previousIconFile: String?
    public var restored: Bool
}

public struct FolderIconHistory {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("history.json") }
    var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    public func load() -> [FolderIconHistoryEntry] {
        (try? FinderPlusJSON.read([FolderIconHistoryEntry].self, from: fileURL)) ?? []
    }

    public func save(_ entries: [FolderIconHistoryEntry]) throws {
        try FinderPlusJSON.write(Array(entries.prefix(500)), to: fileURL)
    }

    /// Applies `spec` to `folder`, backing up an existing custom icon first.
    @MainActor
    public func apply(_ spec: FolderIconSpec?, image: NSImage?, to folder: URL) throws {
        var backup: String?
        if FolderIconRenderer.hasCustomIcon(folder),
           let data = FolderIconRenderer.pngData(NSWorkspace.shared.icon(forFile: folder.path)) {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let url = backupsDirectory.appendingPathComponent("\(UUID().uuidString).png")
            try data.write(to: url)
            backup = url.path
        }
        guard FolderIconRenderer.apply(image, to: folder) else {
            throw ModuleError.failed(LocalizedText(en: "Could not change the icon of “\(folder.lastPathComponent)”.",
                                                   zhHans: "无法修改“\(folder.lastPathComponent)”的图标。",
                                                   ko: "“\(folder.lastPathComponent)”의 아이콘을 변경할 수 없습니다.").localized)
        }
        var entries = load()
        entries.insert(FolderIconHistoryEntry(id: UUID(), folderPath: folder.path, appliedAt: Date(), spec: spec,
                                              previousIconFile: backup, restored: false), at: 0)
        try save(entries)
    }

    /// Puts back the icon the folder had before `entry` (custom backup or the default icon).
    @MainActor
    public func restore(_ entry: FolderIconHistoryEntry) throws {
        let folder = URL(fileURLWithPath: entry.folderPath)
        let previous = entry.previousIconFile.flatMap { NSImage(contentsOf: URL(fileURLWithPath: $0)) }
        guard FolderIconRenderer.apply(previous, to: folder) else {
            throw ModuleError.failed("Could not restore \(folder.lastPathComponent)")
        }
        var entries = load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].restored = true
        }
        try save(entries)
    }
}
