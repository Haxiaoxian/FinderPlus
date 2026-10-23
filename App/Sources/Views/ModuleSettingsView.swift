import FinderPlusCore
import FinderPlusEngine
import FinderPlusUI
import SwiftUI

/// A module's page, laid out like a PowerToys utility page: header, an "Enable" switch, then the
/// module's settings (dimmed while the module is off).
struct ModuleSettingsView: View {
    @Environment(AppModel.self) private var model
    let module: FinderPlusModule
    @State private var confirmReset = false
    @State private var confirmExperimental = false

    private var manifest: ModuleManifest { module.manifest }
    private var isPackage: Bool { manifest.kind == .scriptPackage }

    var body: some View {
        let settings = model.settingsBinding(for: module)
        let custom = module as? ModuleSettingsViewProviding
        let enabled = model.isEnabled(module)
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ModuleIconView(symbol: manifest.icon, size: 56, tint: manifest.category.tint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(manifest.name.localized).font(.largeTitle.bold())
                        Text(manifest.summary.localized).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Badge(text: isPackage ? HostStrings.scriptPackage.localized : HostStrings.builtIn.localized,
                                  color: isPackage ? .purple : .blue)
                            if manifest.stability == .experimental { Badge(text: HostStrings.experimental.localized, color: .orange) }
                            Badge(text: "v\(manifest.version.description)")
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Toggle(isOn: Binding(get: { model.isEnabled(module) }, set: setEnabled)) {
                    HStack(spacing: 10) {
                        Image(systemName: "power").foregroundStyle(enabled ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HostStrings.enableModule.replacing("name", with: manifest.name.localized).localized)
                                .font(.headline)
                            if !enabled {
                                Text(HostStrings.moduleOffHint.localized).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(isPackage && !model.isTrusted(module))
                if manifest.stability == .experimental {
                    Label(HostStrings.experimentalNotice.localized, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Group {
                if !(custom?.replacesGeneratedSettings ?? false) {
                    SchemaForm(schema: manifest.settings, settings: settings)
                }

                if let custom {
                    Section {
                        custom.makeSettingsView(context: model.uiContext(for: module))
                    }
                }

                let actions = module.menuActions(settings: settings.wrappedValue).filter { $0.presentation == .finderMenu }
                if !actions.isEmpty {
                    Section(HostStrings.menuItems.localized) {
                        ForEach(actions) { action in
                            HStack {
                                Image(systemName: action.icon ?? "circle").frame(width: 20)
                                Text(action.title.localized)
                                Spacer()
                                Text(RuleDescription.describe(action.rule)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button(HostStrings.customizeInMenuManager.localized) { model.selection = .menu }
                            .buttonStyle(.link)
                    }
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.55)

            Section(HostStrings.about.localized) {
                LabeledContent(HostStrings.identifier.localized, value: manifest.id)
                LabeledContent(HostStrings.version.localized, value: manifest.version.description)
                LabeledContent(HostStrings.kind.localized,
                               value: isPackage ? HostStrings.scriptPackage.localized : HostStrings.builtIn.localized)
                LabeledContent(HostStrings.permissions.localized,
                               value: manifest.permissions.map { $0.title.localized }.joined(separator: ", "))
                Button(HostStrings.resetSettings.localized, role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(manifest.name.localized)
        .confirmationDialog(HostStrings.resetSettings.localized, isPresented: $confirmReset) {
            Button(HostStrings.resetSettings.localized, role: .destructive) { model.resetSettings(module) }
        }
        .confirmationDialog(HostStrings.enableExperimentalTitle.localized, isPresented: $confirmExperimental) {
            Button(HostStrings.enable.localized) { model.setEnabled(module, true) }
        } message: {
            Text(HostStrings.enableExperimentalMessage.localized)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled, manifest.stability == .experimental {
            confirmExperimental = true
        } else {
            model.setEnabled(module, enabled)
        }
    }
}
