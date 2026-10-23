import FinderPlusCore
import FinderPlusUI
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    sidebarRow(.overview, HostStrings.overview, "square.grid.2x2")
                    sidebarRow(.modules, HostStrings.moduleCenter, "puzzlepiece.extension")
                    sidebarRow(.menu, HostStrings.menuManager, "contextualmenu.and.cursorarrow")
                    sidebarRow(.templates, HostStrings.templates, "doc.on.doc")
                    sidebarRow(.icons, HostStrings.icons, "paintpalette")
                    sidebarRow(.dependencies, HostStrings.dependencies, "shippingbox")
                    sidebarRow(.tasks, HostStrings.taskCenter, "list.bullet.clipboard")
                    sidebarRow(.general, HostStrings.general, "gearshape")
                }
                Section(HostStrings.moduleSettings.localized) {
                    ForEach(model.modules.filter { model.isEnabled($0) }, id: \.id) { module in
                        Label(module.manifest.name.localized, systemImage: module.manifest.icon)
                            .tag(SidebarSection.module(module.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
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
