import FinderPlusCore
import Foundation

/// Block 04.3 — convert documents to Markdown with Microsoft MarkItDown (runs locally).
///
/// FinderPlus manages a private virtual environment under
/// `~/Library/Application Support/FinderPlus/Runtimes/markitdown`, so nothing is installed into the
/// user's own Python. A custom `markitdown` executable or one on PATH can be used instead.
public final class MarkItDownModule: FinderPlusModule {
    public static let id = "io.github.finderplus.markitdown"

    enum Key {
        static let runtime = "runtime"
        static let customExecutable = "customExecutable"
        static let basePython = "basePython"
        static let outputLocation = "outputLocation"
        static let outputFolder = "outputFolder"
        static let collision = "collision"
        static let keepDataURIs = "keepDataURIs"
        static let openAfter = "openAfter"
    }

    static let inputExtensions: Set<String> = ["pdf", "docx", "pptx", "xlsx", "xls", "html", "htm", "csv", "json", "xml",
                                                "epub", "msg", "ipynb", "zip", "txt", "rtf"]

    public let runtimeDirectory: URL

    public init(runtimeDirectory: URL = FinderPlusPaths.runtimesDirectory.appendingPathComponent("markitdown", isDirectory: true)) {
        self.runtimeDirectory = runtimeDirectory
    }

    public let manifest = ModuleManifest(
        id: MarkItDownModule.id,
        name: LocalizedText(en: "MarkItDown", zhHans: "MarkItDown 转 Markdown", ko: "MarkItDown"),
        summary: LocalizedText(en: "Convert PDF, Word, PowerPoint, Excel and HTML to Markdown locally with Microsoft MarkItDown.",
                               zhHans: "使用微软 MarkItDown 在本地将 PDF、Word、PowerPoint、Excel、HTML 转为 Markdown。",
                               ko: "Microsoft MarkItDown으로 PDF, Word, PowerPoint, Excel, HTML을 로컬에서 Markdown으로 변환합니다."),
        version: "1.0.0",
        icon: "text.badge.checkmark",
        category: .convert,
        supportedTypes: Array(MarkItDownModule.inputExtensions).sorted(),
        settings: SettingsSchema(sections: [
            SettingsSection(id: "runtime", title: LocalizedText(en: "Runtime", zhHans: "运行环境", ko: "런타임"),
                            footer: LocalizedText(en: "Conversion runs on this Mac. No files are uploaded.",
                                                  zhHans: "转换完全在本机进行，不会上传任何文件。",
                                                  ko: "변환은 이 Mac에서 실행되며 파일을 업로드하지 않습니다."),
                            fields: [
                .choice(Key.runtime, LocalizedText(en: "MarkItDown runtime", zhHans: "MarkItDown 运行环境", ko: "MarkItDown 런타임"), options: [
                    SettingOption("managed", LocalizedText(en: "Managed by FinderPlus (recommended)", zhHans: "由 FinderPlus 管理（推荐）", ko: "FinderPlus가 관리(권장)")),
                    SettingOption("path", LocalizedText(en: "markitdown found on PATH", zhHans: "使用 PATH 中的 markitdown", ko: "PATH의 markitdown")),
                    SettingOption("custom", LocalizedText(en: "Custom executable", zhHans: "自定义可执行文件", ko: "사용자 지정 실행 파일")),
                ], default: "managed"),
                .path(Key.customExecutable, LocalizedText(en: "markitdown executable", zhHans: "markitdown 可执行文件", ko: "markitdown 실행 파일"),
                      kind: .file, visibleWhen: SettingCondition(key: Key.runtime, equals: ["custom"])),
                .path(Key.basePython, LocalizedText(en: "Python used to create the environment", zhHans: "创建环境所用的 Python", ko: "환경 생성에 사용할 Python"),
                      kind: .file, placeholder: LocalizedText(en: "Newest Python ≥ 3.10 found automatically", zhHans: "自动选择 ≥ 3.10 的最新 Python",
                                                              ko: "3.10 이상 최신 Python 자동 선택"),
                      visibleWhen: SettingCondition(key: Key.runtime, equals: ["managed"])),
            ]),
            SettingsSection(id: "output", title: LocalizedText(en: "Output", zhHans: "输出", ko: "출력"), fields: [
                .choice(Key.outputLocation, LocalizedText(en: "Save to", zhHans: "保存位置", ko: "저장 위치"), options: [
                    SettingOption("same", LocalizedText(en: "Next to the original", zhHans: "原文件旁边", ko: "원본 옆")),
                    SettingOption("custom", LocalizedText(en: "A specific folder", zhHans: "指定文件夹", ko: "지정한 폴더")),
                ], default: "same"),
                .path(Key.outputFolder, LocalizedText(en: "Folder", zhHans: "文件夹", ko: "폴더"), kind: .folder,
                      visibleWhen: SettingCondition(key: Key.outputLocation, equals: ["custom"])),
                .choice(Key.collision, LocalizedText(en: "If the Markdown file exists", zhHans: "Markdown 文件已存在时", ko: "Markdown 파일이 이미 있으면"), options: [
                    SettingOption("rename", LocalizedText(en: "Keep both (add number)", zhHans: "保留两者（追加编号）", ko: "둘 다 유지(번호 추가)")),
                    SettingOption("overwrite", LocalizedText(en: "Replace", zhHans: "覆盖", ko: "바꾸기")),
                    SettingOption("skip", LocalizedText(en: "Skip", zhHans: "跳过", ko: "건너뛰기")),
                ], default: "rename"),
                .toggle(Key.keepDataURIs, LocalizedText(en: "Keep embedded images as data URIs", zhHans: "以 data URI 保留内嵌图片", ko: "포함된 이미지를 data URI로 유지"),
                        default: false),
                .toggle(Key.openAfter, LocalizedText(en: "Open the result", zhHans: "转换后打开结果", ko: "결과 열기"), default: false),
            ]),
        ]),
        dependencies: [
            DependencyDescriptor(id: "markitdown-runtime", kind: .custom, displayName: "MarkItDown"),
        ],
        permissions: [.readSelection, .writeFiles, .runProcesses, .network]
    )

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        [
            ActionDescriptor(id: "convert", title: LocalizedText(en: "Convert to Markdown", zhHans: "转换为 Markdown", ko: "Markdown으로 변환"),
                             icon: "text.badge.checkmark", group: .convert, order: 20,
                             rule: .files(Self.inputExtensions), execution: .task),
            ActionDescriptor(id: "installRuntime", title: LocalizedText(en: "Install or Update MarkItDown", zhHans: "安装或更新 MarkItDown",
                                                                        ko: "MarkItDown 설치 또는 업데이트"),
                             icon: "arrow.down.circle", execution: .task, presentation: .hostOnly),
            ActionDescriptor(id: "removeRuntime", title: LocalizedText(en: "Remove MarkItDown Environment", zhHans: "移除 MarkItDown 环境",
                                                                       ko: "MarkItDown 환경 제거"),
                             icon: "trash", execution: .task, presentation: .hostOnly, requiresConfirmation: true),
        ]
    }

    var managedExecutable: URL { runtimeDirectory.appendingPathComponent("bin/markitdown") }
    var managedPython: URL { runtimeDirectory.appendingPathComponent("bin/python") }

    func executable(settings: ModuleSettings) -> URL? {
        switch settings.string(Key.runtime) {
        case "custom":
            return settings.nonEmptyString(Key.customExecutable).flatMap { ExecutableLocator.locate($0) }
        case "path":
            return ExecutableLocator.locate("markitdown")
        default:
            return FileManager.default.isExecutableFile(atPath: managedExecutable.path) ? managedExecutable : nil
        }
    }

    public func dependencyStatuses(settings: ModuleSettings, checker: DependencyChecking) async -> [DependencyStatus] {
        let managed = settings.string(Key.runtime) == "managed" || settings.string(Key.runtime).isEmpty
        if let url = executable(settings: settings) {
            return [DependencyStatus(id: "markitdown-runtime", displayName: "MarkItDown", state: .satisfied, detail: url.path,
                                     fixActionID: managed ? "installRuntime" : nil)]
        }
        let python = PythonFinder.findPython(preferred: settings.nonEmptyString(Key.basePython))
        let hint: String
        if managed {
            hint = python == nil
                ? LocalizedText(en: "Python 3.10 or newer is required: brew install python", zhHans: "需要 Python 3.10 或更高版本：brew install python",
                                ko: "Python 3.10 이상이 필요합니다: brew install python").localized
                : LocalizedText(en: "Click Install to create a private environment with MarkItDown.",
                                zhHans: "点击“安装”即可创建包含 MarkItDown 的独立环境。",
                                ko: "설치를 눌러 MarkItDown 전용 환경을 만드세요.").localized
        } else {
            hint = "pipx install 'markitdown[all]'"
        }
        return [DependencyStatus(id: "markitdown-runtime", displayName: "MarkItDown", state: .missing,
                                 detail: python.map { "Python: \($0.url.path) (\($0.version))" },
                                 installHint: hint, fixActionID: managed && python != nil ? "installRuntime" : nil)]
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        switch invocation.actionID {
        case "installRuntime": return try await installRuntime(settings: invocation.settings, context: context)
        case "removeRuntime": return try removeRuntime()
        case "convert": return try await convert(invocation, context: context)
        default: throw ModuleError.unknownAction(invocation.actionID)
        }
    }

    // MARK: Conversion

    private func convert(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let settings = invocation.settings
        guard let markitdown = executable(settings: settings) else {
            throw ModuleError.dependencyMissing(LocalizedText(
                en: "MarkItDown is not installed. Open FinderPlus › Dependencies to install it.",
                zhHans: "尚未安装 MarkItDown。请在 FinderPlus 的“依赖管理”中安装。",
                ko: "MarkItDown이 설치되어 있지 않습니다. FinderPlus › 종속성에서 설치하세요."
            ).localized)
        }
        let files = invocation.selection.files.map(\.url)
        var outputs: [URL] = []
        var failures: [String] = []
        var skipped = 0
        for (index, file) in files.enumerated() {
            try context.checkCancellation()
            context.reporter.progress(completed: index, of: files.count, message: file.lastPathComponent)
            guard let output = outputURL(for: file, settings: settings) else {
                skipped += 1
                context.reporter.log("\(file.lastPathComponent): skipped (exists)")
                continue
            }
            var arguments = [file.path, "-o", output.path]
            if settings.bool(Key.keepDataURIs) { arguments.append("--keep-data-uris") }
            context.reporter.log("$ " + ShellQuoting.join([markitdown.path] + arguments))
            do {
                let result = try await context.processes.run(markitdown, arguments: arguments,
                                                             workingDirectory: file.deletingLastPathComponent(),
                                                             environment: ["PYTHONIOENCODING": "utf-8"], timeout: 900)
                if !result.standardError.isEmpty { context.reporter.log(result.standardError) }
                if result.succeeded, FileManager.default.fileExists(atPath: output.path) {
                    outputs.append(output)
                } else {
                    failures.append("\(file.lastPathComponent): \(result.diagnosticTail)")
                }
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        context.reporter.progress(1, message: nil)
        if outputs.isEmpty, !failures.isEmpty { throw ModuleError.failed(failures.joined(separator: "\n")) }
        if settings.bool(Key.openAfter), !outputs.isEmpty {
            try? await context.system.open(outputs, withApplicationAt: nil)
        }
        var message = LocalizedText(en: "Converted \(outputs.count) file(s).", zhHans: "已转换 \(outputs.count) 个文件。",
                                    ko: "파일 \(outputs.count)개를 변환했습니다.").localized
        if skipped > 0 { message += " " + LocalizedText(en: "Skipped \(skipped).", zhHans: "跳过 \(skipped) 个。", ko: "\(skipped)개 건너뜀.").localized }
        if !failures.isEmpty { message += "\n" + failures.joined(separator: "\n") }
        return ActionOutcome(message: message, outputs: outputs, revealOutputs: !settings.bool(Key.openAfter))
    }

    func outputURL(for file: URL, settings: ModuleSettings) -> URL? {
        var folder = file.deletingLastPathComponent()
        if settings.string(Key.outputLocation) == "custom", let custom = settings.nonEmptyString(Key.outputFolder) {
            folder = URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath, isDirectory: true)
        }
        let base = file.deletingPathExtension().lastPathComponent
        let direct = folder.appendingPathComponent("\(base).md")
        guard FileManager.default.fileExists(atPath: direct.path) else { return direct }
        switch settings.string(Key.collision) {
        case "overwrite": return direct
        case "skip": return nil
        default: return UniqueFileNamer.availableURL(in: folder, baseName: base, pathExtension: "md")
        }
    }

    // MARK: Runtime management

    private func installRuntime(settings: ModuleSettings, context: ModuleContext) async throws -> ActionOutcome {
        guard let python = PythonFinder.findPython(preferred: settings.nonEmptyString(Key.basePython)) else {
            throw ModuleError.dependencyMissing(LocalizedText(
                en: "No Python 3.10+ found. Install it with `brew install python` or from python.org.",
                zhHans: "未找到 Python 3.10 及以上版本。请通过 `brew install python` 或 python.org 安装。",
                ko: "Python 3.10 이상을 찾을 수 없습니다. `brew install python` 또는 python.org에서 설치하세요."
            ).localized)
        }
        let reporter = context.reporter
        func step(_ fraction: Double, _ message: String, _ executable: URL, _ arguments: [String]) async throws {
            try context.checkCancellation()
            reporter.progress(fraction, message: message)
            reporter.log("$ " + ShellQuoting.join([executable.path] + arguments))
            let result = try await context.processes.run(executable, arguments: arguments, timeout: 1800,
                                                         onOutputLine: { reporter.log($0) })
            guard result.succeeded else { throw ModuleError.failed(result.diagnosticTail) }
        }
        try FileManager.default.createDirectory(at: runtimeDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.isExecutableFile(atPath: managedPython.path) {
            try await step(0.1, "Creating virtual environment", python.url, ["-m", "venv", runtimeDirectory.path])
        }
        try await step(0.3, "Updating pip", managedPython, ["-m", "pip", "install", "--upgrade", "pip"])
        try await step(0.5, "Installing markitdown[all]", managedPython, ["-m", "pip", "install", "--upgrade", "markitdown[all]"])
        reporter.progress(1, message: nil)
        return .message(LocalizedText(en: "MarkItDown is ready (Python \(python.version)).", zhHans: "MarkItDown 已就绪（Python \(python.version)）。",
                                      ko: "MarkItDown 준비 완료(Python \(python.version)).").localized)
    }

    private func removeRuntime() throws -> ActionOutcome {
        if FileManager.default.fileExists(atPath: runtimeDirectory.path) {
            try FileManager.default.trashItem(at: runtimeDirectory, resultingItemURL: nil)
        }
        return .message(LocalizedText(en: "MarkItDown environment moved to the Trash.", zhHans: "MarkItDown 环境已移到废纸篓。",
                                      ko: "MarkItDown 환경을 휴지통으로 옮겼습니다.").localized)
    }
}

/// Finds a Python interpreter new enough for MarkItDown (3.10+). Skips `/usr/bin/python3`, the
/// Command Line Tools shim, which is 3.9 and may trigger an installer dialog.
enum PythonFinder {
    struct Found {
        var url: URL
        var version: String
    }

    static func findPython(preferred: String?) -> Found? {
        var candidates: [URL] = []
        if let preferred, let url = ExecutableLocator.locate(preferred) { candidates.append(url) }
        for name in ["python3.13", "python3.12", "python3.11", "python3.10", "python3"] {
            if let url = ExecutableLocator.locate(name), url.path != "/usr/bin/python3", !candidates.contains(url) {
                candidates.append(url)
            }
        }
        for url in candidates {
            if let version = version(of: url), version >= SemanticVersion(3, 10) {
                return Found(url: url, version: version.description)
            }
        }
        return nil
    }

    static func version(of python: URL) -> SemanticVersion? {
        let process = Process()
        process.executableURL = python
        process.arguments = ["-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return SemanticVersion(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
