import Foundation

/// The contract every feature module implements.
///
/// A module describes itself with a ``ModuleManifest`` and performs its actions when invoked.
/// It never talks to Finder, other modules or the configuration file directly: everything it
/// needs arrives through ``ActionInvocation`` and ``ModuleContext``.
///
/// Native modules are Swift package targets listed in `BuiltinModules`. Script packages are
/// wrapped by the engine's `ScriptPackageModule`, which implements this same protocol.
public protocol FinderPlusModule: AnyObject {
    var manifest: ModuleManifest { get }

    /// Actions for the current settings. Override when the menu depends on configuration
    /// (one "New …" item per enabled file type, one "Open with …" item per configured app).
    func menuActions(settings: ModuleSettings) -> [ActionDescriptor]

    /// Executes one action. Throw ``ModuleError`` (or any error) to report a failure; the engine
    /// catches it, records it in the task center and keeps every other module running.
    func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome

    /// Reports dependency health for the dependency page and module cards.
    func dependencyStatuses(settings: ModuleSettings, checker: DependencyChecking) async -> [DependencyStatus]
}

extension FinderPlusModule {
    public var id: String { manifest.id }

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        manifest.actions
    }

    public func dependencyStatuses(settings: ModuleSettings, checker: DependencyChecking) async -> [DependencyStatus] {
        await checker.statuses(for: manifest.dependencies)
    }

    /// Looks up an action by id among the actions for `settings`.
    public func action(_ id: String, settings: ModuleSettings) -> ActionDescriptor? {
        menuActions(settings: settings).first { $0.id == id }
    }
}

/// One concrete invocation of an action.
public struct ActionInvocation: Sendable {
    public var requestID: UUID
    public var actionID: String
    public var parameters: [String: String]
    public var selection: FinderSelection
    public var settings: ModuleSettings

    public init(requestID: UUID = UUID(), actionID: String, parameters: [String: String] = [:],
                selection: FinderSelection, settings: ModuleSettings) {
        self.requestID = requestID
        self.actionID = actionID
        self.parameters = parameters
        self.selection = selection
        self.settings = settings
    }
}

/// What an action produced.
public struct ActionOutcome: Sendable {
    /// Short human-readable summary ("3 images compressed, saved 4.2 MB").
    public var message: String?
    public var outputs: [URL]
    /// Select the outputs in Finder once the action finishes.
    public var revealOutputs: Bool

    public init(message: String? = nil, outputs: [URL] = [], revealOutputs: Bool = false) {
        self.message = message
        self.outputs = outputs
        self.revealOutputs = revealOutputs
    }

    public static let none = ActionOutcome()

    public static func message(_ message: String) -> ActionOutcome {
        ActionOutcome(message: message)
    }
}

public enum ModuleError: LocalizedError, Equatable {
    case unknownAction(String)
    case invalidSelection(String)
    case dependencyMissing(String)
    case unsupported(String)
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownAction(let id):
            return LocalizedText(en: "Unknown action “\(id)”.", zhHans: "未知操作“\(id)”。", ko: "알 수 없는 작업 “\(id)”.").localized
        case .invalidSelection(let detail):
            return detail
        case .dependencyMissing(let detail):
            return detail
        case .unsupported(let detail):
            return detail
        case .cancelled:
            return LocalizedText(en: "Cancelled.", zhHans: "已取消。", ko: "취소됨.").localized
        case .failed(let detail):
            return detail
        }
    }
}

/// Services the host provides to a module for the duration of one invocation.
public struct ModuleContext: Sendable {
    public var moduleID: String
    /// Private, persistent directory for this module (created on demand).
    public var dataDirectory: URL
    public var system: SystemServices
    public var processes: ProcessRunner
    public var reporter: TaskReporter
    public var dependencies: DependencyChecking
    /// Private Python environments managed by FinderPlus (no system Python or Homebrew needed).
    public var python: PythonEnvironmentProviding

    public init(moduleID: String, dataDirectory: URL, system: SystemServices, processes: ProcessRunner,
                reporter: TaskReporter, dependencies: DependencyChecking,
                python: PythonEnvironmentProviding = UnavailablePythonEnvironments()) {
        self.moduleID = moduleID
        self.dataDirectory = dataDirectory
        self.system = system
        self.processes = processes
        self.reporter = reporter
        self.dependencies = dependencies
        self.python = python
    }

    /// `dataDirectory`, created if necessary.
    public func ensuredDataDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        return dataDirectory
    }

    public func checkCancellation() throws {
        if Task.isCancelled { throw ModuleError.cancelled }
    }
}

/// Progress and log reporting for the task center.
public protocol TaskReporter: Sendable {
    /// `fraction` in 0…1, or `nil` for indeterminate progress.
    func progress(_ fraction: Double?, message: String?)
    func log(_ line: String)
}

public extension TaskReporter {
    func progress(completed: Int, of total: Int, message: String? = nil) {
        progress(total > 0 ? Double(completed) / Double(total) : nil, message: message)
    }
}

/// Reporter that discards everything (tests, previews).
public struct SilentTaskReporter: TaskReporter {
    public init() {}
    public func progress(_ fraction: Double?, message: String?) {}
    public func log(_ line: String) {}
}

/// Isolated Python environments shared by every module that needs Python packages.
///
/// The host downloads a pinned, checksum-verified `uv` and lets it install a standalone Python, so a
/// module only says *which packages* it needs; nothing touches the user's own Python installation.
public protocol PythonEnvironmentProviding: Sendable {
    /// Creates or updates `Runtimes/envs/<name>` with `packages` installed and returns the folder.
    func prepareEnvironment(named name: String, pythonVersion: String, packages: [String],
                            reporter: TaskReporter) async throws -> URL
    /// Folder of the environment (it may not exist yet).
    func environmentDirectory(named name: String) -> URL
    /// An executable inside the environment's `bin` folder, if installed.
    func executable(_ command: String, inEnvironment name: String) -> URL?
    func removeEnvironment(named name: String) throws
}

/// Used where no host is available (tests, previews).
public struct UnavailablePythonEnvironments: PythonEnvironmentProviding {
    public init() {}

    public func prepareEnvironment(named name: String, pythonVersion: String, packages: [String],
                                   reporter: TaskReporter) async throws -> URL {
        throw ModuleError.unsupported("Managed Python environments are not available here.")
    }

    public func environmentDirectory(named name: String) -> URL {
        FinderPlusPaths.runtimesDirectory.appendingPathComponent("envs/\(name)", isDirectory: true)
    }

    public func executable(_ command: String, inEnvironment name: String) -> URL? {
        let url = environmentDirectory(named: name).appendingPathComponent("bin/\(command)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public func removeEnvironment(named name: String) throws {}
}
