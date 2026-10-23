import FinderPlusCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FinderPlus").font(.largeTitle.bold())
                    Text(HostStrings.tagline.localized).foregroundStyle(.secondary)
                }

                extensionCard

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(HostStrings.dashboardModules.localized).font(.headline)
                            Text("\(model.modules.filter { model.isEnabled($0) }.count) / \(model.modules.count)")
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button(HostStrings.moduleCenter.localized) { model.selection = .modules }.buttonStyle(.link)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 8) {
                            ForEach(model.modules, id: \.id) { module in
                                DashboardModuleTile(module: module)
                            }
                        }
                    }
                    .padding(6)
                }

                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(HostStrings.recentTasks.localized).font(.headline)
                            Spacer()
                            Button(HostStrings.showAll.localized) { model.selection = .tasks }.buttonStyle(.link)
                        }
                        let recent = Array(model.tasks.records.prefix(6))
                        if recent.isEmpty {
                            Text(HostStrings.noTasksYet.localized).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(recent) { record in
                            TaskRow(record: record, showsLog: false)
                            if record.id != recent.last?.id { Divider() }
                        }
                    }
                    .padding(6)
                }
            }
            .padding(24)
        }
        .navigationTitle(HostStrings.overview.localized)
        .onAppear { model.refreshExtensionStatus() }
    }

    private var extensionCard: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: model.extensionEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(model.extensionEnabled ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.extensionEnabled ? HostStrings.extensionOn.localized : HostStrings.extensionOff.localized)
                        .font(.headline)
                    Text(HostStrings.extensionHelp.localized).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(HostStrings.openExtensionSettings.localized) { model.openExtensionSettings() }
            }
            .padding(6)
        }
    }

}

/// One module on the home dashboard: icon, name, on/off switch; clicking opens its page.
private struct DashboardModuleTile: View {
    @Environment(AppModel.self) private var model
    let module: FinderPlusModule

    var body: some View {
        let manifest = module.manifest
        let enabled = model.isEnabled(module)
        HStack(spacing: 10) {
            Button { model.selection = .module(module.id) } label: {
                HStack(spacing: 10) {
                    ModuleIconView(symbol: manifest.icon, size: 28, tint: enabled ? manifest.category.tint : .gray)
                    Text(manifest.name.localized)
                        .foregroundStyle(enabled ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { model.isEnabled(module) },
                set: { newValue in
                    // Experimental modules are switched on from their own page, which explains the risk.
                    if newValue, manifest.stability == .experimental {
                        model.selection = .module(module.id)
                    } else {
                        model.setEnabled(module, newValue)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(manifest.kind == .scriptPackage && !model.isTrusted(module))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}
