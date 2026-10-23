import Foundation

/// Version of the module contract implemented by this host. A module whose `minimumHostAPI` is
/// higher than this value is shown as incompatible and never loaded.
public let finderPlusHostAPIVersion = 1

public enum ModuleKind: String, Codable, Sendable {
    /// Compiled into the app (Swift package target registered in `BuiltinModules`).
    case native
    /// Imported at runtime from a folder containing `finderplus-package.json`; runs declared scripts only.
    case scriptPackage
}

public enum ModuleStability: String, Codable, Sendable {
    case stable
    case beta
    /// Relies on undocumented system behavior. Isolated, disabled by default, always backed up.
    case experimental
}

public enum ModuleCategory: String, Codable, Sendable, CaseIterable {
    case create, path, open, convert, appearance, finder, utility

    public var title: LocalizedText {
        switch self {
        case .create: return LocalizedText(en: "Create", zhHans: "创建", ko: "생성")
        case .path: return LocalizedText(en: "Paths", zhHans: "路径", ko: "경로")
        case .open: return LocalizedText(en: "Open & Run", zhHans: "打开与运行", ko: "열기 및 실행")
        case .convert: return LocalizedText(en: "Convert", zhHans: "转换", ko: "변환")
        case .appearance: return LocalizedText(en: "Appearance", zhHans: "外观", ko: "모양")
        case .finder: return LocalizedText(en: "Finder", zhHans: "Finder", ko: "Finder")
        case .utility: return LocalizedText(en: "Utilities", zhHans: "工具", ko: "유틸리티")
        }
    }
}

/// Access a module needs. Shown on the module card and, for script packages, at import time.
public enum ModulePermission: String, Codable, Sendable, CaseIterable {
    case readSelection
    case writeFiles
    case runProcesses
    case appleEvents
    case accessibility
    case network
    case modifyFinder
    case privateSystemData

    public var title: LocalizedText {
        switch self {
        case .readSelection: return LocalizedText(en: "Read selected files", zhHans: "读取所选文件", ko: "선택한 파일 읽기")
        case .writeFiles: return LocalizedText(en: "Create or modify files", zhHans: "创建或修改文件", ko: "파일 생성 또는 수정")
        case .runProcesses: return LocalizedText(en: "Run external programs", zhHans: "运行外部程序", ko: "외부 프로그램 실행")
        case .appleEvents: return LocalizedText(en: "Control other apps (Automation)", zhHans: "控制其他应用（自动化）", ko: "다른 앱 제어(자동화)")
        case .accessibility: return LocalizedText(en: "Accessibility", zhHans: "辅助功能", ko: "손쉬운 사용")
        case .network: return LocalizedText(en: "Network access", zhHans: "网络访问", ko: "네트워크 접근")
        case .modifyFinder: return LocalizedText(en: "Modify Finder icons or sidebar", zhHans: "修改 Finder 图标或侧边栏", ko: "Finder 아이콘 또는 사이드바 수정")
        case .privateSystemData: return LocalizedText(en: "Edit undocumented system data", zhHans: "修改未公开的系统数据", ko: "비공개 시스템 데이터 수정")
        }
    }

    /// Permissions that require explicit trust before a script package may be enabled.
    public var isSensitive: Bool {
        switch self {
        case .readSelection: return false
        default: return true
        }
    }
}

/// External program, application or runtime a module relies on.
public struct DependencyDescriptor: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Command-line tool looked up on PATH and well-known locations (Homebrew, Conda, …).
        case executable
        /// macOS application looked up by bundle identifier.
        case application
        /// Checked by the module itself (`dependencyStatuses`).
        case custom
    }

    public var id: String
    public var kind: Kind
    public var displayName: LocalizedText
    public var executableNames: [String]
    public var bundleIdentifiers: [String]
    public var isRequired: Bool
    public var installHint: LocalizedText?
    public var helpURL: URL?

    public init(
        id: String,
        kind: Kind,
        displayName: LocalizedText,
        executableNames: [String] = [],
        bundleIdentifiers: [String] = [],
        isRequired: Bool = true,
        installHint: LocalizedText? = nil,
        helpURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.executableNames = executableNames
        self.bundleIdentifiers = bundleIdentifiers
        self.isRequired = isRequired
        self.installHint = installHint
        self.helpURL = helpURL
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, displayName, executableNames, bundleIdentifiers, isRequired, installHint, helpURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind, default: .executable)
        displayName = try container.decode(LocalizedText.self, forKey: .displayName, default: LocalizedText(stringLiteral: id))
        executableNames = try container.decode([String].self, forKey: .executableNames, default: [])
        bundleIdentifiers = try container.decode([String].self, forKey: .bundleIdentifiers, default: [])
        isRequired = try container.decode(Bool.self, forKey: .isRequired, default: true)
        installHint = try container.decodeIfPresent(LocalizedText.self, forKey: .installHint)
        helpURL = try container.decodeIfPresent(URL.self, forKey: .helpURL)
    }
}

/// Everything the host needs to know about a module without running any of its code.
public struct ModuleManifest: Codable, Hashable, Sendable, Identifiable {
    /// Globally unique reverse-DNS identifier, e.g. `io.github.finderplus.path-tools`.
    public var id: String
    public var name: LocalizedText
    public var summary: LocalizedText
    public var version: SemanticVersion
    public var author: String
    /// SF Symbol name.
    public var icon: String
    public var category: ModuleCategory
    public var kind: ModuleKind
    public var stability: ModuleStability
    public var minimumHostAPI: Int
    /// Free-form capability tags (`finder.menu`, `host.interactive-ui`, `settings.custom-view`, …).
    public var capabilities: [String]
    /// File types the module works with, for display and search (`md`, `public.image`, `folder`).
    public var supportedTypes: [String]
    /// Static actions. Modules with settings-dependent menus override `menuActions(settings:)`.
    public var actions: [ActionDescriptor]
    public var settings: SettingsSchema
    public var dependencies: [DependencyDescriptor]
    public var permissions: [ModulePermission]
    /// Whether the module starts enabled the first time it is seen.
    public var enabledByDefault: Bool

    public init(
        id: String,
        name: LocalizedText,
        summary: LocalizedText,
        version: SemanticVersion,
        author: String = "FinderPlus",
        icon: String,
        category: ModuleCategory,
        kind: ModuleKind = .native,
        stability: ModuleStability = .stable,
        minimumHostAPI: Int = 1,
        capabilities: [String] = ["finder.menu"],
        supportedTypes: [String] = [],
        actions: [ActionDescriptor] = [],
        settings: SettingsSchema = .empty,
        dependencies: [DependencyDescriptor] = [],
        permissions: [ModulePermission] = [.readSelection],
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.version = version
        self.author = author
        self.icon = icon
        self.category = category
        self.kind = kind
        self.stability = stability
        self.minimumHostAPI = minimumHostAPI
        self.capabilities = capabilities
        self.supportedTypes = supportedTypes
        self.actions = actions
        self.settings = settings
        self.dependencies = dependencies
        self.permissions = permissions
        self.enabledByDefault = enabledByDefault
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, version, author, icon, category, kind, stability, minimumHostAPI
        case capabilities, supportedTypes, actions, settings, dependencies, permissions, enabledByDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(LocalizedText.self, forKey: .name)
        summary = try container.decode(LocalizedText.self, forKey: .summary, default: "")
        version = try container.decode(SemanticVersion.self, forKey: .version, default: SemanticVersion(0, 1, 0))
        author = try container.decode(String.self, forKey: .author, default: "")
        icon = try container.decode(String.self, forKey: .icon, default: "puzzlepiece.extension")
        category = try container.decode(ModuleCategory.self, forKey: .category, default: .utility)
        kind = try container.decode(ModuleKind.self, forKey: .kind, default: .scriptPackage)
        stability = try container.decode(ModuleStability.self, forKey: .stability, default: .stable)
        minimumHostAPI = try container.decode(Int.self, forKey: .minimumHostAPI, default: 1)
        capabilities = try container.decode([String].self, forKey: .capabilities, default: ["finder.menu"])
        supportedTypes = try container.decode([String].self, forKey: .supportedTypes, default: [])
        actions = try container.decode([ActionDescriptor].self, forKey: .actions, default: [])
        settings = try container.decode(SettingsSchema.self, forKey: .settings, default: .empty)
        dependencies = try container.decode([DependencyDescriptor].self, forKey: .dependencies, default: [])
        permissions = try container.decode([ModulePermission].self, forKey: .permissions, default: [.readSelection])
        enabledByDefault = try container.decode(Bool.self, forKey: .enabledByDefault, default: false)
    }

    public var isCompatibleWithHost: Bool { minimumHostAPI <= finderPlusHostAPIVersion }
}
