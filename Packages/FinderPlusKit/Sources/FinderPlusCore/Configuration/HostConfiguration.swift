import Foundation

/// Persistent state of a single module, owned by the host.
public struct ModuleState: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var settings: [String: SettingValue]
    /// Version that last ran; used to migrate settings when a module is updated.
    public var lastSeenVersion: String?

    public init(enabled: Bool, settings: [String: SettingValue] = [:], lastSeenVersion: String? = nil) {
        self.enabled = enabled
        self.settings = settings
        self.lastSeenVersion = lastSeenVersion
    }

    enum CodingKeys: String, CodingKey { case enabled, settings, lastSeenVersion }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled, default: true)
        settings = try container.decode([String: SettingValue].self, forKey: .settings, default: [:])
        lastSeenVersion = try container.decodeIfPresent(String.self, forKey: .lastSeenVersion)
    }
}

/// User customizations of a single menu item.
public struct MenuItemOverride: Codable, Hashable, Sendable {
    public var title: String?
    public var hidden: Bool
    public var order: Int?
    public var group: MenuGroupID?

    public init(title: String? = nil, hidden: Bool = false, order: Int? = nil, group: MenuGroupID? = nil) {
        self.title = title
        self.hidden = hidden
        self.order = order
        self.group = group
    }

    public var isEmpty: Bool { title == nil && !hidden && order == nil && group == nil }

    enum CodingKeys: String, CodingKey { case title, hidden, order, group }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        hidden = try container.decode(Bool.self, forKey: .hidden, default: false)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        group = try container.decodeIfPresent(MenuGroupID.self, forKey: .group)
    }
}

/// User customizations of a menu group.
public struct MenuGroupOverride: Codable, Hashable, Sendable {
    public var title: String?
    public var hidden: Bool
    public var order: Int?
    public var presentation: MenuGroupCatalog.Presentation?

    public init(title: String? = nil, hidden: Bool = false, order: Int? = nil, presentation: MenuGroupCatalog.Presentation? = nil) {
        self.title = title
        self.hidden = hidden
        self.order = order
        self.presentation = presentation
    }

    enum CodingKeys: String, CodingKey { case title, hidden, order, presentation }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        hidden = try container.decode(Bool.self, forKey: .hidden, default: false)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        presentation = try container.decodeIfPresent(MenuGroupCatalog.Presentation.self, forKey: .presentation)
    }
}

public struct MenuPreferences: Codable, Hashable, Sendable {
    public var groups: [String: MenuGroupOverride]
    public var items: [String: MenuItemOverride]

    public init(groups: [String: MenuGroupOverride] = [:], items: [String: MenuItemOverride] = [:]) {
        self.groups = groups
        self.items = items
    }

    enum CodingKeys: String, CodingKey { case groups, items }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([String: MenuGroupOverride].self, forKey: .groups, default: [:])
        items = try container.decode([String: MenuItemOverride].self, forKey: .items, default: [:])
    }
}

public struct GeneralPreferences: Codable, Hashable, Sendable {
    public var confirmDangerousActions: Bool
    public var notifyOnTaskCompletion: Bool
    public var keepRunningInBackground: Bool
    public var taskHistoryLimit: Int

    public init(confirmDangerousActions: Bool = true, notifyOnTaskCompletion: Bool = true,
                keepRunningInBackground: Bool = true, taskHistoryLimit: Int = 200) {
        self.confirmDangerousActions = confirmDangerousActions
        self.notifyOnTaskCompletion = notifyOnTaskCompletion
        self.keepRunningInBackground = keepRunningInBackground
        self.taskHistoryLimit = taskHistoryLimit
    }

    enum CodingKeys: String, CodingKey { case confirmDangerousActions, notifyOnTaskCompletion, keepRunningInBackground, taskHistoryLimit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmDangerousActions = try container.decode(Bool.self, forKey: .confirmDangerousActions, default: true)
        notifyOnTaskCompletion = try container.decode(Bool.self, forKey: .notifyOnTaskCompletion, default: true)
        keepRunningInBackground = try container.decode(Bool.self, forKey: .keepRunningInBackground, default: true)
        taskHistoryLimit = try container.decode(Int.self, forKey: .taskHistoryLimit, default: 200)
    }
}

/// Everything the user configured, stored as one JSON document so it can be exported and migrated.
public struct HostConfiguration: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var modules: [String: ModuleState]
    public var menu: MenuPreferences
    public var general: GeneralPreferences
    /// Script package id → content hash the user explicitly trusted.
    public var trustedPackages: [String: String]

    public init(
        schemaVersion: Int = HostConfiguration.currentSchemaVersion,
        modules: [String: ModuleState] = [:],
        menu: MenuPreferences = MenuPreferences(),
        general: GeneralPreferences = GeneralPreferences(),
        trustedPackages: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.modules = modules
        self.menu = menu
        self.general = general
        self.trustedPackages = trustedPackages
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, modules, menu, general, trustedPackages }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion, default: 1)
        modules = try container.decode([String: ModuleState].self, forKey: .modules, default: [:])
        menu = try container.decode(MenuPreferences.self, forKey: .menu, default: MenuPreferences())
        general = try container.decode(GeneralPreferences.self, forKey: .general, default: GeneralPreferences())
        trustedPackages = try container.decode([String: String].self, forKey: .trustedPackages, default: [:])
    }

    /// State for a module, creating it from the manifest defaults on first sight.
    public func state(for manifest: ModuleManifest) -> ModuleState {
        modules[manifest.id] ?? ModuleState(enabled: manifest.enabledByDefault && manifest.stability != .experimental)
    }

    public func settings(for manifest: ModuleManifest) -> ModuleSettings {
        ModuleSettings(values: state(for: manifest).settings, schema: manifest.settings)
    }

    public func isEnabled(_ manifest: ModuleManifest) -> Bool {
        state(for: manifest).enabled
    }
}
