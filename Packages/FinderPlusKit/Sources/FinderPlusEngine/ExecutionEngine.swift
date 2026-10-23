import Foundation
import FinderPlusCore
import os

/// A request for a module-provided window (``ExecutionStyle/interactive(route:)``).
public struct InteractiveRequest {
    public var module: FinderPlusModule
    public var route: String
    public var request: ActionRequest
    public var settings: ModuleSettings
}

/// Dispatches action requests to modules, tracks them as tasks and isolates failures.
///
/// Every invocation runs in its own detached task. A module that throws only fails its own task;
/// the engine, the menu and all other modules keep working. (Crash isolation for untrusted native
/// code would require an XPC service — see docs/ARCHITECTURE.md, "Execution service".)
@MainActor
public final class ExecutionEngine {
    public let registry: ModuleRegistry
    public let configuration: ConfigurationStore
    public let tasks: TaskStore
    public let system: SystemServices
    public let dependencies: DependencyChecking
    public let processes = ProcessRunner()

    /// Presents module windows for interactive actions. Set by the host app.
    public var interactiveHandler: ((InteractiveRequest) -> Void)?
    /// Called after the menu snapshot was rewritten.
    public var snapshotDidChange: ((MenuSnapshot) -> Void)?

    private var running: [UUID: Task<ActionOutcome, Error>] = [:]
    private let logger = Logger(subsystem: "io.github.finderplus", category: "engine")

    public init(registry: ModuleRegistry, configuration: ConfigurationStore, tasks: TaskStore,
                system: SystemServices, dependencies: DependencyChecking) {
        self.registry = registry
        self.configuration = configuration
        self.tasks = tasks
        self.system = system
        self.dependencies = dependencies
    }

    // MARK: Dispatch

    public func handle(_ request: ActionRequest) {
        let config = configuration.load()
        guard let module = registry.module(request.moduleID) else {
            tasks.recordRejection(request: request, moduleName: request.moduleID, title: request.actionID,
                                  reason: Strings.moduleMissing.localized)
            return
        }
        let manifest = module.manifest
        let moduleName = manifest.name.localized
        guard config.isEnabled(manifest) else {
            tasks.recordRejection(request: request, moduleName: moduleName, title: request.actionID,
                                  reason: Strings.moduleDisabled.localized)
            return
        }
        if manifest.kind == .scriptPackage, !isTrusted(module, in: config) {
            tasks.recordRejection(request: request, moduleName: moduleName, title: request.actionID,
                                  reason: Strings.packageUntrusted.localized)
            return
        }
        let settings = config.settings(for: manifest)
        guard let action = module.action(request.actionID, settings: settings) else {
            tasks.recordRejection(request: request, moduleName: moduleName, title: request.actionID,
                                  reason: ModuleError.unknownAction(request.actionID).localizedDescription)
            return
        }
        if request.origin == .finder, action.presentation == .hostOnly {
            logger.error("Rejected host-only action \(request.key, privacy: .public) from Finder")
            return
        }

        Task { @MainActor in
            if action.requiresConfirmation, config.general.confirmDangerousActions {
                let message = action.confirmationMessage?.localized ?? Strings.confirmDefault.localized
                let confirmed = await system.confirm(title: action.title.localized, message: message,
                                                     confirmButton: Strings.continueButton.localized)
                guard confirmed else { return }
            }
            if case .interactive(let route) = action.execution {
                interactiveHandler?(InteractiveRequest(module: module, route: route, request: request, settings: settings))
                return
            }
            await run(module: module, action: action, request: request, settings: settings,
                      notify: config.general.notifyOnTaskCompletion)
        }
    }

    /// Runs a `hostOnly` action, e.g. "Install runtime" from the dependency page.
    public func runHostAction(moduleID: String, actionID: String, selection: FinderSelection = .empty) {
        handle(ActionRequest(moduleID: moduleID, actionID: actionID, selection: selection, origin: .host))
    }

    public func cancel(_ taskID: UUID) {
        running[taskID]?.cancel()
    }

    private func run(module: FinderPlusModule, action: ActionDescriptor, request: ActionRequest,
                     settings: ModuleSettings, notify: Bool) async {
        let tracked: Bool
        if case .task = action.execution { tracked = true } else { tracked = false }
        let taskID = tasks.start(request: request, moduleName: module.manifest.name.localized,
                                 title: action.title.localized, tracked: tracked)
        let context = ModuleContext(
            moduleID: module.id,
            dataDirectory: FinderPlusPaths.moduleDataDirectory(module.id),
            system: system,
            processes: processes,
            reporter: StoreTaskReporter(store: tasks, taskID: taskID),
            dependencies: dependencies
        )
        var parameters = action.parameters
        parameters.merge(request.parameters) { _, requested in requested }
        let invocation = ActionInvocation(requestID: request.id, actionID: action.id, parameters: parameters,
                                          selection: request.selection, settings: settings)

        let work = Task.detached(priority: .userInitiated) {
            try await module.perform(invocation, context: context)
        }
        running[taskID] = work
        defer { running[taskID] = nil }

        do {
            let outcome = try await work.value
            tasks.finish(taskID, status: .succeeded, message: outcome.message, outputs: outcome.outputs)
            if outcome.revealOutputs, !outcome.outputs.isEmpty {
                await system.reveal(outcome.outputs)
            }
            if tracked, notify {
                await system.notify(title: action.title.localized, body: outcome.message ?? Strings.done.localized)
            }
        } catch is CancellationError {
            tasks.finish(taskID, status: .cancelled, message: ModuleError.cancelled.localizedDescription)
        } catch ModuleError.cancelled {
            tasks.finish(taskID, status: .cancelled, message: ModuleError.cancelled.localizedDescription)
        } catch {
            let message = error.localizedDescription
            logger.error("\(request.key, privacy: .public) failed: \(message, privacy: .public)")
            tasks.finish(taskID, status: .failed, message: message)
            await system.notify(title: Strings.failedTitle.replacing("action", with: action.title.localized).localized,
                                body: message)
        }
    }

    // MARK: Menu snapshot

    public func isTrusted(_ module: FinderPlusModule, in config: HostConfiguration) -> Bool {
        guard let package = module as? ScriptPackageModule else { return true }
        return config.trustedPackages[package.manifest.id] == package.contentHash
    }

    /// Recomputes and writes the snapshot the Finder extension reads.
    @discardableResult
    public func publishMenuSnapshot() -> MenuSnapshot {
        let config = configuration.load()
        let snapshot = Self.buildSnapshot(registry: registry, configuration: config)
        do {
            try snapshot.write()
        } catch {
            logger.error("Could not write menu snapshot: \(error.localizedDescription, privacy: .public)")
        }
        snapshotDidChange?(snapshot)
        return snapshot
    }

    nonisolated public static func buildSnapshot(registry: ModuleRegistry, configuration config: HostConfiguration) -> MenuSnapshot {
        let appearanceSettings: ModuleSettings? = registry.module(WellKnownModule.appearance).flatMap { module in
            config.isEnabled(module.manifest) ? config.settings(for: module.manifest) : nil
        }
        let contributions = registry.modules.compactMap { module -> ModuleMenuContribution? in
            guard config.isEnabled(module.manifest) else { return nil }
            if let package = module as? ScriptPackageModule,
               config.trustedPackages[package.manifest.id] != package.contentHash { return nil }
            return ModuleMenuContribution(moduleID: module.id,
                                          actions: module.menuActions(settings: config.settings(for: module.manifest)))
        }
        return MenuSnapshotBuilder.build(contributions: contributions, preferences: config.menu,
                                         appearance: MenuAppearance(appearanceSettings: appearanceSettings))
    }

    // MARK: Dependencies

    public func dependencyStatuses(for module: FinderPlusModule) async -> [DependencyStatus] {
        let settings = configuration.load().settings(for: module.manifest)
        return await module.dependencyStatuses(settings: settings, checker: dependencies)
    }
}

enum Strings {
    static let moduleMissing = LocalizedText(en: "The module is not installed.", zhHans: "模块未安装。", ko: "모듈이 설치되어 있지 않습니다.")
    static let moduleDisabled = LocalizedText(en: "The module is disabled.", zhHans: "模块已停用。", ko: "모듈이 비활성화되었습니다.")
    static let packageUntrusted = LocalizedText(en: "The script package changed or is not trusted. Review it in FinderPlus.",
                                                zhHans: "脚本功能包已更改或未被信任，请在 FinderPlus 中重新审核。",
                                                ko: "스크립트 패키지가 변경되었거나 신뢰되지 않았습니다. FinderPlus에서 검토하세요.")
    static let confirmDefault = LocalizedText(en: "This action modifies files or system settings. Continue?",
                                              zhHans: "此操作会修改文件或系统设置，是否继续？",
                                              ko: "이 작업은 파일 또는 시스템 설정을 수정합니다. 계속하시겠습니까?")
    static let continueButton = LocalizedText(en: "Continue", zhHans: "继续", ko: "계속")
    static let done = LocalizedText(en: "Done", zhHans: "完成", ko: "완료")
    static let failedTitle = LocalizedText(en: "{action} failed", zhHans: "{action} 失败", ko: "{action} 실패")
}
