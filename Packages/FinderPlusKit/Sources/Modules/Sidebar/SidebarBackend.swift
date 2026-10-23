import Foundation

/// One entry of Finder's sidebar "Favorites" section.
public struct SidebarItem: Hashable, Identifiable, Sendable {
    public var id: String { "\(index)-\(name)" }
    public var index: Int
    public var name: String
    public var url: URL?
}

public enum SidebarBackendError: LocalizedError {
    case unavailable
    case operationFailed(String)
    case notVerified

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The Finder sidebar list API is not available on this version of macOS."
        case .operationFailed(let detail):
            return detail
        case .notVerified:
            return "macOS accepted the request but the sidebar did not change. This macOS version may no longer allow it."
        }
    }
}

/// Access to Finder's Favorites through `LSSharedFileList`.
///
/// The API has been deprecated since macOS 10.11 and is undocumented in recent releases. To keep
/// the rest of FinderPlus independent of it, the functions are resolved at runtime with `dlsym`:
/// if Apple removes them, this module reports itself unavailable instead of failing to build or
/// crashing. Every write is verified by reading the list back.
final class SidebarBackend {
    private typealias CreateFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias SnapshotFn = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt32>?) -> OpaquePointer?
    private typealias CopyNameFn = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias CopyURLFn = @convention(c) (OpaquePointer?, UInt32, UnsafeMutablePointer<OpaquePointer?>?) -> OpaquePointer?
    private typealias InsertFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?, OpaquePointer?,
                                                 OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias RemoveFn = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    private typealias MoveFn = @convention(c) (OpaquePointer?, OpaquePointer?, OpaquePointer?) -> Int32

    private let fnCreate: CreateFn
    private let fnSnapshot: SnapshotFn
    private let fnCopyName: CopyNameFn
    private let fnCopyURL: CopyURLFn
    private let fnInsert: InsertFn
    private let fnRemove: RemoveFn
    private let fnMove: MoveFn
    private let favoritesListType: OpaquePointer
    private let lastItemMarker: OpaquePointer?
    private let beforeFirstMarker: OpaquePointer?

    /// `nil` when the running macOS no longer exports the API.
    init?() {
        let handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        func constant(_ name: String) -> OpaquePointer? {
            guard let pointer = dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return pointer.assumingMemoryBound(to: OpaquePointer?.self).pointee
        }
        guard let create = symbol("LSSharedFileListCreate", as: CreateFn.self),
              let snapshot = symbol("LSSharedFileListCopySnapshot", as: SnapshotFn.self),
              let copyName = symbol("LSSharedFileListItemCopyDisplayName", as: CopyNameFn.self),
              let copyURL = symbol("LSSharedFileListItemCopyResolvedURL", as: CopyURLFn.self),
              let insert = symbol("LSSharedFileListInsertItemURL", as: InsertFn.self),
              let remove = symbol("LSSharedFileListItemRemove", as: RemoveFn.self),
              let move = symbol("LSSharedFileListItemMove", as: MoveFn.self),
              let favorites = constant("kLSSharedFileListFavoriteItems") else { return nil }
        self.fnCreate = create
        self.fnSnapshot = snapshot
        self.fnCopyName = copyName
        self.fnCopyURL = copyURL
        self.fnInsert = insert
        self.fnRemove = remove
        self.fnMove = move
        favoritesListType = favorites
        lastItemMarker = constant("kLSSharedFileListItemLast")
        beforeFirstMarker = constant("kLSSharedFileListItemBeforeFirst")
    }

    // MARK: Reading

    func items() throws -> [SidebarItem] {
        try withList { list in
            rawItems(list).enumerated().map { index, item in
                SidebarItem(index: index, name: displayName(item), url: resolvedURL(item))
            }
        }
    }

    // MARK: Writing

    func add(_ url: URL) throws {
        let target = url.standardizedFileURL
        if try items().contains(where: { $0.url?.standardizedFileURL == target }) { return }
        try withList { list in
            let cfURL = url as CFURL
            let item = fnInsert(list, lastItemMarker, nil, nil, opaque(cfURL), nil, nil)
            if let item { release(item) }
        }
        guard try items().contains(where: { $0.url?.standardizedFileURL == target }) else {
            throw SidebarBackendError.notVerified
        }
    }

    func remove(_ url: URL) throws {
        let target = url.standardizedFileURL
        try withList { list in
            for item in rawItems(list) where resolvedURL(item)?.standardizedFileURL == target {
                let status = fnRemove(list, item)
                if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemRemove: \(status)") }
            }
        }
        if try items().contains(where: { $0.url?.standardizedFileURL == target }) {
            throw SidebarBackendError.notVerified
        }
    }

    /// Moves the item at `index` so that it ends up at `newIndex`.
    func move(from index: Int, to newIndex: Int) throws {
        try withList { list in
            let all = rawItems(list)
            guard all.indices.contains(index), all.indices.contains(newIndex), index != newIndex else { return }
            let item = all[index]
            var remaining = all
            remaining.remove(at: index)
            let after: OpaquePointer? = newIndex == 0 ? beforeFirstMarker : remaining[newIndex - 1]
            let status = fnMove(list, item, after)
            if status != 0 { throw SidebarBackendError.operationFailed("LSSharedFileListItemMove: \(status)") }
        }
    }

    // MARK: Helpers

    private func withList<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let list = fnCreate(nil, favoritesListType, nil) else { throw SidebarBackendError.unavailable }
        defer { release(list) }
        return try body(list)
    }

    private func rawItems(_ list: OpaquePointer) -> [OpaquePointer] {
        guard let arrayPointer = fnSnapshot(list, nil) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(UnsafeRawPointer(arrayPointer)).takeRetainedValue()
        return (0..<CFArrayGetCount(array)).compactMap { index in
            CFArrayGetValueAtIndex(array, index).map { OpaquePointer($0) }
        }
    }

    private func displayName(_ item: OpaquePointer) -> String {
        guard let pointer = fnCopyName(item) else { return "" }
        return Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue() as String
    }

    private func resolvedURL(_ item: OpaquePointer) -> URL? {
        // kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes
        guard let pointer = fnCopyURL(item, 0b11, nil) else { return nil }
        return Unmanaged<CFURL>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue() as URL
    }

    private func opaque(_ object: AnyObject) -> OpaquePointer {
        OpaquePointer(Unmanaged.passUnretained(object).toOpaque())
    }

    private func release(_ pointer: OpaquePointer) {
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(pointer)).release()
    }
}

/// Copies Finder's sidebar data files so any change can be rolled back.
struct SidebarBackupStore {
    let directory: URL

    static var sourceDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist", isDirectory: true)
    }

    static var sourceFiles: [URL] {
        ["sfl3", "sfl2"].map {
            sourceDirectory.appendingPathComponent("com.apple.LSSharedFileList.FavoriteItems.\($0)")
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    struct Backup: Identifiable, Hashable {
        var id: String { url.path }
        var url: URL
        var date: Date
    }

    func backups() -> [Backup] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        return folders.map { folder in
            let date = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Backup(url: folder, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    @discardableResult
    func createBackup(reason: String) throws -> Backup {
        let files = Self.sourceFiles
        guard !files.isEmpty else {
            throw SidebarBackendError.operationFailed("Finder sidebar data file not found in \(Self.sourceDirectory.path).")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = directory.appendingPathComponent("\(formatter.string(from: Date()))-\(reason)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        prune(keeping: 30)
        return Backup(url: folder, date: Date())
    }

    /// Restores files from `backup` and restarts the processes that cache them.
    func restore(_ backup: Backup) throws {
        try createBackup(reason: "before-restore")
        let files = (try? FileManager.default.contentsOfDirectory(at: backup.url, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("com.apple.LSSharedFileList.FavoriteItems.") {
            let destination = Self.sourceDirectory.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: try stagedCopy(file))
            } else {
                try FileManager.default.copyItem(at: file, to: destination)
            }
        }
        for process in ["sharedfilelistd", "Finder"] {
            let killall = Process()
            killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killall.arguments = [process]
            try? killall.run()
            killall.waitUntilExit()
        }
    }

    private func stagedCopy(_ file: URL) throws -> URL {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: staged)
        return staged
    }

    private func prune(keeping count: Int) {
        for backup in backups().dropFirst(count) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }
}
