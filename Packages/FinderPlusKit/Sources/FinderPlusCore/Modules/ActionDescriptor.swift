import Foundation

/// Identifier of a menu group. Built-in groups are listed in ``MenuGroupCatalog``; modules may
/// introduce their own by using a new identifier.
public struct MenuGroupID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, Comparable {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: MenuGroupID, rhs: MenuGroupID) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let create: MenuGroupID = "create"
    public static let template: MenuGroupID = "template"
    public static let run: MenuGroupID = "run"
    public static let open: MenuGroupID = "open"
    public static let convert: MenuGroupID = "convert"
    public static let compress: MenuGroupID = "compress"
    public static let folder: MenuGroupID = "folder"
    public static let sidebar: MenuGroupID = "sidebar"
    public static let path: MenuGroupID = "path"
    public static let other: MenuGroupID = "other"
}

/// How the host executes an action once the user clicks it.
public enum ExecutionStyle: Hashable, Sendable {
    /// Quick, in-process work (copy a path, open an app). Only failures appear in the task center.
    case immediate
    /// Potentially long-running; tracked with progress in the task center and cancellable.
    case task
    /// Opens a host window supplied by the module (e.g. the folder icon picker) for the selection.
    case interactive(route: String)
}

extension ExecutionStyle: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "immediate" {
            self = .immediate
        } else if raw == "task" {
            self = .task
        } else if raw.hasPrefix("interactive:") {
            self = .interactive(route: String(raw.dropFirst("interactive:".count)))
        } else {
            self = .task
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .immediate: try container.encode("immediate")
        case .task: try container.encode("task")
        case .interactive(let route): try container.encode("interactive:\(route)")
        }
    }
}

/// Where an action may be triggered from.
public enum ActionPresentation: String, Codable, Sendable {
    /// Shown in the Finder context menu when its rule matches (and in host previews).
    case finderMenu
    /// Only invoked from the host UI, e.g. "Install runtime" on the dependency page.
    case hostOnly
}

/// One operation a module offers.
public struct ActionDescriptor: Codable, Hashable, Sendable, Identifiable {
    /// Unique within the module. Settings-generated actions encode their variant, e.g. `new.md`.
    public var id: String
    public var title: LocalizedText
    /// Compact title used when the user prefers short menu names ("VS Code" instead of "Open with VS Code").
    public var shortTitle: LocalizedText?
    /// SF Symbol name.
    public var icon: String?
    public var group: MenuGroupID
    /// Sort order inside the group; lower first.
    public var order: Int
    public var rule: MenuRule
    public var execution: ExecutionStyle
    public var presentation: ActionPresentation
    public var requiresConfirmation: Bool
    public var confirmationMessage: LocalizedText?
    /// Opaque values passed back to the module on invocation.
    public var parameters: [String: String]

    public init(
        id: String,
        title: LocalizedText,
        shortTitle: LocalizedText? = nil,
        icon: String? = nil,
        group: MenuGroupID = .other,
        order: Int = 100,
        rule: MenuRule = MenuRule(),
        execution: ExecutionStyle = .immediate,
        presentation: ActionPresentation = .finderMenu,
        requiresConfirmation: Bool = false,
        confirmationMessage: LocalizedText? = nil,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.icon = icon
        self.group = group
        self.order = order
        self.rule = rule
        self.execution = execution
        self.presentation = presentation
        self.requiresConfirmation = requiresConfirmation
        self.confirmationMessage = confirmationMessage
        self.parameters = parameters
    }

    enum CodingKeys: String, CodingKey {
        case id, title, shortTitle, icon, group, order, rule, execution, presentation
        case requiresConfirmation, confirmationMessage, parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(LocalizedText.self, forKey: .title)
        shortTitle = try container.decodeIfPresent(LocalizedText.self, forKey: .shortTitle)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        group = try container.decode(MenuGroupID.self, forKey: .group, default: .other)
        order = try container.decode(Int.self, forKey: .order, default: 100)
        rule = try container.decode(MenuRule.self, forKey: .rule, default: MenuRule())
        execution = try container.decode(ExecutionStyle.self, forKey: .execution, default: .task)
        presentation = try container.decode(ActionPresentation.self, forKey: .presentation, default: .finderMenu)
        requiresConfirmation = try container.decode(Bool.self, forKey: .requiresConfirmation, default: false)
        confirmationMessage = try container.decodeIfPresent(LocalizedText.self, forKey: .confirmationMessage)
        parameters = try container.decode([String: String].self, forKey: .parameters, default: [:])
    }

    /// Key used for menu overrides and requests: `<moduleID>/<actionID>`.
    public static func key(moduleID: String, actionID: String) -> String { "\(moduleID)/\(actionID)" }
}

/// Default title, order and presentation for the built-in groups.
public enum MenuGroupCatalog {
    public enum Presentation: String, Codable, Sendable {
        /// Items appear directly in the FinderPlus menu, separated from other groups.
        case inline
        /// Items appear in a submenu titled with the group name.
        case submenu
    }

    public struct Entry: Sendable {
        public var id: MenuGroupID
        public var title: LocalizedText
        public var order: Int
        public var presentation: Presentation
        public var icon: String?
    }

    public static let entries: [Entry] = [
        Entry(id: .create, title: LocalizedText(en: "New File", zhHans: "新建文件", ko: "새 파일"), order: 10, presentation: .submenu, icon: "doc.badge.plus"),
        Entry(id: .template, title: LocalizedText(en: "New from Template", zhHans: "从模板创建", ko: "템플릿에서 만들기"), order: 20, presentation: .submenu, icon: "doc.on.doc"),
        Entry(id: .run, title: LocalizedText(en: "Run", zhHans: "运行", ko: "실행"), order: 30, presentation: .inline, icon: "play"),
        Entry(id: .open, title: LocalizedText(en: "Open", zhHans: "打开", ko: "열기"), order: 40, presentation: .inline, icon: "arrow.up.forward.app"),
        Entry(id: .convert, title: LocalizedText(en: "Convert", zhHans: "转换", ko: "변환"), order: 50, presentation: .inline, icon: "arrow.triangle.2.circlepath"),
        Entry(id: .compress, title: LocalizedText(en: "Compress with Preset", zhHans: "按预设压缩", ko: "프리셋으로 압축"), order: 55, presentation: .submenu, icon: "photo.stack"),
        Entry(id: .folder, title: LocalizedText(en: "Folder", zhHans: "文件夹", ko: "폴더"), order: 60, presentation: .inline, icon: "folder"),
        Entry(id: .sidebar, title: LocalizedText(en: "Sidebar", zhHans: "侧边栏", ko: "사이드바"), order: 70, presentation: .inline, icon: "sidebar.left"),
        Entry(id: .path, title: LocalizedText(en: "Path", zhHans: "路径", ko: "경로"), order: 80, presentation: .inline, icon: "link"),
        Entry(id: .other, title: LocalizedText(en: "More", zhHans: "更多", ko: "더 보기"), order: 90, presentation: .inline, icon: "ellipsis.circle"),
    ]

    public static func entry(for id: MenuGroupID) -> Entry {
        entries.first { $0.id == id }
            ?? Entry(id: id, title: LocalizedText(stringLiteral: id.rawValue.capitalized), order: 85, presentation: .inline, icon: nil)
    }
}
