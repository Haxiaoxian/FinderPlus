import AppKit
import FinderPlusCore
import FinderPlusEngine
import FinderPlusUI
import SwiftUI

struct ModuleCenterView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewing: ScriptPackage?
    @State private var category: ModuleCategory?

    private var visibleModules: [FinderPlusModule] {
        model.modules.filter { category == nil || $0.manifest.category == category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(HostStrings.category.localized, selection: $category) {
                    Text(HostStrings.all.localized).tag(ModuleCategory?.none)
                    ForEach(ModuleCategory.allCases, id: \.self) { category in
                        Text(category.title.localized).tag(ModuleCategory?.some(category))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(visibleModules, id: \.id) { module in
                        ModuleCard(module: module, onReview: review)
                    }
                }

                let problems = model.packageLoadFailures + model.registry.rejected.map { "\($0.id): \($0.reason)" }
                if !problems.isEmpty {
                    GroupBox(HostStrings.loadProblems.localized) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(problems, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(HostStrings.moduleCenter.localized)
        .toolbar {
            ToolbarItem {
                Button { importPackage() } label: { Label(HostStrings.importPackage.localized, systemImage: "square.and.arrow.down") }
                    .help(HostStrings.importPackageHelp.localized)
            }
            ToolbarItem {
                Button { NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(FinderPlusPaths.packagesDirectory)) } label: {
                    Label(HostStrings.openPackagesFolder.localized, systemImage: "folder")
                }
            }
        }
        .sheet(item: Binding(get: { reviewing.map(ReviewItem.init) }, set: { reviewing = $0?.package })) { item in
            PackageReviewSheet(package: item.package)
        }
    }

    private func importPackage() {
        guard let folder = OpenPanel.chooseFolder() else { return }
        review(folder)
    }

    private func review(_ folder: URL) {
        do {
            reviewing = try model.inspectPackage(at: folder)
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }
}

private struct ReviewItem: Identifiable {
    let package: ScriptPackage
    var id: String { package.contentHash }
}

struct ModuleCard: View {
    @Environment(AppModel.self) private var model
    let module: FinderPlusModule
    let onReview: (URL) -> Void
    @State private var confirmExperimental = false
    @State private var confirmUninstall = false

    private var manifest: ModuleManifest { module.manifest }
    private var isPackage: Bool { manifest.kind == .scriptPackage }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    ModuleIconView(symbol: manifest.icon, size: 40, tint: manifest.category.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(manifest.name.localized).font(.headline)
                        Text("v\(manifest.version.description) · \(manifest.author.isEmpty ? "—" : manifest.author)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.isEnabled(module) }, set: setEnabled))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(isPackage && !model.isTrusted(module))
                }

                Text(manifest.summary.localized)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)

                HStack(spacing: 6) {
                    Badge(text: isPackage ? HostStrings.scriptPackage.localized : HostStrings.builtIn.localized,
                          color: isPackage ? .purple : .blue)
                    if manifest.stability == .experimental { Badge(text: HostStrings.experimental.localized, color: .orange) }
                    if manifest.stability == .beta { Badge(text: "Beta", color: .orange) }
                    if isPackage, !model.isTrusted(module) { Badge(text: HostStrings.untrusted.localized, color: .red) }
                    if !model.missingRequiredDependencies(module).isEmpty {
                        Badge(text: HostStrings.missingDependency.localized, color: .red)
                    }
                    Spacer()
                    ForEach(manifest.permissions.filter(\.isSensitive), id: \.self) { permission in
                        Image(systemName: permissionSymbol(permission))
                            .foregroundStyle(.secondary)
                            .help(permission.title.localized)
                    }
                }

                HStack {
                    Button(HostStrings.settings.localized) { model.selection = .module(module.id) }
                        .disabled(!model.isEnabled(module))
                    if isPackage {
                        if !model.isTrusted(module), let package = module as? ScriptPackageModule {
                            Button(HostStrings.review.localized) { onReview(package.package.directory) }
                        }
                        Button(HostStrings.update.localized) {
                            if let folder = OpenPanel.chooseFolder() { onReview(folder) }
                        }
                        Spacer()
                        Button(HostStrings.uninstall.localized, role: .destructive) { confirmUninstall = true }
                    } else {
                        Spacer()
                    }
                }
                .controlSize(.small)
            }
            .padding(6)
        }
        .confirmationDialog(HostStrings.enableExperimentalTitle.localized, isPresented: $confirmExperimental) {
            Button(HostStrings.enable.localized) { model.setEnabled(module, true) }
        } message: {
            Text(HostStrings.enableExperimentalMessage.localized)
        }
        .confirmationDialog(HostStrings.uninstallTitle.localized, isPresented: $confirmUninstall) {
            Button(HostStrings.uninstallKeepSettings.localized) { model.uninstallPackage(module, keepSettings: true) }
            Button(HostStrings.uninstallRemoveAll.localized, role: .destructive) { model.uninstallPackage(module, keepSettings: false) }
        } message: {
            Text(manifest.name.localized)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled, manifest.stability == .experimental {
            confirmExperimental = true
        } else {
            model.setEnabled(module, enabled)
        }
    }

    private func permissionSymbol(_ permission: ModulePermission) -> String {
        switch permission {
        case .readSelection: return "eye"
        case .writeFiles: return "square.and.pencil"
        case .runProcesses: return "terminal"
        case .appleEvents: return "applescript"
        case .accessibility: return "accessibility"
        case .network: return "network"
        case .modifyFinder: return "macwindow"
        case .privateSystemData: return "exclamationmark.lock"
        }
    }
}

/// Trust review shown before a script package is installed or updated.
struct PackageReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let package: ScriptPackage
    @State private var enableAfterInstall = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ModuleIconView(symbol: package.manifest.icon, size: 44, tint: .purple)
                VStack(alignment: .leading) {
                    Text(package.manifest.name.localized).font(.title2.bold())
                    Text("\(package.manifest.id) · v\(package.manifest.version.description) · \(package.manifest.author)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Label(HostStrings.reviewWarning.localized, systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)

            Form {
                Section(HostStrings.source.localized) {
                    LabeledContent(HostStrings.folder.localized, value: package.directory.path)
                    LabeledContent("SHA-256", value: String(package.contentHash.prefix(16)) + "…")
                    LabeledContent(HostStrings.files.localized, value: "\(package.files.count)")
                }
                Section(HostStrings.permissions.localized) {
                    ForEach(package.manifest.permissions, id: \.self) { permission in
                        Label(permission.title.localized, systemImage: permission.isSensitive ? "exclamationmark.circle" : "circle")
                            .foregroundStyle(permission.isSensitive ? .orange : .primary)
                    }
                }
                Section(HostStrings.commands.localized) {
                    ForEach(package.manifest.actions) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title.localized).font(.body.weight(.medium))
                            Text(RuleDescription.describe(action.rule)).font(.caption).foregroundStyle(.secondary)
                            if let command = package.commands[action.id] {
                                Text(command.displayCommand)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 280)

            Toggle(HostStrings.enableAfterInstall.localized, isOn: $enableAfterInstall)
            HStack {
                Button(HostStrings.showFiles.localized) { NSWorkspace.shared.open(package.directory) }
                Spacer()
                Button(HostStrings.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(HostStrings.trustAndInstall.localized) {
                    do {
                        try model.installTrusted(package, enable: enableAfterInstall)
                        dismiss()
                    } catch {
                        model.alertMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}
