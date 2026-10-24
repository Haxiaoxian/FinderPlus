import FinderPlusCore
import Foundation

/// Block 02 — copy paths of selected items (or of the current folder).
public final class PathToolsModule: FinderPlusModule {
    public static let id = "io.github.finderplus.path-tools"

    enum Key {
        static let separator = "separator"
        static let customSeparator = "customSeparator"
        static let quoting = "quoting"
        static let wrap = "wrap"
        static let customTitle = "customTitle"
        static let extraActions = "extraActions"
        static let trailingSlashForFolders = "trailingSlashForFolders"
    }

    public init() {}

    public let manifest = ModuleManifest(
        id: PathToolsModule.id,
        name: LocalizedText(en: "Path Tools", zhHans: "路径操作", ko: "경로 도구"),
        summary: LocalizedText(en: "Copy absolute paths of files and folders, with batch formatting and shell escaping.",
                               zhHans: "复制文件和文件夹的绝对路径，支持批量格式与 Shell 转义。",
                               ko: "파일과 폴더의 절대 경로를 복사합니다. 일괄 형식과 셸 이스케이프를 지원합니다."),
        version: "1.0.0",
        icon: "link",
        category: .path,
        supportedTypes: ["*"],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "format", title: LocalizedText(en: "Format", zhHans: "格式", ko: "형식"), fields: [
                .choice(Key.separator, LocalizedText(en: "Separator for multiple items", zhHans: "多个项目的分隔方式", ko: "여러 항목 구분자"),
                        options: [
                            SettingOption("newline", LocalizedText(en: "New line", zhHans: "换行", ko: "줄바꿈")),
                            SettingOption("space", LocalizedText(en: "Space", zhHans: "空格", ko: "공백")),
                            SettingOption("comma", LocalizedText(en: "Comma", zhHans: "逗号", ko: "쉼표")),
                            SettingOption("tab", LocalizedText(en: "Tab", zhHans: "制表符", ko: "탭")),
                            SettingOption("custom", LocalizedText(en: "Custom", zhHans: "自定义", ko: "사용자 지정")),
                        ], default: "newline"),
                .text(Key.customSeparator, LocalizedText(en: "Custom separator", zhHans: "自定义分隔符", ko: "사용자 지정 구분자"),
                      default: "; ", visibleWhen: SettingCondition(key: Key.separator, equals: ["custom"])),
                .choice(Key.quoting, LocalizedText(en: "Shell escaping", zhHans: "Shell 转义", ko: "셸 이스케이프"),
                        options: [
                            SettingOption("none", LocalizedText(en: "None", zhHans: "不转义", ko: "없음")),
                            SettingOption("single", LocalizedText(en: "Single quotes  '/a b'", zhHans: "单引号  '/a b'", ko: "작은따옴표  '/a b'")),
                            SettingOption("double", LocalizedText(en: "Double quotes  \"/a b\"", zhHans: "双引号  \"/a b\"", ko: "큰따옴표  \"/a b\"")),
                            SettingOption("backslash", LocalizedText(en: "Backslashes  /a\\ b", zhHans: "反斜杠  /a\\ b", ko: "백슬래시  /a\\ b")),
                        ], default: "none"),
                .choice(Key.wrap, LocalizedText(en: "Wrap each item in", zhHans: "包裹符号", ko: "각 항목 감싸기"),
                        options: [
                            SettingOption("none", LocalizedText(en: "Nothing", zhHans: "不包裹", ko: "감싸지 않음")),
                            SettingOption("single", LocalizedText(en: "Single quotes  'name'", zhHans: "单引号  'name'", ko: "작은따옴표  'name'")),
                            SettingOption("double", LocalizedText(en: "Double quotes  \"name\"", zhHans: "双引号  \"name\"", ko: "큰따옴표  \"name\"")),
                            SettingOption("curlySingle", LocalizedText(en: "Curly single quotes  ‘name’", zhHans: "中文单引号  ‘name’", ko: "둥근 작은따옴표  ‘name’")),
                            SettingOption("curlyDouble", LocalizedText(en: "Curly double quotes  “name”", zhHans: "中文双引号  “name”", ko: "둥근 큰따옴표  “name”")),
                        ], default: "none",
                        help: LocalizedText(en: "Applies to every copy item (path, name, parent folder, file URL). The text inside is left as is; use Shell escaping instead when pasting into Terminal.",
                                            zhHans: "作用于所有复制项（路径、名称、所在文件夹、文件 URL），只在外侧加引号、不改动内容；若要粘贴到终端，请改用上方的“Shell 转义”。",
                                            ko: "모든 복사 항목(경로, 이름, 상위 폴더, 파일 URL)에 적용됩니다. 내용은 그대로 두며, 터미널용이면 셸 이스케이프를 사용하세요."),
                        visibleWhen: SettingCondition(key: Key.quoting, equals: ["none"])),
                .toggle(Key.trailingSlashForFolders, LocalizedText(en: "Add trailing slash to folders", zhHans: "文件夹路径末尾加 /", ko: "폴더 경로 끝에 / 추가"),
                        default: false),
            ]),
            SettingsSection(id: "menu", title: LocalizedText(en: "Menu", zhHans: "菜单", ko: "메뉴"), fields: [
                .text(Key.customTitle, LocalizedText(en: "Menu title", zhHans: "菜单名称", ko: "메뉴 이름"),
                      placeholder: LocalizedText(en: "Copy Absolute Path", zhHans: "复制绝对路径", ko: "절대 경로 복사")),
                .multiChoice(Key.extraActions, LocalizedText(en: "Additional items", zhHans: "附加菜单项", ko: "추가 항목"),
                             options: [
                                SettingOption("name", LocalizedText(en: "Copy name", zhHans: "复制名称", ko: "이름 복사")),
                                SettingOption("parent", LocalizedText(en: "Copy parent folder path", zhHans: "复制所在文件夹路径", ko: "상위 폴더 경로 복사")),
                                SettingOption("fileURL", LocalizedText(en: "Copy as file:// URL", zhHans: "复制为 file:// URL", ko: "file:// URL로 복사")),
                             ], default: []),
            ]),
        ]),
        permissions: [.readSelection]
    )

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        var title = LocalizedText(en: "Copy Absolute Path", zhHans: "复制绝对路径", ko: "절대 경로 복사")
        if let custom = settings.nonEmptyString(Key.customTitle) { title = LocalizedText(stringLiteral: custom) }
        var actions = [
            ActionDescriptor(id: "copyPath", title: title, shortTitle: LocalizedText(en: "Copy Path", zhHans: "复制路径", ko: "경로 복사"),
                             icon: "doc.on.clipboard", group: .path, order: 10, rule: .anything),
        ]
        let extras = Set(settings.strings(Key.extraActions))
        if extras.contains("name") {
            actions.append(ActionDescriptor(id: "copyName", title: LocalizedText(en: "Copy Name", zhHans: "复制名称", ko: "이름 복사"),
                                            icon: "textformat", group: .path, order: 20, rule: .anyItems))
        }
        if extras.contains("parent") {
            actions.append(ActionDescriptor(id: "copyParent",
                                            title: LocalizedText(en: "Copy Parent Folder Path", zhHans: "复制所在文件夹路径", ko: "상위 폴더 경로 복사"),
                                            icon: "folder", group: .path, order: 30, rule: .anyItems))
        }
        if extras.contains("fileURL") {
            actions.append(ActionDescriptor(id: "copyURL", title: LocalizedText(en: "Copy as File URL", zhHans: "复制为文件 URL", ko: "파일 URL로 복사"),
                                            icon: "link", group: .path, order: 40, rule: .anything))
        }
        return actions
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let selection = invocation.selection
        let text: String
        switch invocation.actionID {
        case "copyPath":
            text = PathFormatter.format(selection: selection, settings: invocation.settings)
        case "copyName":
            text = PathFormatter.join(selection.targetURLs.map { PathFormatter.decorate($0.lastPathComponent, settings: invocation.settings) },
                                      settings: invocation.settings)
        case "copyParent":
            let parents = selection.targetURLs.map { $0.deletingLastPathComponent().path }
            var unique: [String] = []
            for parent in parents where !unique.contains(parent) { unique.append(parent) }
            text = PathFormatter.join(unique.map { PathFormatter.decorate($0, settings: invocation.settings) }, settings: invocation.settings)
        case "copyURL":
            text = PathFormatter.join(selection.targetURLs.map { PathFormatter.decorate($0.absoluteString, settings: invocation.settings) },
                                      settings: invocation.settings)
        default:
            throw ModuleError.unknownAction(invocation.actionID)
        }
        guard !text.isEmpty else {
            throw ModuleError.invalidSelection(LocalizedText(en: "Nothing selected.", zhHans: "没有选中任何项目。", ko: "선택한 항목이 없습니다.").localized)
        }
        await context.system.copyToPasteboard(text)
        let count = selection.targetURLs.count
        return .message(LocalizedText(en: "Copied \(count) path(s).", zhHans: "已复制 \(count) 个路径。", ko: "경로 \(count)개를 복사했습니다.").localized)
    }
}

/// Pure formatting, unit-tested.
public enum PathFormatter {
    public static func format(selection: FinderSelection, settings: ModuleSettings) -> String {
        let trailingSlash = settings.bool(PathToolsModule.Key.trailingSlashForFolders)
        let paths: [String]
        switch selection.context {
        case .container:
            paths = selection.container.map { [$0.path] } ?? []
        case .items:
            paths = selection.items.map { item in
                trailingSlash && item.kind == .folder ? item.path + "/" : item.path
            }
        }
        return join(paths.map { decorate($0, settings: settings) }, settings: settings)
    }

    /// Shell escaping when chosen (for Terminal); otherwise the plain wrapping characters, if any.
    public static func decorate(_ value: String, settings: ModuleSettings) -> String {
        switch settings.string(PathToolsModule.Key.quoting) {
        case "single": return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
        case "double": return ShellQuoting.doubleQuote(value)
        case "backslash": return ShellQuoting.backslashEscape(value)
        default: return wrap(value, settings: settings)
        }
    }

    static func wrap(_ value: String, settings: ModuleSettings) -> String {
        switch settings.string(PathToolsModule.Key.wrap) {
        case "single": return "'\(value)'"
        case "double": return "\"\(value)\""
        case "curlySingle": return "‘\(value)’"
        case "curlyDouble": return "“\(value)”"
        default: return value
        }
    }

    public static func join(_ values: [String], settings: ModuleSettings) -> String {
        let separator: String
        switch settings.string(PathToolsModule.Key.separator) {
        case "space": separator = " "
        case "comma": separator = ", "
        case "tab": separator = "\t"
        case "custom": separator = settings.string(PathToolsModule.Key.customSeparator)
        default: separator = "\n"
        }
        return values.joined(separator: separator)
    }
}
