import Foundation

/// File-system layout shared by the host app and the Finder extension.
///
/// * **Shared container** (App Group): the menu snapshot, the request inbox and the configuration.
///   This is the only location both the sandboxed extension and the host can access.
/// * **Host data** (`~/Library/Application Support/FinderPlus`): templates, icon packs, imported
///   script packages, managed runtimes, module data and backups. Only the host touches these.
public enum FinderPlusPaths {
    /// Info.plist key holding the App Group identifier (set from the `FP_APP_GROUP` build setting).
    public static let appGroupInfoKey = "FPAppGroupIdentifier"

    /// Override for tests and command-line tools.
    public static var overrideSharedRoot: URL?
    public static var overrideHostDataRoot: URL?

    public static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !value.isEmpty, !value.contains("$("), !value.hasPrefix(".") else { return nil }
        return value
    }

    public static var sharedRoot: URL {
        if let overrideSharedRoot { return overrideSharedRoot }
        if let identifier = appGroupIdentifier,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url.appendingPathComponent("FinderPlus", isDirectory: true)
        }
        // Builds without a Team ID (ad-hoc signed downloads, local development) have no App Group.
        // Both sides then use a fixed folder in the *real* home directory; the sandboxed extension
        // is granted access to exactly this folder by a temporary-exception entitlement
        // (FinderSyncExtension-AdHoc.entitlements).
        return realHomeDirectory
            .appendingPathComponent("Library/Application Support/FinderPlus/Shared", isDirectory: true)
    }

    /// The user's home folder, even inside the sandbox (where `NSHomeDirectory()` is the container).
    public static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static var hostDataRoot: URL {
        if let overrideHostDataRoot { return overrideHostDataRoot }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FinderPlus", isDirectory: true)
    }

    // MARK: Shared

    public static var configurationFile: URL { sharedRoot.appendingPathComponent("configuration.json") }
    public static var menuSnapshotFile: URL { sharedRoot.appendingPathComponent("menu-snapshot.json") }
    public static var inboxDirectory: URL { sharedRoot.appendingPathComponent("Inbox", isDirectory: true) }

    // MARK: Host only

    public static var templatesDirectory: URL { hostDataRoot.appendingPathComponent("Templates", isDirectory: true) }
    public static var iconPacksDirectory: URL { hostDataRoot.appendingPathComponent("IconPacks", isDirectory: true) }
    public static var packagesDirectory: URL { hostDataRoot.appendingPathComponent("Packages", isDirectory: true) }
    public static var runtimesDirectory: URL { hostDataRoot.appendingPathComponent("Runtimes", isDirectory: true) }
    public static var backupsDirectory: URL { hostDataRoot.appendingPathComponent("Backups", isDirectory: true) }
    public static var logsDirectory: URL { hostDataRoot.appendingPathComponent("Logs", isDirectory: true) }
    public static var taskHistoryFile: URL { hostDataRoot.appendingPathComponent("task-history.json") }

    /// Private storage for one module (history, caches, backups).
    public static func moduleDataDirectory(_ moduleID: String) -> URL {
        hostDataRoot.appendingPathComponent("ModuleData", isDirectory: true)
            .appendingPathComponent(moduleID, isDirectory: true)
    }

    @discardableResult
    public static func ensureDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
