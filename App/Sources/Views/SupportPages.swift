import AppKit
import ApplicationServices
import FinderPlusCore
import FinderPlusEngine
import FinderPlusUI
import SwiftUI
import UniformTypeIdentifiers

/// "Templates" and "Icons" pages: every enabled module that provides a library view for the section.
struct LibraryPage: View {
    @Environment(AppModel.self) private var model
    let section: ModuleLibrarySection

    var body: some View {
        let providers = model.modules.filter { model.isEnabled($0) && ($0 as? ModuleLibraryProviding)?.librarySection == section }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if providers.isEmpty {
                    ContentUnavailableView(HostStrings.noLibraryProviders.localized, systemImage: "tray")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
                ForEach(providers, id: \.id) { module in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(module.manifest.name.localized, systemImage: module.manifest.icon).font(.headline)
                            (module as? ModuleLibraryProviding)?.makeLibraryView(context: model.uiContext(for: module))
                        }
                        .padding(6)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(section == .templates ? HostStrings.templates.localized : HostStrings.icons.localized)
    }
}

struct DependenciesView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshing = false
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            if !model.fixableDependencies.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HostStrings.setUpAllTitle.localized).font(.headline)
                            Text(model.fixableDependencies.map { "\($0.module.manifest.name.localized): \($0.status.displayName)" }
                                .joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(HostStrings.setUpAll.localized) { model.installAllMissingDependencies() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section(HostStrings.systemIntegration.localized) {
                statusRow(HostStrings.finderExtension.localized, ok: model.extensionEnabled,
                          detail: model.extensionEnabled ? nil : HostStrings.extensionHelp.localized) {
                    Button(HostStrings.openSettings.localized) { model.openExtensionSettings() }
                }
                statusRow(HostStrings.accessibility.localized, ok: accessibilityTrusted,
                          detail: HostStrings.accessibilityHelp.localized) {
                    Button(HostStrings.openSettings.localized) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            ForEach(model.modules.filter { model.isEnabled($0) }, id: \.id) { module in
                let statuses = model.dependencyStatuses[module.id] ?? []
                if !statuses.isEmpty {
                    Section(module.manifest.name.localized) {
                        ForEach(statuses) { status in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: status.state.symbol).foregroundStyle(status.state.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(status.displayName)
                                        if !status.isRequired { Badge(text: HostStrings.optional.localized) }
                                    }
                                    if let detail = status.detail { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                    if case .warning(let warning) = status.state { Text(warning).font(.caption).foregroundStyle(.orange) }
                                    if !status.isSatisfied, let hint = status.installHint {
                                        Text(hint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                                Spacer()
                                if let fix = status.fixActionID {
                                    Button(status.isSatisfied ? HostStrings.update.localized : HostStrings.setUpOneClick.localized) {
                                        model.engine.runHostAction(moduleID: module.id, actionID: fix)
                                        model.selection = .tasks
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ExtensionDiagnosticsSection()
        }
        .formStyle(.grouped)
        .navigationTitle(HostStrings.dependencies.localized)
        .toolbar {
            ToolbarItem {
                Button { Task { await refresh() } } label: { Label(HostStrings.refresh.localized, systemImage: "arrow.clockwise") }
                    .disabled(refreshing)
            }
        }
        // Also re-check when an installer task finishes.
        .task(id: model.tasks.running.count) { await refresh() }
    }

    private func refresh() async {
        refreshing = true
        accessibilityTrusted = AXIsProcessTrusted()
        model.refreshExtensionStatus()
        await model.refreshDependencies()
        refreshing = false
    }

    private func statusRow<Accessory: View>(_ title: String, ok: Bool, detail: String?, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !ok { accessory() }
        }
    }
}

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var showQuickActions = false

    var body: some View {
        let records = showQuickActions ? model.tasks.records : model.tasks.visible
        List {
            if records.isEmpty {
                Text(HostStrings.noTasksYet.localized).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                TaskRow(record: record)
            }
        }
        .navigationTitle(HostStrings.taskCenter.localized)
        .toolbar {
            ToolbarItem {
                Toggle(HostStrings.showQuickActions.localized, isOn: $showQuickActions)
            }
            ToolbarItem {
                Button { model.tasks.clearFinished() } label: { Label(HostStrings.clearFinished.localized, systemImage: "trash") }
            }
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let general = model.configuration.general
        Form {
            Section(HostStrings.startup.localized) {
                Toggle(HostStrings.launchAtLogin.localized, isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                    .id(model.moduleRevision)
                Toggle(HostStrings.keepRunning.localized, isOn: Binding(
                    get: { general.keepRunningInBackground },
                    set: { value in model.mutate { $0.general.keepRunningInBackground = value } }
                ))
                Text(HostStrings.keepRunningHelp.localized).font(.caption).foregroundStyle(.secondary)
            }
            Section(HostStrings.safety.localized) {
                Toggle(HostStrings.confirmDangerous.localized, isOn: Binding(
                    get: { general.confirmDangerousActions },
                    set: { value in model.mutate { $0.general.confirmDangerousActions = value } }
                ))
                Toggle(HostStrings.notifyOnCompletion.localized, isOn: Binding(
                    get: { general.notifyOnTaskCompletion },
                    set: { value in model.mutate { $0.general.notifyOnTaskCompletion = value } }
                ))
                Stepper(value: Binding(
                    get: { general.taskHistoryLimit },
                    set: { value in model.mutate { $0.general.taskHistoryLimit = value } }
                ), in: 20...2000, step: 20) {
                    LabeledContent(HostStrings.taskHistoryLimit.localized, value: "\(general.taskHistoryLimit)")
                }
            }
            Section(HostStrings.appearanceAndLanguage.localized) {
                Button(HostStrings.openAppearanceSettings.localized) { model.selection = .module(WellKnownModule.appearance) }
                    .buttonStyle(.link)
            }
            Section(HostStrings.finderExtension.localized) {
                LabeledContent(HostStrings.status.localized,
                               value: model.extensionEnabled ? HostStrings.enabled.localized : HostStrings.disabled.localized)
                Button(HostStrings.openExtensionSettings.localized) { model.openExtensionSettings() }
            }
            Section(HostStrings.backupAndMigration.localized) {
                HStack {
                    Button(HostStrings.exportConfiguration.localized) { exportConfiguration() }
                    Button(HostStrings.importConfiguration.localized) { importConfiguration() }
                }
                Text(HostStrings.migrationHelp.localized).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(HostStrings.openDataFolder.localized) {
                        NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(FinderPlusPaths.hostDataRoot))
                    }
                    Button(HostStrings.openSharedFolder.localized) {
                        NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(FinderPlusPaths.sharedRoot))
                    }
                }
            }
            Section(HostStrings.about.localized) {
                LabeledContent(HostStrings.version.localized, value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent(HostStrings.architecture.localized, value: Self.architecture)
                Text(HostStrings.aboutText.localized).font(.callout).foregroundStyle(.secondary)
                if let link = Bundle.main.object(forInfoDictionaryKey: "FPProjectURL") as? String, let url = URL(string: link),
                   !link.isEmpty {
                    Link(link, destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(HostStrings.general.localized)
    }

    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FinderPlus Configuration.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { model.exportConfiguration(to: url) }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { model.importConfiguration(from: url) }
    }
}

/// What Finder recently asked the Finder extension, to diagnose locations without a menu.
private struct ExtensionDiagnosticsSection: View {
    @State private var diagnostics = ExtensionDiagnostics()
    @State private var copied = false

    var body: some View {
        Section {
            Text(HostStrings.diagnosticsHelp.localized).font(.caption).foregroundStyle(.secondary)
            if diagnostics.events.isEmpty {
                Text(HostStrings.diagnosticsEmpty.localized).foregroundStyle(.secondary)
            }
            ForEach(diagnostics.events.suffix(15).reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.date.formatted(date: .omitted, time: .standard))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Badge(text: event.kind, color: event.kind == "error" ? .red : .secondary)
                    Text(event.detail).font(.caption).textSelection(.enabled).lineLimit(3)
                }
            }
            HStack {
                Button(copied ? HostStrings.copied.localized : HostStrings.copyDiagnostics.localized) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(diagnosticsReport, forType: .string)
                    copied = true
                }
                Button(HostStrings.clear.localized) {
                    ExtensionDiagnostics.clear()
                    diagnostics = ExtensionDiagnostics()
                }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
        } header: {
            Text(HostStrings.diagnostics.localized)
        }
        .onAppear(perform: reload)
    }

    private var diagnosticsReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return """
        FinderPlus \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Shared folder: \(FinderPlusPaths.sharedRoot.path)
        Cloud folders: \(CloudStorageLocations.discover().joined(separator: ", "))
        \(diagnostics.report)
        """
    }

    private func reload() {
        diagnostics = ExtensionDiagnostics.load()
        copied = false
    }
}
