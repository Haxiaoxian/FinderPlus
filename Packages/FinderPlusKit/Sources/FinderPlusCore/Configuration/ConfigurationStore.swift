import Foundation

/// Loads, saves, migrates, imports and exports ``HostConfiguration``.
///
/// The host is the only writer. Reads and writes are serialized with a lock so background tasks
/// can read settings while the UI edits them.
public final class ConfigurationStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var cached: HostConfiguration?

    public init(fileURL: URL = FinderPlusPaths.configurationFile) {
        self.fileURL = fileURL
    }

    public func load() -> HostConfiguration {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let configuration = readFromDisk()
        cached = configuration
        return configuration
    }

    public func save(_ configuration: HostConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }
        try FinderPlusJSON.write(configuration, to: fileURL)
        cached = configuration
    }

    @discardableResult
    public func update(_ change: (inout HostConfiguration) -> Void) throws -> HostConfiguration {
        var configuration = load()
        change(&configuration)
        try save(configuration)
        return configuration
    }

    /// Writes the configuration to a user-chosen location for migration to another Mac.
    public func export(to url: URL) throws {
        let export = ConfigurationExport(exportedAt: Date(), configuration: load())
        try FinderPlusJSON.write(export, to: url)
    }

    /// Replaces the configuration with an exported one after validating and migrating it.
    /// The previous configuration is kept as a backup next to the configuration file.
    @discardableResult
    public func importConfiguration(from url: URL) throws -> HostConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = FinderPlusJSON.decoder()
        let imported: HostConfiguration
        if let export = try? decoder.decode(ConfigurationExport.self, from: data) {
            imported = export.configuration
        } else {
            imported = try decoder.decode(HostConfiguration.self, from: data)
        }
        try backupCurrent(reason: "before-import")
        var migrated = imported
        Self.migrate(&migrated)
        try save(migrated)
        return migrated
    }

    public func backupCurrent(reason: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = FinderPlusPaths.backupsDirectory.appendingPathComponent("configuration-\(reason)-\(stamp).json")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fileURL, to: backup)
    }

    private func readFromDisk() -> HostConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return HostConfiguration() }
        do {
            var configuration = try FinderPlusJSON.read(HostConfiguration.self, from: fileURL)
            if configuration.schemaVersion < HostConfiguration.currentSchemaVersion {
                try? backupCurrent(reason: "migration-v\(configuration.schemaVersion)")
                Self.migrate(&configuration)
            }
            return configuration
        } catch {
            // Never lose the user's file: keep the unreadable copy and start from defaults.
            try? backupCurrent(reason: "unreadable")
            return HostConfiguration()
        }
    }

    /// Upgrades older configuration documents in place. Add a step for every schema bump.
    static func migrate(_ configuration: inout HostConfiguration) {
        // v1 is the first published schema; future migrations go here, e.g.
        // if configuration.schemaVersion < 2 { …; configuration.schemaVersion = 2 }
        configuration.schemaVersion = HostConfiguration.currentSchemaVersion
    }
}

public struct ConfigurationExport: Codable, Sendable {
    public var format = "finderplus-configuration"
    public var exportedAt: Date
    public var configuration: HostConfiguration
}
