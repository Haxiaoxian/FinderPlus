import AppKit
import FinderPlusBuiltinModules
import FinderPlusCore
import FinderPlusEngine
import FinderPlusUI
import FinderSync
import Observation
import ServiceManagement
import SwiftUI

enum SidebarSection: Hashable {
    case overview
    case modules
    case menu
    case module(String)
    case templates
    case icons
    case dependencies
    case tasks
    case general
}

/// Central state of the host app. Owns the registry, engine and configuration and exposes them to SwiftUI.
@MainActor
@Observable
final class AppModel {
    let registry: ModuleRegistry
    let configurationStore: ConfigurationStore
    let tasks: TaskStore
    let engine: ExecutionEngine
    let system = MacSystemServices()
    let packageManager = ScriptPackageManager()
    let inbox = RequestInbox()

    private(set) var configuration: HostConfiguration
    private(set) var snapshot: MenuSnapshot = .empty
    private(set) var dependencyStatuses: [String: [DependencyStatus]] = [:]
    private(set) var packageLoadFailures: [String] = []
    private(set) var extensionEnabled = false
    private(set) var moduleRevision = 0
    var selection: SidebarSection? = .overview
    var languageRevision = 0
    var alertMessage: String?

    @ObservationIgnored private var republishTask: Task<Void, Never>?
    @ObservationIgnored var presentInteractive: ((InteractiveRequest) -> Void)?

    init() {
        let store = ConfigurationStore()
        let tasks = TaskStore()
        let registry = ModuleRegistry(modules: BuiltinModules.make())
        configurationStore = store
        configuration = store.load()
        self.tasks = tasks
        self.registry = registry
        engine = ExecutionEngine(registry: registry, configuration: store, tasks: tasks, system: MacSystemServices(),
                                 dependencies: DependencyChecker())
        tasks.historyLimit = configuration.general.taskHistoryLimit
        loadScriptPackages()
        migrateModuleVersions()
        applyAppearance()
        engine.interactiveHandler = { [weak self] request in self?.presentInteractive?(request) }
        engine.snapshotDidChange = { [weak self] snapshot in self?.snapshot = snapshot }
        snapshot = engine.publishMenuSnapshot()
        refreshExtensionStatus()
    }

    // MARK: Requests

    func handle(url: URL) {
        switch FinderPlusURL.parse(url) {
        case .dispatch(let id):
            if let request = inbox.take(id) { engine.handle(request) }
        case .module(let id):
            selection = .module(id)
        case .main, nil:
            break
        }
    }

    func processPendingRequests() {
        inbox.takeAll().forEach(engine.handle)
    }

    // MARK: Modules

    var modules: [FinderPlusModule] { registry.modules }

    func module(_ id: String) -> FinderPlusModule? { registry.module(id) }

    func isEnabled(_ module: FinderPlusModule) -> Bool {
        configuration.isEnabled(module.manifest)
    }

    func isTrusted(_ module: FinderPlusModule) -> Bool {
        engine.isTrusted(module, in: configuration)
    }

    func setEnabled(_ module: FinderPlusModule, _ enabled: Bool) {
        mutate { config in
            var state = config.state(for: module.manifest)
            state.enabled = enabled
            config.modules[module.id] = state
        }
    }

    func settings(for module: FinderPlusModule) -> ModuleSettings {
        configuration.settings(for: module.manifest)
    }

    func settingsBinding(for module: FinderPlusModule) -> Binding<ModuleSettings> {
        Binding(
            get: { [unowned self] in settings(for: module) },
            set: { [unowned self] newValue in
                mutate { config in
                    var state = config.state(for: module.manifest)
                    state.settings = newValue.values
                    config.modules[module.id] = state
                }
            }
        )
    }

    func resetSettings(_ module: FinderPlusModule) {
        mutate { config in
            var state = config.state(for: module.manifest)
            state.settings = [:]
            config.modules[module.id] = state
        }
    }

    func uiContext(for module: FinderPlusModule, selection: FinderSelection = .empty,
                   dismiss: @escaping () -> Void = {}) -> ModuleUIContext {
        ModuleUIContext(
            moduleID: module.id,
            settings: settingsBinding(for: module),
            selection: selection,
            dataDirectory: FinderPlusPaths.moduleDataDirectory(module.id),
            system: system,
            perform: { [weak self] actionID, parameters, selection in
                self?.engine.handle(ActionRequest(moduleID: module.id, actionID: actionID, parameters: parameters,
                                                  selection: selection, origin: .host))
            },
            dismiss: dismiss
        )
    }

    /// Settings migration hook: records the version each module last ran with.
    private func migrateModuleVersions() {
        var changed = false
        var config = configuration
        for module in registry.modules {
            var state = config.state(for: module.manifest)
            let version = module.manifest.version.description
            if state.lastSeenVersion != version {
                // Unknown keys are kept (a newer schema may bring them back); removed keys are harmless.
                state.lastSeenVersion = version
                config.modules[module.id] = state
                changed = true
            }
        }
        if changed { save(config) }
    }

    // MARK: Menu

    func itemOverride(_ key: String) -> MenuItemOverride {
        configuration.menu.items[key] ?? MenuItemOverride()
    }

    func setItemOverride(_ key: String, _ override: MenuItemOverride) {
        mutate { $0.menu.items[key] = override.isEmpty ? nil : override }
    }

    func groupOverride(_ id: MenuGroupID) -> MenuGroupOverride {
        configuration.menu.groups[id.rawValue] ?? MenuGroupOverride()
    }

    func setGroupOverride(_ id: MenuGroupID, _ override: MenuGroupOverride) {
        mutate { $0.menu.groups[id.rawValue] = override }
    }

    func resetMenuCustomizations() {
        mutate { $0.menu = MenuPreferences() }
    }

    /// All actions of enabled modules, including hidden ones, for the menu manager.
    func allMenuActions() -> [(module: FinderPlusModule, action: ActionDescriptor)] {
        modules.filter(isEnabled).flatMap { module in
            module.menuActions(settings: settings(for: module))
                .filter { $0.presentation == .finderMenu }
                .map { (module, $0) }
        }
    }

    func republishNow() {
        snapshot = engine.publishMenuSnapshot()
        moduleRevision += 1
    }

    private func scheduleRepublish() {
        republishTask?.cancel()
        republishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.republishNow()
        }
    }

    // MARK: Configuration

    func mutate(_ change: (inout HostConfiguration) -> Void) {
        var config = configuration
        change(&config)
        save(config)
    }

    private func save(_ config: HostConfiguration) {
        do {
            try configurationStore.save(config)
            configuration = config
            tasks.historyLimit = config.general.taskHistoryLimit
            applyAppearance()
            scheduleRepublish()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func exportConfiguration(to url: URL) {
        do { try configurationStore.export(to: url) } catch { alertMessage = error.localizedDescription }
    }

    func importConfiguration(from url: URL) {
        do {
            configuration = try configurationStore.importConfiguration(from: url)
            applyAppearance()
            republishNow()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: Script packages

    private func loadScriptPackages() {
        let result = packageManager.loadInstalled()
        for package in result.packages {
            registry.register(ScriptPackageModule(package: package))
        }
        packageLoadFailures = result.failures.map { "\($0.folder): \($0.error.localizedDescription)" }
    }

    func inspectPackage(at folder: URL) throws -> ScriptPackage {
        try packageManager.inspect(folder)
    }

    /// Installs (or updates) a package the user reviewed, trusting exactly the reviewed content.
    func installTrusted(_ reviewed: ScriptPackage, enable: Bool) throws {
        let installed = try packageManager.install(from: reviewed.directory)
        guard installed.contentHash == reviewed.contentHash else {
            throw ScriptPackageError.invalidManifest("The package changed while it was being installed.")
        }
        registry.unregister(installed.manifest.id)
        registry.register(ScriptPackageModule(package: installed))
        mutate { config in
            config.trustedPackages[installed.manifest.id] = installed.contentHash
            var state = config.state(for: installed.manifest)
            state.enabled = enable
            config.modules[installed.manifest.id] = state
        }
        republishNow()
    }

    func uninstallPackage(_ module: FinderPlusModule, keepSettings: Bool) {
        do {
            try packageManager.uninstall(module.id)
            registry.unregister(module.id)
            mutate { config in
                config.trustedPackages[module.id] = nil
                if keepSettings {
                    config.modules[module.id]?.enabled = false
                } else {
                    config.modules[module.id] = nil
                    config.menu.items = config.menu.items.filter { !$0.key.hasPrefix(module.id + "/") }
                }
            }
            if !keepSettings {
                try? FileManager.default.trashItem(at: FinderPlusPaths.moduleDataDirectory(module.id), resultingItemURL: nil)
            }
            if selection == .module(module.id) { selection = .modules }
            republishNow()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: Dependencies

    func refreshDependencies() async {
        var result: [String: [DependencyStatus]] = [:]
        // Only enabled modules run code: a disabled (e.g. experimental) module must stay inert.
        for module in modules where isEnabled(module) {
            result[module.id] = await engine.dependencyStatuses(for: module)
        }
        dependencyStatuses = result
    }

    func missingRequiredDependencies(_ module: FinderPlusModule) -> [DependencyStatus] {
        (dependencyStatuses[module.id] ?? []).filter { $0.isRequired && $0.state == .missing }
    }

    // MARK: System integration

    func refreshExtensionStatus() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                alertMessage = error.localizedDescription
            }
            moduleRevision += 1
        }
    }

    // MARK: Appearance

    @ObservationIgnored private var appliedLanguage: String?

    func applyAppearance() {
        let appearanceSettings = registry.module(WellKnownModule.appearance).flatMap { module in
            configuration.isEnabled(module.manifest) ? configuration.settings(for: module.manifest) : nil
        }
        let theme = AppTheme(rawValue: appearanceSettings?.string(AppearanceSettingKey.theme) ?? "") ?? .system
        switch theme {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }

        let language = appearanceSettings?.string(AppearanceSettingKey.language) ?? "system"
        guard language != appliedLanguage else { return }
        appliedLanguage = language
        if language == "system" || language.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            LocalizedText.preferredLanguages = Locale.preferredLanguages
        } else {
            // Affects system-provided strings after a restart; FinderPlus' own strings switch immediately.
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
            LocalizedText.preferredLanguages = [language] + Locale.preferredLanguages
        }
        languageRevision += 1
    }
}
