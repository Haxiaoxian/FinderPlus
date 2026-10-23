import AppKit
import FinderPlusCore
import FinderPlusUI
import SwiftUI

/// Block 06 — manage Finder sidebar favorites. **Experimental**: relies on a deprecated,
/// undocumented API, so it is disabled by default, isolated in its own target, resolves the API at
/// runtime, verifies every change and backs up Finder's data file before writing.
public final class SidebarModule: FinderPlusModule {
    public static let id = "io.github.finderplus.sidebar"

    public init() {}

    public let manifest = ModuleManifest(
        id: SidebarModule.id,
        name: LocalizedText(en: "Finder Sidebar", zhHans: "Finder 侧边栏", ko: "Finder 사이드바"),
        summary: LocalizedText(en: "Add, remove and reorder Finder sidebar favorites, with automatic backups.",
                               zhHans: "添加、移除和排序 Finder 侧边栏收藏，并自动备份。",
                               ko: "Finder 사이드바 즐겨찾기를 추가, 제거, 정렬하며 자동으로 백업합니다."),
        version: "0.1.0",
        icon: "sidebar.left",
        category: .finder,
        stability: .experimental,
        capabilities: ["finder.menu", "settings.custom-view", "host.interactive-ui"],
        supportedTypes: ["folder"],
        permissions: [.readSelection, .modifyFinder, .privateSystemData],
        enabledByDefault: false
    )

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        [
            ActionDescriptor(id: "add", title: LocalizedText(en: "Add to Sidebar", zhHans: "添加到侧边栏", ko: "사이드바에 추가"),
                             icon: "sidebar.left", group: .sidebar, order: 10, rule: .folders(includeContainer: true, max: 10)),
            ActionDescriptor(id: "remove", title: LocalizedText(en: "Remove from Sidebar", zhHans: "从侧边栏移除", ko: "사이드바에서 제거"),
                             icon: "minus.circle", group: .sidebar, order: 20, rule: .folders(includeContainer: true, max: 10),
                             requiresConfirmation: true,
                             confirmationMessage: LocalizedText(en: "Remove the selected folders from Finder’s sidebar? A backup is made first.",
                                                                zhHans: "确定从 Finder 侧边栏移除所选文件夹吗？操作前会自动备份。",
                                                                ko: "선택한 폴더를 Finder 사이드바에서 제거할까요? 먼저 백업합니다.")),
            ActionDescriptor(id: "manage", title: LocalizedText(en: "Manage Sidebar Favorites…", zhHans: "管理侧边栏收藏…", ko: "사이드바 즐겨찾기 관리…"),
                             icon: "list.bullet", group: .sidebar, order: 30, rule: .folders(includeContainer: true, max: 1),
                             execution: .interactive(route: "manager")),
        ]
    }

    public func dependencyStatuses(settings: ModuleSettings, checker: DependencyChecking) async -> [DependencyStatus] {
        let name = LocalizedText(en: "Sidebar list API", zhHans: "侧边栏列表接口", ko: "사이드바 목록 API").localized
        guard let backend = SidebarBackend() else {
            return [DependencyStatus(id: "lssharedfilelist", displayName: name, state: .missing,
                                     installHint: SidebarBackendError.unavailable.localizedDescription)]
        }
        do {
            let count = try backend.items().count
            return [DependencyStatus(id: "lssharedfilelist", displayName: name,
                                     state: .warning(LocalizedText(en: "Undocumented API — changes are verified and backed up.",
                                                                   zhHans: "未公开接口——所有修改都会校验并备份。",
                                                                   ko: "비공개 API — 변경 사항은 검증 및 백업됩니다.").localized),
                                     detail: "\(count) items", isRequired: true)]
        } catch {
            return [DependencyStatus(id: "lssharedfilelist", displayName: name, state: .missing, installHint: error.localizedDescription)]
        }
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        guard let backend = SidebarBackend() else { throw SidebarBackendError.unavailable }
        let store = SidebarBackupStore(directory: try context.ensuredDataDirectory().appendingPathComponent("Backups", isDirectory: true))
        let folders = invocation.selection.targetURLs.filter { SelectedItem.inspect($0).kind == .folder }
        switch invocation.actionID {
        case "add":
            try store.createBackup(reason: "before-add")
            for folder in folders { try backend.add(folder) }
            return .message(LocalizedText(en: "Added to the sidebar.", zhHans: "已添加到侧边栏。", ko: "사이드바에 추가했습니다.").localized)
        case "remove":
            try store.createBackup(reason: "before-remove")
            for folder in folders { try backend.remove(folder) }
            return .message(LocalizedText(en: "Removed from the sidebar.", zhHans: "已从侧边栏移除。", ko: "사이드바에서 제거했습니다.").localized)
        default:
            throw ModuleError.unknownAction(invocation.actionID)
        }
    }
}

extension SidebarModule: ModuleSettingsViewProviding, ModuleInteractiveUIProviding {
    public var replacesGeneratedSettings: Bool { true }

    @MainActor
    public func makeSettingsView(context: ModuleUIContext) -> AnyView {
        AnyView(SidebarManagerView(context: context))
    }

    @MainActor
    public func makeInteractiveView(route: String, context: ModuleUIContext) -> AnyView? {
        AnyView(SidebarManagerView(context: context).padding().frame(minWidth: 520, minHeight: 480))
    }
}

struct SidebarManagerView: View {
    let context: ModuleUIContext
    @State private var items: [SidebarItem] = []
    @State private var backups: [SidebarBackupStore.Backup] = []
    @State private var message: String?
    @State private var available = true

    private var store: SidebarBackupStore {
        SidebarBackupStore(directory: context.dataDirectory.appendingPathComponent("Backups", isDirectory: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(LocalizedText(en: "Experimental: uses an undocumented macOS interface. FinderPlus backs up Finder’s sidebar data before every change.",
                                zhHans: "实验性功能：使用了未公开的 macOS 接口。每次修改前 FinderPlus 都会备份侧边栏数据。",
                                ko: "실험적 기능: 비공개 macOS 인터페이스를 사용합니다. 변경 전마다 사이드바 데이터를 백업합니다.").localized,
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)

            if !available {
                Text(SidebarBackendError.unavailable.localizedDescription).foregroundStyle(.red)
            }

            List {
                Section(LocalizedText(en: "Favorites", zhHans: "个人收藏", ko: "즐겨찾기").localized) {
                    ForEach(items) { item in
                        HStack {
                            if let url = item.url {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "star").frame(width: 18)
                            }
                            VStack(alignment: .leading) {
                                Text(item.name)
                                if let url = item.url {
                                    Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Button { perform { try $0.move(from: item.index, to: item.index - 1) } } label: { Image(systemName: "arrow.up") }
                                .disabled(item.index == 0)
                            Button { perform { try $0.move(from: item.index, to: item.index + 1) } } label: { Image(systemName: "arrow.down") }
                                .disabled(item.index >= items.count - 1)
                            if let url = item.url {
                                Button { perform { try $0.remove(url) } } label: { Image(systemName: "minus.circle") }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section(LocalizedText(en: "Custom sidebar icons", zhHans: "自定义侧边栏图标", ko: "사용자 지정 사이드바 아이콘").localized) {
                    Text(LocalizedText(en: "Not available yet: macOS has no supported way to set sidebar icons. This will ship as a separate experimental backend once it can be done safely.",
                                       zhHans: "暂不可用：macOS 没有受支持的设置侧边栏图标方式。待能安全实现后，将以独立的实验性后端提供。",
                                       ko: "아직 사용할 수 없음: macOS에는 사이드바 아이콘을 설정하는 공식 방법이 없습니다. 안전하게 구현되면 별도의 실험적 백엔드로 제공됩니다.").localized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(LocalizedText(en: "Backups", zhHans: "备份", ko: "백업").localized) {
                    ForEach(backups) { backup in
                        HStack {
                            Text(backup.url.lastPathComponent).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(LocalizedText(en: "Restore", zhHans: "恢复", ko: "복원").localized) { restore(backup) }
                        }
                    }
                }
            }
            .frame(minHeight: 280)

            HStack {
                Button(LocalizedText(en: "Add Folder…", zhHans: "添加文件夹…", ko: "폴더 추가…").localized) {
                    if let url = OpenPanel.chooseFolder() { perform { try $0.add(url) } }
                }
                Button(LocalizedText(en: "Back Up Now", zhHans: "立即备份", ko: "지금 백업").localized) {
                    do { try store.createBackup(reason: "manual"); reload() } catch { message = error.localizedDescription }
                }
                Button(LocalizedText(en: "Show Backups", zhHans: "显示备份", ko: "백업 보기").localized) {
                    NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(store.directory))
                }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        guard let backend = SidebarBackend() else {
            available = false
            return
        }
        items = (try? backend.items()) ?? []
        backups = store.backups()
    }

    private func perform(_ change: (SidebarBackend) throws -> Void) {
        guard let backend = SidebarBackend() else {
            available = false
            return
        }
        do {
            try store.createBackup(reason: "before-edit")
            try change(backend)
            message = nil
        } catch {
            message = error.localizedDescription
        }
        reload()
    }

    private func restore(_ backup: SidebarBackupStore.Backup) {
        let alert = NSAlert()
        alert.messageText = LocalizedText(en: "Restore this backup?", zhHans: "恢复此备份？", ko: "이 백업을 복원할까요?").localized
        alert.informativeText = LocalizedText(en: "Finder will restart. The current state is backed up first.",
                                              zhHans: "Finder 将会重新启动。恢复前会先备份当前状态。",
                                              ko: "Finder가 다시 시작됩니다. 현재 상태를 먼저 백업합니다.").localized
        alert.addButton(withTitle: LocalizedText(en: "Restore", zhHans: "恢复", ko: "복원").localized)
        alert.addButton(withTitle: LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.restore(backup)
            message = LocalizedText(en: "Restored.", zhHans: "已恢复。", ko: "복원했습니다.").localized
        } catch {
            message = error.localizedDescription
        }
        reload()
    }
}
