import FinderPlusCore
import FinderPlusUI
import SwiftUI

/// Sidebar layout modeled on PowerToys: Home and General at the top, every module under one
/// collapsible "Modules" group (enabled or not), and the cross-module tools under "Manage".
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sidebar.modulesExpanded") private var modulesExpanded = true
    @AppStorage("sidebar.manageExpanded") private var manageExpanded = true

    /// Modules in category order, then by name, so related modules sit together.
    private var sortedModules: [FinderPlusModule] {
        let order = Dictionary(uniqueKeysWithValues: ModuleCategory.allCases.enumerated().map { ($1, $0) })
        return model.modules.sorted {
            let lhs = (order[$0.manifest.category] ?? 99, $0.manifest.name.localized)
            let rhs = (order[$1.manifest.category] ?? 99, $1.manifest.name.localized)
            return lhs < rhs
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    sidebarRow(.overview, HostStrings.overview, "house")
                    sidebarRow(.general, HostStrings.general, "gearshape")
                }

                Section(HostStrings.modulesSection.localized, isExpanded: $modulesExpanded) {
                    ForEach(sortedModules, id: \.id) { module in
                        ModuleSidebarRow(module: module, enabled: model.isEnabled(module))
                            .tag(SidebarSection.module(module.id))
                    }
                }

                Section(HostStrings.manageSection.localized, isExpanded: $manageExpanded) {
                    sidebarRow(.modules, HostStrings.moduleCenter, "puzzlepiece.extension")
                    sidebarRow(.menu, HostStrings.menuManager, "contextualmenu.and.cursorarrow")
                    sidebarRow(.templates, HostStrings.templates, "doc.on.doc")
                    sidebarRow(.icons, HostStrings.icons, "paintpalette")
                    sidebarRow(.dependencies, HostStrings.dependencies, "shippingbox")
                    sidebarRow(.tasks, HostStrings.taskCenter, "list.bullet.clipboard")
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .id(model.languageRevision)
        .alert(HostStrings.error.localized, isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button(HostStrings.ok.localized) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private func sidebarRow(_ section: SidebarSection, _ title: LocalizedText, _ symbol: String) -> some View {
        Label(title.localized, systemImage: symbol).tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection ?? .overview {
        case .overview: OverviewView()
        case .modules: ModuleCenterView()
        case .menu: MenuManagerView()
        case .module(let id):
            if let module = model.module(id) {
                ModuleSettingsView(module: module)
                    .id(id)
            } else {
                ContentUnavailableView(HostStrings.moduleMissing.localized, systemImage: "puzzlepiece")
            }
        case .templates: LibraryPage(section: .templates)
        case .icons: LibraryPage(section: .icons)
        case .dependencies: DependenciesView()
        case .tasks: TasksView()
        case .general: GeneralSettingsView()
        }
    }
}

/// A module in the sidebar; switched-off modules stay listed (like PowerToys) but dimmed.
private struct ModuleSidebarRow: View {
    let module: FinderPlusModule
    let enabled: Bool

    var body: some View {
        HStack {
            Label(module.manifest.name.localized, systemImage: module.manifest.icon)
                .foregroundStyle(enabled ? .primary : .secondary)
            Spacer(minLength: 4)
            if !enabled {
                Text(HostStrings.moduleOff.localized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
