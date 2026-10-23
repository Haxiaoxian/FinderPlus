import FinderPlusCore
import FinderPlusUI
import SwiftUI

struct ModuleSettingsView: View {
    @Environment(AppModel.self) private var model
    let module: FinderPlusModule
    @State private var confirmReset = false

    private var manifest: ModuleManifest { module.manifest }

    var body: some View {
        let settings = model.settingsBinding(for: module)
        let custom = module as? ModuleSettingsViewProviding
        Form {
            Section {
                HStack(spacing: 14) {
                    ModuleIconView(symbol: manifest.icon, size: 48, tint: manifest.category.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manifest.name.localized).font(.title2.bold())
                        Text(manifest.summary.localized).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(HostStrings.enabled.localized, isOn: Binding(get: { model.isEnabled(module) },
                                                                       set: { model.setEnabled(module, $0) }))
                        .toggleStyle(.switch)
                }
                if manifest.stability == .experimental {
                    Label(HostStrings.experimentalNotice.localized, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

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

            Section(HostStrings.about.localized) {
                LabeledContent(HostStrings.identifier.localized, value: manifest.id)
                LabeledContent(HostStrings.version.localized, value: manifest.version.description)
                LabeledContent(HostStrings.kind.localized,
                               value: manifest.kind == .native ? HostStrings.builtIn.localized : HostStrings.scriptPackage.localized)
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
    }
}
