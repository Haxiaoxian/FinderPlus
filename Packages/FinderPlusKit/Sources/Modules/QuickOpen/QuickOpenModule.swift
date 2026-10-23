import AppKit
import FinderPlusCore
import Foundation

/// Block 03 — open items with chosen apps, open terminals, run Python and R scripts.
public final class QuickOpenModule: FinderPlusModule {
    public static let id = "io.github.finderplus.quick-open"

    enum Key {
        static let apps = "apps"
        static let hideMissingApps = "hideMissingApps"
        static let terminalApp = "terminalApp"
        static let showOpenInTerminal = "showOpenInTerminal"
        static let pythonEnabled = "pythonEnabled"
        static let interpreterMode = "interpreterMode"
        static let customInterpreter = "customInterpreter"
        static let condaEnvironment = "condaEnvironment"
        static let condaExecutable = "condaExecutable"
        static let detectVirtualEnvironment = "detectVirtualEnvironment"
        static let pythonArguments = "pythonArguments"
        static let rEnabled = "rEnabled"
        static let rscriptPath = "rscriptPath"
        static let rArguments = "rArguments"
        static let workingDirectory = "workingDirectory"
        static let customWorkingDirectory = "customWorkingDirectory"
        static let runMode = "runMode"
        static let afterRun = "afterRun"
    }

    public init() {}

    static func app(_ name: String, bundleID: String, extensions: String = "", files: Bool = true, folders: Bool) -> SettingValue {
        .object([
            "name": .string(name), "bundleID": .string(bundleID), "application": .string(""),
            "extensions": .string(extensions), "files": .bool(files), "folders": .bool(folders), "enabled": .bool(true),
        ])
    }

    static let workingDirectoryOptions = [
        SettingOption("fileFolder", LocalizedText(en: "Folder of the script", zhHans: "脚本所在文件夹", ko: "스크립트가 있는 폴더")),
        SettingOption("projectRoot", LocalizedText(en: "Project root (.venv / .git / pyproject.toml)", zhHans: "项目根目录（.venv / .git / pyproject.toml）",
                                                   ko: "프로젝트 루트(.venv / .git / pyproject.toml)")),
        SettingOption("custom", LocalizedText(en: "Custom folder", zhHans: "自定义文件夹", ko: "사용자 지정 폴더")),
    ]

    public let manifest = ModuleManifest(
        id: QuickOpenModule.id,
        name: LocalizedText(en: "Quick Open & Run", zhHans: "快捷打开与运行", ko: "빠른 열기 및 실행"),
        summary: LocalizedText(en: "Open items in VS Code, CotEditor or any app, open terminals, and run Python or R scripts.",
                               zhHans: "用 VS Code、CotEditor 或任意应用打开，打开终端，运行 Python 与 R 脚本。",
                               ko: "VS Code, CotEditor 또는 다른 앱으로 열고, 터미널을 열고, Python 및 R 스크립트를 실행합니다."),
        version: "1.0.0",
        icon: "arrow.up.forward.app",
        category: .open,
        supportedTypes: ["*", "py", "R", "folder"],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "apps", title: LocalizedText(en: "Open with", zhHans: "打开方式", ko: "다음으로 열기"),
                            footer: LocalizedText(en: "Extensions are comma separated (e.g. md, py, json). Leave empty for all files.",
                                                  zhHans: "扩展名用逗号分隔（如 md, py, json），留空表示所有文件。",
                                                  ko: "확장자는 쉼표로 구분합니다(예: md, py, json). 비워 두면 모든 파일에 적용됩니다."),
                            fields: [
                .objectList(Key.apps, LocalizedText(en: "Applications", zhHans: "应用程序", ko: "응용 프로그램"), itemFields: [
                    .text("name", LocalizedText(en: "Name", zhHans: "名称", ko: "이름")),
                    .path("application", LocalizedText(en: "Application", zhHans: "应用程序", ko: "응용 프로그램"), kind: .application,
                          placeholder: LocalizedText(en: "Found by bundle identifier", zhHans: "按 Bundle ID 自动查找", ko: "번들 ID로 찾기")),
                    .text("bundleID", LocalizedText(en: "Bundle identifier", zhHans: "Bundle ID", ko: "번들 ID")),
                    .text("extensions", LocalizedText(en: "File extensions", zhHans: "文件扩展名", ko: "파일 확장자")),
                    .toggle("files", LocalizedText(en: "Show for files", zhHans: "对文件显示", ko: "파일에 표시"), default: true),
                    .toggle("folders", LocalizedText(en: "Show for folders", zhHans: "对文件夹显示", ko: "폴더에 표시"), default: true),
                    .toggle("enabled", LocalizedText(en: "Enabled", zhHans: "启用", ko: "사용"), default: true),
                ], titleKey: "name", default: [
                    QuickOpenModule.app("VS Code", bundleID: "com.microsoft.VSCode", folders: true),
                    QuickOpenModule.app("CotEditor", bundleID: "com.coteditor.CotEditor", folders: false),
                ]),
                .toggle(Key.hideMissingApps, LocalizedText(en: "Hide apps that are not installed", zhHans: "隐藏未安装的应用", ko: "설치되지 않은 앱 숨기기"),
                        default: true),
            ]),
            SettingsSection(id: "terminal", title: LocalizedText(en: "Terminal", zhHans: "终端", ko: "터미널"), fields: [
                .choice(Key.terminalApp, LocalizedText(en: "Terminal app", zhHans: "终端应用", ko: "터미널 앱"), options: [
                    SettingOption("terminal", "Terminal"), SettingOption("iTerm", "iTerm2"),
                ], default: "terminal"),
                .toggle(Key.showOpenInTerminal, LocalizedText(en: "Show “Open in Terminal”", zhHans: "显示“在终端打开”", ko: "“터미널에서 열기” 표시"),
                        default: true),
            ]),
            SettingsSection(id: "python", title: "Python", fields: [
                .toggle(Key.pythonEnabled, LocalizedText(en: "Show “Run Python”", zhHans: "显示“运行 Python”", ko: "“Python 실행” 표시"), default: true),
                .choice(Key.interpreterMode, LocalizedText(en: "Interpreter", zhHans: "解释器", ko: "인터프리터"), options: [
                    SettingOption("auto", LocalizedText(en: "Automatic (project venv, then python3)", zhHans: "自动（项目虚拟环境，其次 python3）",
                                                        ko: "자동(프로젝트 venv, 그다음 python3)")),
                    SettingOption("python3", "python3"),
                    SettingOption("python", "python"),
                    SettingOption("custom", LocalizedText(en: "Custom path", zhHans: "自定义路径", ko: "사용자 지정 경로")),
                    SettingOption("conda", LocalizedText(en: "Conda environment", zhHans: "Conda 环境", ko: "Conda 환경")),
                ], default: "auto"),
                .path(Key.customInterpreter, LocalizedText(en: "Interpreter path", zhHans: "解释器路径", ko: "인터프리터 경로"), kind: .file,
                      placeholder: LocalizedText(stringLiteral: "/opt/homebrew/bin/python3"),
                      visibleWhen: SettingCondition(key: Key.interpreterMode, equals: ["custom"])),
                .text(Key.condaEnvironment, LocalizedText(en: "Conda environment name", zhHans: "Conda 环境名", ko: "Conda 환경 이름"),
                      default: "base", visibleWhen: SettingCondition(key: Key.interpreterMode, equals: ["conda"])),
                .path(Key.condaExecutable, LocalizedText(en: "conda executable", zhHans: "conda 可执行文件", ko: "conda 실행 파일"), kind: .file,
                      placeholder: LocalizedText(en: "Found automatically", zhHans: "自动查找", ko: "자동으로 찾기"),
                      visibleWhen: SettingCondition(key: Key.interpreterMode, equals: ["conda"])),
                .toggle(Key.detectVirtualEnvironment, LocalizedText(en: "Use the project’s .venv / venv when present", zhHans: "存在时使用项目的 .venv / venv",
                                                                    ko: "있으면 프로젝트의 .venv / venv 사용"),
                        default: true, visibleWhen: SettingCondition(key: Key.interpreterMode, equals: ["auto"])),
                .text(Key.pythonArguments, LocalizedText(en: "Arguments", zhHans: "执行参数", ko: "인수"),
                      placeholder: LocalizedText(stringLiteral: "--verbose \"two words\"")),
            ]),
            SettingsSection(id: "r", title: "R", fields: [
                .toggle(Key.rEnabled, LocalizedText(en: "Show “Run with Rscript”", zhHans: "显示“使用 Rscript 运行”", ko: "“Rscript로 실행” 표시"), default: true),
                .path(Key.rscriptPath, LocalizedText(en: "Rscript path", zhHans: "Rscript 路径", ko: "Rscript 경로"), kind: .file,
                      placeholder: LocalizedText(en: "Found automatically", zhHans: "自动查找", ko: "자동으로 찾기")),
                .text(Key.rArguments, LocalizedText(en: "Arguments", zhHans: "执行参数", ko: "인수")),
            ]),
            SettingsSection(id: "execution", title: LocalizedText(en: "Running scripts", zhHans: "脚本执行", ko: "스크립트 실행"), fields: [
                .choice(Key.workingDirectory, LocalizedText(en: "Working directory", zhHans: "工作目录", ko: "작업 디렉터리"),
                        options: QuickOpenModule.workingDirectoryOptions, default: "fileFolder"),
                .path(Key.customWorkingDirectory, LocalizedText(en: "Custom working directory", zhHans: "自定义工作目录", ko: "사용자 지정 작업 디렉터리"),
                      kind: .folder, visibleWhen: SettingCondition(key: Key.workingDirectory, equals: ["custom"])),
                .choice(Key.runMode, LocalizedText(en: "In the terminal", zhHans: "在终端中", ko: "터미널에서"), options: [
                    SettingOption("execute", LocalizedText(en: "Run immediately", zhHans: "自动执行", ko: "바로 실행")),
                    SettingOption("typeOnly", LocalizedText(en: "Only enter the command", zhHans: "仅输入命令", ko: "명령만 입력")),
                ], default: "execute",
                        help: LocalizedText(en: "Terminal.app cannot pre-type commands; FinderPlus copies the command so you can paste it.",
                                            zhHans: "Terminal.app 无法预先输入命令，FinderPlus 会复制命令供你粘贴；iTerm2 会直接输入。",
                                            ko: "Terminal.app은 명령을 미리 입력할 수 없어 명령을 복사합니다. iTerm2는 직접 입력합니다.")),
                .choice(Key.afterRun, LocalizedText(en: "When the script finishes", zhHans: "执行结束后", ko: "스크립트가 끝나면"), options: [
                    SettingOption("keepOpen", LocalizedText(en: "Keep the shell open", zhHans: "保持终端打开", ko: "셸 유지")),
                    SettingOption("exitOnSuccess", LocalizedText(en: "Exit the shell if it succeeded", zhHans: "成功后退出 Shell", ko: "성공하면 셸 종료")),
                    SettingOption("waitForKey", LocalizedText(en: "Wait for Return, then exit", zhHans: "按回车后退出", ko: "Return을 누르면 종료")),
                ], default: "keepOpen"),
            ]),
        ]),
        dependencies: [
            DependencyDescriptor(id: "python3", kind: .executable, displayName: "Python 3", executableNames: ["python3"], isRequired: false,
                                 installHint: LocalizedText(en: "brew install python", zhHans: "brew install python", ko: "brew install python")),
            DependencyDescriptor(id: "rscript", kind: .executable, displayName: "Rscript", executableNames: ["Rscript"], isRequired: false,
                                 installHint: LocalizedText(en: "Install R from cran.r-project.org or `brew install r`.",
                                                            zhHans: "从 cran.r-project.org 安装 R，或执行 `brew install r`。",
                                                            ko: "cran.r-project.org에서 R을 설치하거나 `brew install r`을 실행하세요.")),
            DependencyDescriptor(id: "vscode", kind: .application, displayName: "Visual Studio Code", bundleIdentifiers: ["com.microsoft.VSCode"],
                                 isRequired: false),
            DependencyDescriptor(id: "coteditor", kind: .application, displayName: "CotEditor", bundleIdentifiers: ["com.coteditor.CotEditor"],
                                 isRequired: false),
            DependencyDescriptor(id: "iterm", kind: .application, displayName: "iTerm2", bundleIdentifiers: ["com.googlecode.iterm2"],
                                 isRequired: false),
        ],
        permissions: [.readSelection, .runProcesses, .appleEvents]
    )

    // MARK: Apps

    struct AppTarget {
        var slug: String
        var name: String
        var applicationURL: URL?
        var extensions: Set<String>?
        var files: Bool
        var folders: Bool
    }

    func appTargets(settings: ModuleSettings, resolve: Bool = true) -> [AppTarget] {
        var used = Set<String>()
        return settings.objects(Key.apps).compactMap { object in
            guard object["enabled"]?.boolValue ?? true else { return nil }
            let name = (object["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            var url: URL?
            if let path = object["application"]?.stringValue, !path.isEmpty {
                url = URL(fileURLWithPath: path)
            } else if resolve, let bundleID = object["bundleID"]?.stringValue, !bundleID.isEmpty {
                url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            }
            let extensions = Set((object["extensions"]?.stringValue ?? "")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
                .filter { !$0.isEmpty })
            var slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            while used.contains(slug) { slug += "-2" }
            used.insert(slug)
            return AppTarget(slug: slug, name: name, applicationURL: url, extensions: extensions.isEmpty ? nil : extensions,
                             files: object["files"]?.boolValue ?? true, folders: object["folders"]?.boolValue ?? true)
        }
    }

    // MARK: Menu

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        var actions: [ActionDescriptor] = []
        let hideMissing = settings.bool(Key.hideMissingApps)
        for (index, app) in appTargets(settings: settings).enumerated() {
            if hideMissing, app.applicationURL == nil { continue }
            guard app.files || app.folders else { continue }
            var kinds: Set<ItemKind> = []
            if app.files { kinds.formUnion([.file, .package]) }
            if app.folders { kinds.insert(.folder) }
            // Folders always match when allowed; the extension filter applies to files only.
            let rule = MenuRule(contexts: app.folders ? [.items, .container] : [.items],
                                itemKinds: kinds, extensions: app.extensions)
            actions.append(ActionDescriptor(
                id: "open.\(app.slug)",
                title: LocalizedText(en: "Open with {app}", zhHans: "使用 {app} 打开", ko: "{app}(으)로 열기").replacing("app", with: app.name),
                shortTitle: LocalizedText(stringLiteral: app.name),
                icon: "arrow.up.forward.app",
                group: .open,
                order: 10 + index * 10,
                rule: rule,
                parameters: ["app": app.slug]
            ))
        }
        if settings.bool(Key.showOpenInTerminal) {
            let terminal = TerminalApplication(rawValue: settings.string(Key.terminalApp)) ?? .terminal
            actions.append(ActionDescriptor(
                id: "terminal",
                title: LocalizedText(en: "Open in {app}", zhHans: "在 {app} 中打开", ko: "{app}에서 열기").replacing("app", with: terminal.displayName),
                shortTitle: LocalizedText(stringLiteral: terminal.displayName),
                icon: "terminal",
                group: .open,
                order: 5,
                rule: MenuRule(contexts: [.items, .container], maxSelection: 5)
            ))
        }
        if settings.bool(Key.pythonEnabled) {
            actions.append(ActionDescriptor(
                id: "runPython",
                title: LocalizedText(en: "Run Python", zhHans: "运行 Python", ko: "Python 실행"),
                icon: "play.fill", group: .run, order: 10,
                rule: .files(["py"], max: 1)
            ))
        }
        if settings.bool(Key.rEnabled) {
            actions.append(ActionDescriptor(
                id: "runR",
                title: LocalizedText(en: "Run with Rscript", zhHans: "使用 Rscript 运行", ko: "Rscript로 실행"),
                icon: "play.fill", group: .run, order: 20,
                rule: .files(["r"], max: 1)
            ))
        }
        return actions
    }

    // MARK: Perform

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let settings = invocation.settings
        let selection = invocation.selection
        switch invocation.actionID {
        case "terminal":
            let terminal = TerminalApplication(rawValue: settings.string(Key.terminalApp)) ?? .terminal
            var folders: [URL] = []
            for url in selection.targetURLs {
                let item = SelectedItem.inspect(url)
                let folder = item.kind == .folder ? url : url.deletingLastPathComponent()
                if !folders.contains(folder) { folders.append(folder) }
            }
            for folder in folders {
                try await context.system.openTerminal(terminal, at: folder)
            }
            return .none
        case "runPython", "runR":
            guard let file = selection.files.first?.url else {
                throw ModuleError.invalidSelection(LocalizedText(en: "Select a script.", zhHans: "请选择一个脚本。", ko: "스크립트를 선택하세요.").localized)
            }
            let plan = try invocation.actionID == "runPython"
                ? ScriptRunPlanner.python(file: file, settings: settings)
                : ScriptRunPlanner.r(file: file, settings: settings)
            context.reporter.log(plan.commandLine)
            let terminal = TerminalApplication(rawValue: settings.string(Key.terminalApp)) ?? .terminal
            try await context.system.runInTerminal(TerminalCommand(
                application: terminal,
                commandLine: plan.commandLine,
                execute: settings.string(Key.runMode) != "typeOnly"
            ))
            return .none
        default:
            guard let slug = invocation.parameters["app"],
                  let app = appTargets(settings: settings).first(where: { $0.slug == slug }) else {
                throw ModuleError.unknownAction(invocation.actionID)
            }
            guard let appURL = app.applicationURL else {
                throw ModuleError.dependencyMissing(LocalizedText(en: "\(app.name) is not installed.", zhHans: "未安装 \(app.name)。",
                                                                  ko: "\(app.name)이(가) 설치되어 있지 않습니다.").localized)
            }
            let urls = selection.targetURLs.filter { url in
                guard let extensions = app.extensions else { return true }
                return SelectedItem.inspect(url).kind == .folder || extensions.contains(url.pathExtension.lowercased())
            }
            guard !urls.isEmpty else { return .none }
            try await context.system.open(urls, withApplicationAt: appURL)
            return .none
        }
    }
}

/// Builds terminal command lines for running scripts. Pure and unit-tested; every path and
/// argument is quoted with ``ShellQuoting``.
public enum ScriptRunPlanner {
    public struct Plan: Equatable {
        public var workingDirectory: URL
        public var arguments: [String]
        public var commandLine: String
    }

    typealias Key = QuickOpenModule.Key

    public static func python(file: URL, settings: ModuleSettings,
                              locate: (String) -> URL? = { ExecutableLocator.locate($0) },
                              fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) throws -> Plan {
        let interpreter: [String]
        switch settings.string(Key.interpreterMode) {
        case "python3":
            interpreter = [locate("python3")?.path ?? "python3"]
        case "python":
            interpreter = [locate("python")?.path ?? "python"]
        case "custom":
            guard let path = settings.nonEmptyString(Key.customInterpreter) else {
                throw ModuleError.failed(LocalizedText(en: "Set the interpreter path in Quick Open settings.",
                                                       zhHans: "请在“快捷打开与运行”设置中填写解释器路径。",
                                                       ko: "빠른 열기 설정에서 인터프리터 경로를 지정하세요.").localized)
            }
            interpreter = [NSString(string: path).expandingTildeInPath]
        case "conda":
            let conda = settings.nonEmptyString(Key.condaExecutable).map { NSString(string: $0).expandingTildeInPath }
                ?? locate("conda")?.path ?? locate("mamba")?.path ?? "conda"
            let environment = settings.nonEmptyString(Key.condaEnvironment) ?? "base"
            interpreter = [conda, "run", "--no-capture-output", "-n", environment, "python"]
        default:
            if settings.bool(Key.detectVirtualEnvironment),
               let venvPython = virtualEnvironmentPython(near: file, fileExists: fileExists) {
                interpreter = [venvPython]
            } else {
                interpreter = [locate("python3")?.path ?? "python3"]
            }
        }
        let extra = try ShellWords.split(settings.string(Key.pythonArguments))
        return plan(arguments: interpreter + [file.path] + extra, file: file, settings: settings, fileExists: fileExists)
    }

    public static func r(file: URL, settings: ModuleSettings,
                         locate: (String) -> URL? = { ExecutableLocator.locate($0) },
                         fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) throws -> Plan {
        let rscript = settings.nonEmptyString(Key.rscriptPath).map { NSString(string: $0).expandingTildeInPath }
            ?? locate("Rscript")?.path ?? "Rscript"
        let extra = try ShellWords.split(settings.string(Key.rArguments))
        return plan(arguments: [rscript, file.path] + extra, file: file, settings: settings, fileExists: fileExists)
    }

    static func plan(arguments: [String], file: URL, settings: ModuleSettings, fileExists: (String) -> Bool) -> Plan {
        let folder = file.deletingLastPathComponent()
        let workingDirectory: URL
        switch settings.string(Key.workingDirectory) {
        case "projectRoot":
            workingDirectory = projectRoot(for: file, fileExists: { path in
                fileExists(path) || FileManager.default.fileExists(atPath: path)
            }) ?? folder
        case "custom":
            workingDirectory = settings.nonEmptyString(Key.customWorkingDirectory).map {
                URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
            } ?? folder
        default:
            workingDirectory = folder
        }
        var commandLine = "cd \(ShellQuoting.quote(workingDirectory.path)) && \(ShellQuoting.join(arguments))"
        switch settings.string(Key.afterRun) {
        case "exitOnSuccess":
            commandLine += " && exit"
        case "waitForKey":
            commandLine += "; printf '\\n%s' 'Press Return to close…'; read -r _; exit"
        default:
            break
        }
        return Plan(workingDirectory: workingDirectory, arguments: arguments, commandLine: commandLine)
    }

    /// Walks up from the script looking for `.venv/bin/python` or `venv/bin/python`.
    static func virtualEnvironmentPython(near file: URL, fileExists: (String) -> Bool) -> String? {
        var directory = file.deletingLastPathComponent().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for _ in 0..<12 {
            for name in [".venv", "venv"] {
                let candidate = directory.appendingPathComponent(name).appendingPathComponent("bin/python").path
                if fileExists(candidate) { return candidate }
            }
            if directory.path == "/" || directory.path == home { break }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    static func projectRoot(for file: URL, fileExists: (String) -> Bool) -> URL? {
        var directory = file.deletingLastPathComponent().standardizedFileURL
        for _ in 0..<12 {
            for marker in [".venv", "venv", ".git", "pyproject.toml", "setup.py", "requirements.txt", ".Rproj.user", "renv.lock"] {
                if fileExists(directory.appendingPathComponent(marker).path) { return directory }
            }
            if directory.path == "/" { break }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }
}
