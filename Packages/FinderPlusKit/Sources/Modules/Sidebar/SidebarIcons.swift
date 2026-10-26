import AppKit
import CryptoKit
import FinderPlusCore
import UniformTypeIdentifiers

/// A folder FinderPlus shows in Finder's sidebar with a custom SF Symbol.
public struct SidebarFavorite: Codable, Hashable, Identifiable, Sendable {
    public enum Provenance: String, Codable, Sendable {
        /// FinderPlus added the row; disabling removes it.
        case managed
        /// The row already existed; only its icon is ever touched, and disabling restores it.
        case adopted
    }

    public var id: UUID
    public var path: String
    public var symbol: String
    public var enabled: Bool
    /// Four-character icon code written to the row (`F` + 3 characters). Never changes.
    public var code: String
    public var provenance: Provenance

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    /// False when the folder was deleted, renamed or moved since it was added.
    var folderExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Persists favorites in the module's data folder.
struct SidebarFavoriteStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("favorites.json") }

    func load() -> [SidebarFavorite] {
        (try? FinderPlusJSON.read([SidebarFavorite].self, from: fileURL)) ?? []
    }

    func save(_ favorites: [SidebarFavorite]) throws {
        try FinderPlusJSON.write(favorites, to: fileURL)
    }
}

/// Mints the four-character icon codes. Codes are case-sensitive; `F` + uppercase keeps them
/// apart from Apple's (lowercase) codes and from SidebarFavorites' `S…` codes.
enum SidebarIconCode {
    static let prefix: Character = "F"
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func isOurs(_ code: String?) -> Bool {
        guard let code, code.count == 4, code.first == prefix else { return false }
        return code.dropFirst().allSatisfy { alphabet.contains($0) }
    }

    static func allocate(avoiding used: Set<String>) -> String {
        for index in 0..<(32 * 32 * 32) {
            let code = String([prefix, alphabet[(index >> 10) & 31], alphabet[(index >> 5) & 31], alphabet[index & 31]])
            if used.contains(code) { continue }
            // Skip codes some other installed app already declares.
            if let type = UTType(tag: code, tagClass: .init(rawValue: "com.apple.ostype"), conformingTo: nil),
               type.isDeclared, !type.identifier.hasPrefix(SidebarIconHelper.typePrefix) {
                continue
            }
            return code
        }
        return "F000"
    }

    /// Codes set by the SidebarFavorites app (`S` + 3 characters).
    static func isSidebarFavoritesCode(_ code: String?) -> Bool {
        guard let code, code.count == 4, code.first == "S" else { return false }
        return code.dropFirst().allSatisfy { $0.isUppercase || $0.isNumber }
    }
}

/// Builds and registers the never-launched bundle that maps each icon code to an SF Symbol.
///
/// Finder resolves a row's icon code through Launch Services: the code is the `com.apple.ostype`
/// tag of a declared type whose nested `UTTypeIcons` names the symbol. The bundle contains no
/// program — its executable is a two-line no-op script so Launch Services accepts it.
struct SidebarIconHelper {
    static let bundleIdentifier = "io.github.finderplus.sidebar-icons"
    static let typePrefix = "io.github.finderplus.sidebar-icon."
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    let bundleURL: URL

    init(directory: URL) {
        bundleURL = directory.appendingPathComponent("FinderPlus Sidebar Icons.app", isDirectory: true)
    }

    /// Writes and registers the bundle when the declarations changed. Returns true if it did.
    @discardableResult
    func update(for favorites: [SidebarFavorite]) throws -> Bool {
        let declarations = favorites.filter(\.enabled).sorted { $0.code < $1.code }
        let digest = SHA256.hash(data: Data(declarations.map { "\($0.code)=\($0.symbol)" }.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contents.appendingPathComponent("Info.plist")
        let existing = NSDictionary(contentsOf: plistURL)
        if existing?["FPDeclarationDigest"] as? String == digest { return false }

        let generation = ((existing?["CFBundleVersion"] as? String).flatMap(Int.init) ?? 0) + 1
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/FinderPlusSidebarIcons")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let types: [[String: Any]] = declarations.map { favorite in
            [
                "UTTypeIdentifier": Self.typePrefix + favorite.code.lowercased(),
                "UTTypeDescription": "\(favorite.name) sidebar icon",
                "UTTypeConformsTo": ["public.folder"],
                "UTTypeTagSpecification": ["com.apple.ostype": [favorite.code]],
                // The nested dictionary is required; top-level icon keys are ignored for sidebar rows.
                "UTTypeIcons": ["UTTypeSymbolName": favorite.symbol],
            ]
        }
        let plist: [String: Any] = [
            "CFBundleIdentifier": Self.bundleIdentifier,
            "CFBundleName": "FinderPlus Sidebar Icons",
            "CFBundleExecutable": "FinderPlusSidebarIcons",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            // Bumped on every rebuild so Launch Services never serves a cached record.
            "CFBundleVersion": String(generation),
            "CFBundleGetInfoString": "Icons for Finder sidebar folders set with FinderPlus. Never launched.",
            "LSUIElement": true,
            "LSBackgroundOnly": true,
            "FPDeclarationDigest": digest,
            "UTExportedTypeDeclarations": types,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        // Signing is best effort: an unsigned helper registers and renders icons too.
        _ = Self.run("/usr/bin/codesign", ["--force", "--sign", "-", bundleURL.path])
        // Registration is the step that must succeed.
        let (status, output) = Self.run(Self.lsregister, ["-f", "-R", "-trusted", bundleURL.path])
        guard status == 0 else {
            throw ModuleError.failed("lsregister failed (\(status)): \(output)")
        }
        return true
    }

    func unregister() {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return }
        _ = Self.run(Self.lsregister, ["-u", bundleURL.path])
        try? FileManager.default.removeItem(at: bundleURL)
    }

    static func run(_ tool: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}

/// Keeps Finder's sidebar in line with the favorites: adds/removes rows FinderPlus manages and
/// sets or clears icon codes. Never renames, moves or deletes a row the user created.
final class SidebarIconCoordinator {
    let store: SidebarFavoriteStore
    let helper: SidebarIconHelper
    let backups: SidebarBackupStore

    init(dataDirectory: URL) {
        store = SidebarFavoriteStore(directory: dataDirectory)
        helper = SidebarIconHelper(directory: dataDirectory)
        backups = SidebarBackupStore(directory: dataDirectory.appendingPathComponent("Backups", isDirectory: true))
    }

    struct Result {
        var favorites: [SidebarFavorite]
        var rows: [SidebarRow]
        /// A row already on screen changed icon, or an icon's symbol changed: Finder only redraws after a restart.
        var needsFinderRestart: Bool
        /// Favorites that could not be applied, with the reason. One failing folder never blocks the others.
        var problems: [UUID: String] = [:]
    }

    /// Adds or updates a favorite and applies it.
    func upsert(path: String, symbol: String, enabled: Bool = true) throws -> Result {
        var favorites = store.load()
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let id: UUID
        if let index = favorites.firstIndex(where: { SidebarBackend.samePath($0.path, standardized) }) {
            favorites[index].symbol = symbol
            favorites[index].enabled = enabled
            id = favorites[index].id
        } else {
            let used = Set(favorites.map(\.code))
            // A folder the user already had in the sidebar stays theirs: FinderPlus will only ever
            // change its icon, never delete the row.
            var alreadyInSidebar = false
            if let backend = SidebarBackend(), let rows = try? backend.rows() {
                alreadyInSidebar = rows.contains { SidebarBackend.samePath($0.path, standardized) }
            }
            id = UUID()
            favorites.append(SidebarFavorite(id: id, path: standardized, symbol: symbol, enabled: enabled,
                                             code: SidebarIconCode.allocate(avoiding: used),
                                             provenance: alreadyInSidebar ? .adopted : .managed))
        }
        let result = try apply(favorites, inserting: [id])
        // Saved either way, so the list shows it; the editor reports why it isn't in the sidebar.
        if let problem = result.problems[id] { throw SidebarBackendError.operationFailed(problem) }
        return result
    }

    /// Turning a favorite on (re)adds its row if it is missing from the sidebar.
    func setEnabled(_ id: UUID, _ enabled: Bool) throws -> Result {
        var favorites = store.load()
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return try apply(favorites) }
        favorites[index].enabled = enabled
        return try apply(favorites, inserting: enabled ? [id] : [])
    }

    /// Adds the row again after it was removed in Finder.
    func readd(_ id: UUID) throws -> Result {
        try setEnabled(id, true)
    }

    /// Deletes a favorite from FinderPlus. Its row is removed if FinderPlus added it, otherwise its
    /// icon is restored. The favorite is always deleted, even if its folder or row is gone.
    func delete(_ id: UUID) throws -> Result {
        var favorites = store.load()
        guard let favorite = favorites.first(where: { $0.id == id }) else { return try apply(favorites) }
        favorites.removeAll { $0.id == id }
        var needsRestart = false
        var cleanupError: Error?
        var rows: [SidebarRow] = []
        if let backend = SidebarBackend(), let before = try? backend.rows() {
            rows = before
            if let row = before.first(where: { SidebarBackend.samePath($0.path, favorite.path) }), row.iconCode == favorite.code {
                try? backups.createBackup(reason: "before-remove")
                do {
                    if favorite.provenance == .managed {
                        try backend.remove(path: row.path ?? favorite.path)
                    } else {
                        try backend.clearIconCode(forPath: row.path ?? favorite.path)
                        needsRestart = true
                    }
                } catch {
                    cleanupError = error
                }
            }
            rows = (try? backend.rows()) ?? before
        }
        try store.save(favorites)
        try? helper.update(for: favorites)
        if let cleanupError { throw cleanupError }
        return Result(favorites: favorites, rows: rows, needsFinderRestart: needsRestart)
    }

    /// Re-applies icons to rows that are in the sidebar. Rows the user removed in Finder are not
    /// added back behind their back; the list shows them as "not in sidebar" instead.
    func refresh() throws -> Result {
        try apply(store.load())
    }

    /// - Parameter inserting: favorites whose row may be added if it is missing.
    private func apply(_ input: [SidebarFavorite], inserting: Set<UUID> = []) throws -> Result {
        guard let backend = SidebarBackend() else { throw SidebarBackendError.unavailable }
        var favorites = input
        let previouslyDeclared = Dictionary(store.load().filter(\.enabled).map { ($0.code, $0.symbol) }, uniquingKeysWith: { a, _ in a })
        let before = try backend.rows()
        if before.contains(where: { row in favorites.contains { SidebarBackend.samePath(row.path, $0.path) } }) {
            try? backups.createBackup(reason: "before-icons")
        }

        // Register declarations first, so a newly set code resolves immediately.
        try helper.update(for: favorites)

        var needsRestart = false
        var problems: [UUID: String] = [:]
        for index in favorites.indices {
            let favorite = favorites[index]
            let row = before.first { SidebarBackend.samePath($0.path, favorite.path) }
            do {
                if favorite.enabled {
                    if let row {
                        if row.iconCode != favorite.code {
                            try backend.setIconCode(favorite.code, forPath: row.path ?? favorite.path)
                            needsRestart = true
                        } else if previouslyDeclared[favorite.code] != favorite.symbol {
                            needsRestart = true // same code, new symbol: Finder caches the old one
                        }
                    } else if inserting.contains(favorite.id) {
                        guard favorite.folderExists else { throw SidebarBackendError.folderMissing }
                        // A row inserted with its code already set draws correctly straight away.
                        let added = try backend.insert(URL(fileURLWithPath: favorite.path, isDirectory: true),
                                                       name: favorite.name, iconCode: favorite.code)
                        if !added { favorites[index].provenance = .adopted }
                    }
                } else if let row, row.iconCode == favorite.code {
                    if favorite.provenance == .managed {
                        try backend.remove(path: row.path ?? favorite.path)
                    } else {
                        try backend.clearIconCode(forPath: row.path ?? favorite.path)
                        needsRestart = true
                    }
                }
            } catch {
                problems[favorite.id] = error.localizedDescription
            }
        }
        try store.save(favorites)
        return Result(favorites: favorites, rows: (try? backend.rows()) ?? before, needsFinderRestart: needsRestart,
                      problems: problems)
    }

    /// Takes an existing sidebar row under FinderPlus' management without moving or renaming it.
    func adopt(_ row: SidebarRow, symbol: String) throws -> Result {
        guard let path = row.path else { throw SidebarBackendError.rowNotFound }
        var favorites = store.load()
        if let index = favorites.firstIndex(where: { SidebarBackend.samePath($0.path, path) }) {
            favorites[index].symbol = symbol
            favorites[index].enabled = true
        } else {
            favorites.append(SidebarFavorite(id: UUID(), path: path, symbol: symbol, enabled: true,
                                             code: SidebarIconCode.allocate(avoiding: Set(favorites.map(\.code))),
                                             provenance: .adopted))
        }
        return try apply(favorites)
    }

    static func restartFinder() {
        _ = SidebarIconHelper.run("/usr/bin/killall", ["Finder"])
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
