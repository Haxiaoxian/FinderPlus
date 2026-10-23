import FinderPlusCore
import Foundation

/// A kind of file the "New File" menu can create.
public struct NewFileType: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case text(String)
        case wordDocument
        case spreadsheet
        case presentation
        case pdf
    }

    public var id: String
    public var pathExtension: String
    public var title: LocalizedText
    public var icon: String
    public var content: Content

    public init(id: String, pathExtension: String, title: LocalizedText, icon: String, content: Content) {
        self.id = id
        self.pathExtension = pathExtension
        self.title = title
        self.icon = icon
        self.content = content
    }

    public func makeData(date: Date = Date()) -> Data {
        switch content {
        case .text(let text): return Data(text.utf8)
        case .wordDocument: return DocumentFactory.wordDocument(date: date)
        case .spreadsheet: return DocumentFactory.spreadsheet(date: date)
        case .presentation: return DocumentFactory.presentation(date: date)
        case .pdf: return DocumentFactory.blankPDF()
        }
    }

    public static let builtIn: [NewFileType] = [
        NewFileType(id: "md", pathExtension: "md", title: LocalizedText(en: "Markdown", zhHans: "Markdown", ko: "Markdown"),
                    icon: "text.document", content: .text("")),
        NewFileType(id: "txt", pathExtension: "txt", title: LocalizedText(en: "Text File", zhHans: "文本文件", ko: "텍스트 파일"),
                    icon: "doc.plaintext", content: .text("")),
        NewFileType(id: "docx", pathExtension: "docx", title: LocalizedText(en: "Word Document", zhHans: "Word 文档", ko: "Word 문서"),
                    icon: "doc.richtext", content: .wordDocument),
        NewFileType(id: "xlsx", pathExtension: "xlsx", title: LocalizedText(en: "Excel Workbook", zhHans: "Excel 工作簿", ko: "Excel 통합 문서"),
                    icon: "tablecells", content: .spreadsheet),
        NewFileType(id: "pptx", pathExtension: "pptx", title: LocalizedText(en: "PowerPoint Presentation", zhHans: "PowerPoint 演示文稿", ko: "PowerPoint 프레젠테이션"),
                    icon: "rectangle.on.rectangle", content: .presentation),
        NewFileType(id: "pdf", pathExtension: "pdf", title: LocalizedText(en: "PDF Document", zhHans: "PDF 文档", ko: "PDF 문서"),
                    icon: "doc.text", content: .pdf),
        NewFileType(id: "csv", pathExtension: "csv", title: LocalizedText(en: "CSV", zhHans: "CSV 表格", ko: "CSV"),
                    icon: "tablecells.badge.ellipsis", content: .text("")),
        NewFileType(id: "json", pathExtension: "json", title: LocalizedText(en: "JSON", zhHans: "JSON", ko: "JSON"),
                    icon: "curlybraces", content: .text("{\n}\n")),
        NewFileType(id: "py", pathExtension: "py", title: LocalizedText(en: "Python Script", zhHans: "Python 脚本", ko: "Python 스크립트"),
                    icon: "chevron.left.forwardslash.chevron.right", content: .text("#!/usr/bin/env python3\n\n")),
        NewFileType(id: "R", pathExtension: "R", title: LocalizedText(en: "R Script", zhHans: "R 脚本", ko: "R 스크립트"),
                    icon: "function", content: .text("")),
    ]
}

/// Block 01 — create new files from the Finder background menu.
public final class FileCreatorModule: FinderPlusModule {
    public static let id = "io.github.finderplus.file-creator"

    enum Key {
        static let enabledTypes = "enabledTypes"
        static let customTypes = "customTypes"
        static let baseName = "baseName"
        static let askForName = "askForName"
        static let afterCreate = "afterCreate"
        static let openApplication = "openApplication"
        static let showTemplates = "showTemplates"
    }

    /// Folder holding user templates. `default.<ext>` overrides the content of a built-in type;
    /// any other file appears under "New from Template".
    public let templatesDirectory: URL

    public init(templatesDirectory: URL = FinderPlusPaths.templatesDirectory.appendingPathComponent("FileCreator", isDirectory: true)) {
        self.templatesDirectory = templatesDirectory
    }

    public let manifest = ModuleManifest(
        id: FileCreatorModule.id,
        name: LocalizedText(en: "New File", zhHans: "文件创建", ko: "새 파일"),
        summary: LocalizedText(en: "Create Markdown, text, Office, PDF, code and custom files right in Finder.",
                               zhHans: "在 Finder 中直接新建 Markdown、文本、Office、PDF、代码及自定义文件。",
                               ko: "Finder에서 Markdown, 텍스트, Office, PDF, 코드 및 사용자 지정 파일을 바로 만듭니다."),
        version: "1.0.0",
        icon: "doc.badge.plus",
        category: .create,
        capabilities: ["finder.menu", "templates"],
        supportedTypes: NewFileType.builtIn.map(\.pathExtension),
        settings: FileCreatorModule.schema,
        permissions: [.readSelection, .writeFiles, .accessibility]
    )

    static let afterCreateOptions = [
        SettingOption("rename", LocalizedText(en: "Select and start renaming", zhHans: "选中并进入重命名", ko: "선택 후 이름 변경 시작")),
        SettingOption("reveal", LocalizedText(en: "Select in Finder", zhHans: "在 Finder 中选中", ko: "Finder에서 선택")),
        SettingOption("open", LocalizedText(en: "Open with default app", zhHans: "用默认应用打开", ko: "기본 앱으로 열기")),
        SettingOption("openWith", LocalizedText(en: "Open with a specific app", zhHans: "用指定应用打开", ko: "지정한 앱으로 열기")),
        SettingOption("none", LocalizedText(en: "Do nothing", zhHans: "不做任何操作", ko: "아무것도 안 함")),
    ]

    static let schema = SettingsSchema(sections: [
        SettingsSection(id: "types", title: LocalizedText(en: "File types", zhHans: "文件类型", ko: "파일 형식"),
                        footer: LocalizedText(en: "Menu order can be changed in Menu Manager.", zhHans: "菜单顺序可在“右键菜单管理”中调整。",
                                              ko: "메뉴 순서는 메뉴 관리에서 변경할 수 있습니다."),
                        fields: [
            .multiChoice(Key.enabledTypes, LocalizedText(en: "Show in “New File”", zhHans: "在“新建文件”中显示", ko: "“새 파일”에 표시"),
                         options: NewFileType.builtIn.map { SettingOption($0.id, $0.title) },
                         default: NewFileType.builtIn.map(\.id)),
            .objectList(Key.customTypes, LocalizedText(en: "Custom file types", zhHans: "自定义文件类型", ko: "사용자 지정 파일 형식"),
                        itemFields: [
                            .text("extension", LocalizedText(en: "Extension", zhHans: "扩展名", ko: "확장자"),
                                  placeholder: LocalizedText(stringLiteral: "swift")),
                            .text("title", LocalizedText(en: "Menu title", zhHans: "菜单名称", ko: "메뉴 이름"),
                                  placeholder: LocalizedText(stringLiteral: "Swift")),
                            SettingField(key: "content", title: LocalizedText(en: "Initial content", zhHans: "初始内容", ko: "초기 내용"),
                                         kind: .multilineText, defaultValue: ""),
                        ], titleKey: "title"),
        ]),
        SettingsSection(id: "naming", title: LocalizedText(en: "Naming", zhHans: "命名", ko: "이름"), fields: [
            .text(Key.baseName, LocalizedText(en: "Default name", zhHans: "默认文件名", ko: "기본 이름"),
                  placeholder: LocalizedText(en: "Untitled", zhHans: "未命名", ko: "제목 없음"),
                  help: LocalizedText(en: "Existing names get a number appended automatically.", zhHans: "重名时自动追加编号。",
                                      ko: "이름이 겹치면 자동으로 번호가 붙습니다.")),
            .toggle(Key.askForName, LocalizedText(en: "Ask for a name before creating", zhHans: "创建前询问文件名", ko: "만들기 전에 이름 묻기"),
                    default: false),
        ]),
        SettingsSection(id: "after", title: LocalizedText(en: "After creating", zhHans: "创建之后", ko: "만든 후"), fields: [
            .choice(Key.afterCreate, LocalizedText(en: "Action", zhHans: "操作", ko: "동작"), options: afterCreateOptions, default: "rename",
                    help: LocalizedText(en: "Starting rename needs Accessibility permission; without it the file is just selected.",
                                        zhHans: "进入重命名需要“辅助功能”权限；未授权时仅选中文件。",
                                        ko: "이름 변경 시작에는 손쉬운 사용 권한이 필요합니다. 권한이 없으면 파일만 선택됩니다.")),
            .path(Key.openApplication, LocalizedText(en: "Application", zhHans: "应用程序", ko: "응용 프로그램"), kind: .application,
                  visibleWhen: SettingCondition(key: Key.afterCreate, equals: ["openWith"])),
            .toggle(Key.showTemplates, LocalizedText(en: "Show “New from Template” menu", zhHans: "显示“从模板创建”菜单", ko: "“템플릿에서 만들기” 메뉴 표시"),
                    default: true),
        ]),
    ])

    // MARK: Menu

    public func availableTypes(settings: ModuleSettings) -> [NewFileType] {
        let enabled = Set(settings.strings(Key.enabledTypes))
        var types = NewFileType.builtIn.filter { enabled.contains($0.id) }
        for object in settings.objects(Key.customTypes) {
            let ext = (object["extension"]?.stringValue ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ")).replacingOccurrences(of: "/", with: "")
            guard !ext.isEmpty else { continue }
            let rawTitle = object["title"]?.stringValue ?? ""
            let title = rawTitle.isEmpty ? ext.uppercased() : rawTitle
            types.append(NewFileType(id: "custom-\(ext)", pathExtension: ext, title: LocalizedText(stringLiteral: title),
                                     icon: "doc", content: .text(object["content"]?.stringValue ?? "")))
        }
        return types
    }

    public func templates() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: templatesDirectory, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { !$0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix("default") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        var actions = availableTypes(settings: settings).enumerated().map { index, type in
            ActionDescriptor(
                id: "new.\(type.id)",
                title: type.title,
                icon: type.icon,
                group: .create,
                order: (index + 1) * 10,
                rule: .container,
                parameters: ["type": type.id]
            )
        }
        if settings.bool(Key.showTemplates) {
            for (index, template) in templates().enumerated() {
                actions.append(ActionDescriptor(
                    id: "template.\(template.lastPathComponent)",
                    title: LocalizedText(stringLiteral: template.deletingPathExtension().lastPathComponent),
                    icon: "doc.on.doc",
                    group: .template,
                    order: (index + 1) * 10,
                    rule: .container,
                    parameters: ["template": template.lastPathComponent]
                ))
            }
        }
        return actions
    }

    // MARK: Perform

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        guard let folder = invocation.selection.destinationFolder else {
            throw ModuleError.invalidSelection(LocalizedText(en: "No destination folder.", zhHans: "没有目标文件夹。", ko: "대상 폴더가 없습니다.").localized)
        }
        let settings = invocation.settings
        let created: URL
        if let typeID = invocation.parameters["type"] {
            guard let type = availableTypes(settings: settings).first(where: { $0.id == typeID }) else {
                throw ModuleError.unknownAction(invocation.actionID)
            }
            let base = settings.nonEmptyString(Key.baseName) ?? Self.defaultBaseName.localized
            guard let url = try await destination(in: folder, baseName: base, ext: type.pathExtension, settings: settings, context: context) else {
                return .none
            }
            let data = templateOverride(for: type.pathExtension) ?? type.makeData()
            try data.write(to: url, options: .withoutOverwriting)
            created = url
        } else if let templateName = invocation.parameters["template"] {
            let source = templatesDirectory.appendingPathComponent(templateName)
            guard FileManager.default.fileExists(atPath: source.path), !templateName.contains("/") else {
                throw ModuleError.failed(LocalizedText(en: "Template not found: \(templateName)", zhHans: "找不到模板：\(templateName)",
                                                       ko: "템플릿을 찾을 수 없음: \(templateName)").localized)
            }
            let base = source.deletingPathExtension().lastPathComponent
            guard let url = try await destination(in: folder, baseName: base, ext: source.pathExtension, settings: settings, context: context) else {
                return .none
            }
            try FileManager.default.copyItem(at: source, to: url)
            created = url
        } else {
            throw ModuleError.unknownAction(invocation.actionID)
        }

        let message = try await afterCreate(created, settings: settings, context: context)
        return ActionOutcome(message: message, outputs: [created])
    }

    static let defaultBaseName = LocalizedText(en: "Untitled", zhHans: "未命名", ko: "제목 없음")

    private func destination(in folder: URL, baseName: String, ext: String, settings: ModuleSettings,
                             context: ModuleContext) async throws -> URL? {
        guard settings.bool(Key.askForName) else {
            return UniqueFileNamer.availableURL(in: folder, baseName: baseName, pathExtension: ext)
        }
        let suggestion = UniqueFileNamer.availableURL(in: folder, baseName: baseName, pathExtension: ext).lastPathComponent
        guard let answer = await context.system.promptForText(
            title: LocalizedText(en: "New File", zhHans: "新建文件", ko: "새 파일").localized,
            message: LocalizedText(en: "Name:", zhHans: "文件名：", ko: "이름:").localized,
            defaultValue: suggestion
        ) else { return nil }
        var name = UniqueFileNamer.sanitizedFileName(answer)
        if !ext.isEmpty, URL(fileURLWithPath: name).pathExtension.isEmpty { name += ".\(ext)" }
        return UniqueFileNamer.availableURL(in: folder, fileName: name)
    }

    private func templateOverride(for ext: String) -> Data? {
        let url = templatesDirectory.appendingPathComponent("default.\(ext)")
        return try? Data(contentsOf: url)
    }

    private func afterCreate(_ url: URL, settings: ModuleSettings, context: ModuleContext) async throws -> String? {
        switch settings.string(Key.afterCreate) {
        case "none":
            return nil
        case "open":
            try await context.system.open([url], withApplicationAt: nil)
        case "openWith":
            let app = settings.nonEmptyString(Key.openApplication).map { URL(fileURLWithPath: $0) }
            try await context.system.open([url], withApplicationAt: app)
        case "reveal":
            await context.system.reveal([url])
        default:
            await context.system.reveal([url])
            do {
                try await context.system.beginRenameInFinder()
            } catch {
                // Creating the file succeeded; renaming is a convenience.
                return error.localizedDescription
            }
        }
        return nil
    }
}
