import AppKit
import FinderPlusCore
import FinderPlusUI
import SwiftUI

/// Block 06 — custom SF Symbol icons for folders in Finder's sidebar.
///
/// **Experimental**: relies on an undocumented row property and a deprecated list API (see
/// `SidebarBackend`), so it is disabled by default, isolated in its own target, resolves the API
/// at run time and backs up Finder's sidebar data before changing it. It never moves rows.
public final class SidebarModule: FinderPlusModule {
    public static let id = "io.github.finderplus.sidebar"

    public init() {}

    public let manifest = ModuleManifest(
        id: SidebarModule.id,
        name: LocalizedText(en: "Finder Sidebar Icons", zhHans: "Finder 侧边栏图标", ko: "Finder 사이드바 아이콘"),
        summary: LocalizedText(en: "Give folders in Finder's sidebar their own SF Symbol icons — including iCloud Drive and OneDrive folders.",
                               zhHans: "为 Finder 侧边栏中的文件夹设置 SF Symbols 图标，支持 iCloud 云盘与 OneDrive 等云盘文件夹。",
                               ko: "Finder 사이드바의 폴더에 SF Symbols 아이콘을 지정합니다. iCloud Drive와 OneDrive 폴더도 지원합니다."),
        version: "0.2.0",
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
            ActionDescriptor(id: "setIcon",
                             title: LocalizedText(en: "Sidebar Icon…", zhHans: "设置侧边栏图标…", ko: "사이드바 아이콘…"),
                             icon: "sidebar.left", group: .sidebar, order: 10,
                             rule: .folders(includeContainer: true, max: 1),
                             execution: .interactive(route: "editor")),
        ]
    }

    public func dependencyStatuses(settings: ModuleSettings, checker: DependencyChecking) async -> [DependencyStatus] {
        let name = LocalizedText(en: "Sidebar list API", zhHans: "侧边栏列表接口", ko: "사이드바 목록 API").localized
        guard let backend = SidebarBackend() else {
            return [DependencyStatus(id: "lssharedfilelist", displayName: name, state: .missing,
                                     installHint: SidebarBackendError.unavailable.localizedDescription)]
        }
        do {
            let count = try backend.rows().count
            return [DependencyStatus(id: "lssharedfilelist", displayName: name,
                                     state: .warning(SidebarText.undocumented.localized), detail: "\(count) items")]
        } catch {
            return [DependencyStatus(id: "lssharedfilelist", displayName: name, state: .missing, installHint: error.localizedDescription)]
        }
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        throw ModuleError.unknownAction(invocation.actionID)
    }
}

extension SidebarModule: ModuleSettingsViewProviding, ModuleInteractiveUIProviding {
    public var replacesGeneratedSettings: Bool { true }

    @MainActor
    public func makeSettingsView(context: ModuleUIContext) -> AnyView {
        AnyView(SidebarFavoritesView(context: context))
    }

    @MainActor
    public func makeInteractiveView(route: String, context: ModuleUIContext) -> AnyView? {
        let folder = context.selection.folders.first?.url ?? context.selection.container
        return AnyView(SidebarIconEditor(context: context, initialPath: folder?.path, initialSymbol: nil, offersRestart: true,
                                         onDone: { context.dismiss() }))
    }
}

enum SidebarText {
    static let title = LocalizedText(en: "Sidebar Favorites", zhHans: "侧边栏收藏", ko: "사이드바 즐겨찾기")
    static let undocumented = LocalizedText(en: "Undocumented API — changes are backed up first.", zhHans: "未公开接口——修改前会先备份。",
                                            ko: "비공개 API — 변경 전에 백업합니다.")
    static let inSidebar = LocalizedText(en: "In Sidebar", zhHans: "在侧边栏", ko: "사이드바에 있음")
    static let disabled = LocalizedText(en: "Disabled", zhHans: "已停用", ko: "사용 안 함")
    static let restartNeeded = LocalizedText(en: "Finder shows some of the new icons only after it restarts.",
                                             zhHans: "部分新图标需要重启 Finder 后才会显示。",
                                             ko: "일부 새 아이콘은 Finder를 다시 시작한 후에 표시됩니다.")
    static let restartFinder = LocalizedText(en: "Restart Finder", zhHans: "重启 Finder", ko: "Finder 다시 시작")
    static let otherRows = LocalizedText(en: "Other folders in the sidebar", zhHans: "侧边栏中的其他文件夹", ko: "사이드바의 다른 폴더")
    static let setIcon = LocalizedText(en: "Set Icon…", zhHans: "设置图标…", ko: "아이콘 설정…")
    static let byOtherApp = LocalizedText(en: "Icon set by SidebarFavorites", zhHans: "图标由 SidebarFavorites 设置", ko: "SidebarFavorites가 설정한 아이콘")
    static let refresh = LocalizedText(en: "Refresh", zhHans: "刷新", ko: "새로 고침")
    static let edit = LocalizedText(en: "Edit…", zhHans: "编辑…", ko: "편집…")
    static let delete = LocalizedText(en: "Remove", zhHans: "移除", ko: "제거")
    static let showInFinder = LocalizedText(en: "Show in Finder", zhHans: "在 Finder 中显示", ko: "Finder에서 보기")
    static let empty = LocalizedText(en: "No favorites yet. Click + to add a folder with an icon, or give a folder below its own icon.",
                                     zhHans: "还没有收藏。点击 + 添加文件夹并设置图标，或为下方已有的文件夹设置图标。",
                                     ko: "즐겨찾기가 없습니다. +를 눌러 폴더를 추가하거나 아래 폴더에 아이콘을 지정하세요.")
    static let footer = LocalizedText(
        en: "Icons are monochrome SF Symbols, as Finder draws all sidebar icons. They stay after FinderPlus quits. Removing a favorite deletes the row only if FinderPlus added it; otherwise the folder's original icon comes back.",
        zhHans: "图标为单色 SF Symbols（Finder 侧边栏图标都是单色）。FinderPlus 退出后图标依然保留。移除收藏时，只会删除 FinderPlus 自己添加的行；原本就在侧边栏的文件夹只恢复原图标。",
        ko: "아이콘은 단색 SF Symbols입니다. FinderPlus가 종료되어도 유지됩니다. 즐겨찾기를 제거하면 FinderPlus가 추가한 행만 삭제되고, 원래 있던 폴더는 아이콘만 복원됩니다.")
    static let backups = LocalizedText(en: "Backups", zhHans: "备份", ko: "백업")
    static let restore = LocalizedText(en: "Restore", zhHans: "恢复", ko: "복원")
}

/// Module page: the favorites with their icons, like the SidebarFavorites app (no reordering).
struct SidebarFavoritesView: View {
    let context: ModuleUIContext
    @State private var favorites: [SidebarFavorite] = []
    @State private var rows: [SidebarRow] = []
    @State private var needsRestart = false
    @State private var message: String?
    @State private var editing: EditorTarget?
    @State private var backups: [SidebarBackupStore.Backup] = []

    struct EditorTarget: Identifiable {
        var id = UUID()
        var path: String?
        var symbol: String?
    }

    private var coordinator: SidebarIconCoordinator { SidebarIconCoordinator(dataDirectory: context.dataDirectory) }

    private var otherRows: [SidebarRow] {
        rows.filter { row in
            !row.isSpecial && row.path != nil && !favorites.contains { SidebarBackend.samePath(row.path, $0.path) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(SidebarText.title.localized).font(.title3.bold())
                Spacer()
                Button { editing = EditorTarget() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .help(SidebarText.setIcon.localized)
            }

            if needsRestart {
                HStack {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(.orange)
                    Text(SidebarText.restartNeeded.localized).font(.callout)
                    Spacer()
                    Button(SidebarText.restartFinder.localized) {
                        SidebarIconCoordinator.restartFinder()
                        needsRestart = false
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            VStack(spacing: 0) {
                if favorites.isEmpty {
                    Text(SidebarText.empty.localized).foregroundStyle(.secondary).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(favorites) { favorite in
                    favoriteRow(favorite)
                    if favorite.id != favorites.last?.id { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            if !otherRows.isEmpty {
                Text(SidebarText.otherRows.localized).font(.headline).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(otherRows) { row in
                        otherRow(row)
                        if row.id != otherRows.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }

            Text(SidebarText.footer.localized).font(.caption).foregroundStyle(.secondary)

            if let message { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }

            HStack {
                DisclosureGroup(SidebarText.backups.localized) {
                    ForEach(backups) { backup in
                        HStack {
                            Text(backup.url.lastPathComponent).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Button(SidebarText.restore.localized) { restore(backup) }.controlSize(.small)
                        }
                    }
                }
                .font(.caption)
                Spacer()
                Button { perform { try coordinator.refresh() } } label: {
                    Label(SidebarText.refresh.localized, systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { perform { try coordinator.refresh() } }
        .sheet(item: $editing) { target in
            SidebarIconEditor(context: context, initialPath: target.path, initialSymbol: target.symbol) {
                editing = nil
                reloadFromDisk()
            }
        }
    }

    private func favoriteRow(_ favorite: SidebarFavorite) -> some View {
        let shown = favorite.enabled && rows.contains { SidebarBackend.samePath($0.path, favorite.path) && $0.iconCode == favorite.code }
        return HStack(spacing: 12) {
            SymbolTile(symbol: favorite.symbol, dimmed: !favorite.enabled)
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name).font(.body.weight(.semibold))
                Text(abbreviated(favorite.path)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(shown ? Color.green : Color.secondary).frame(width: 7, height: 7)
                Text(shown ? SidebarText.inSidebar.localized : SidebarText.disabled.localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(get: { favorite.enabled },
                                     set: { value in perform { try coordinator.setEnabled(favorite.id, value) } }))
                .toggleStyle(.switch)
                .labelsHidden()
            Menu {
                Button(SidebarText.edit.localized) { editing = EditorTarget(path: favorite.path, symbol: favorite.symbol) }
                Button(SidebarText.showInFinder.localized) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: favorite.path)])
                }
                Divider()
                Button(SidebarText.delete.localized, role: .destructive) { perform { try coordinator.delete(favorite.id) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = EditorTarget(path: favorite.path, symbol: favorite.symbol) }
    }

    private func otherRow(_ row: SidebarRow) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.path ?? "/"))
                .resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name.isEmpty ? (row.url?.lastPathComponent ?? "") : row.name)
                Text(abbreviated(row.path ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if SidebarIconCode.isSidebarFavoritesCode(row.iconCode) {
                    Text(SidebarText.byOtherApp.localized).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(SidebarText.setIcon.localized) { editing = EditorTarget(path: row.path, symbol: nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func abbreviated(_ path: String) -> String {
        NSString(string: path).abbreviatingWithTildeInPath
    }

    private func perform(_ change: () throws -> SidebarIconCoordinator.Result) {
        do {
            let result = try change()
            favorites = result.favorites
            rows = result.rows
            needsRestart = needsRestart || result.needsFinderRestart
            message = nil
        } catch {
            message = error.localizedDescription
            reloadFromDisk()
        }
        backups = coordinator.backups.backups()
    }

    private func reloadFromDisk() {
        favorites = coordinator.store.load()
        rows = (try? SidebarBackend()?.rows()) ?? rows
        if let state = SidebarEditorState.lastResult {
            needsRestart = needsRestart || state
            SidebarEditorState.lastResult = nil
        }
        backups = coordinator.backups.backups()
    }

    private func restore(_ backup: SidebarBackupStore.Backup) {
        let alert = NSAlert()
        alert.messageText = LocalizedText(en: "Restore this backup?", zhHans: "恢复此备份？", ko: "이 백업을 복원할까요?").localized
        alert.informativeText = LocalizedText(en: "Finder will restart. The current state is backed up first.",
                                              zhHans: "Finder 将会重新启动。恢复前会先备份当前状态。",
                                              ko: "Finder가 다시 시작됩니다. 현재 상태를 먼저 백업합니다.").localized
        alert.addButton(withTitle: SidebarText.restore.localized)
        alert.addButton(withTitle: LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try coordinator.backups.restore(backup)
        } catch {
            message = error.localizedDescription
        }
        reloadFromDisk()
    }
}

/// Passes "Finder needs a restart" from the editor sheet back to the list.
@MainActor
enum SidebarEditorState {
    static var lastResult: Bool?
}

/// The symbol in a rounded tile, as in the favorites list.
struct SymbolTile: View {
    let symbol: String
    var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.accentColor.opacity(dimmed ? 0.06 : 0.14))
            .frame(width: 34, height: 34)
            .overlay(
                Image(systemName: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "folder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(dimmed ? Color.secondary : Color.accentColor)
            )
    }
}

/// Add or edit a favorite: folder + SF Symbol, with a preview of the sidebar row.
struct SidebarIconEditor: View {
    let context: ModuleUIContext
    let initialPath: String?
    let initialSymbol: String?
    /// Opened from Finder's menu (no list page to show a banner): ask about restarting Finder directly.
    var offersRestart = false
    let onDone: () -> Void

    @State private var path = ""
    @State private var symbol = "folder"
    @State private var search = ""
    @State private var error: String?

    static let quickPicks = [
        "folder", "star", "heart", "flag", "bookmark", "tag", "pin", "bolt", "flame", "leaf",
        "doc.text", "doc.richtext", "book", "books.vertical", "graduationcap", "text.book.closed", "newspaper",
        "hammer", "wrench.and.screwdriver", "gearshape", "terminal", "chevron.left.forwardslash.chevron.right", "cpu",
        "briefcase", "building.2", "chart.bar", "chart.pie", "dollarsign.circle", "cart", "creditcard",
        "photo", "camera", "film", "music.note", "mic", "paintbrush", "paintpalette", "pencil.and.ruler",
        "person", "person.2", "house", "globe", "airplane", "car", "map",
        "tray.full", "archivebox", "shippingbox", "externaldrive", "icloud", "cloud", "arrow.down.circle",
        "lock", "key", "shield", "checkmark.seal", "exclamationmark.triangle", "clock", "calendar",
        "atom", "function", "testtube.2", "brain", "lightbulb", "puzzlepiece", "gamecontroller", "sparkles",
    ]

    private var symbolIsValid: Bool { NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil }

    private var filtered: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Self.quickPicks }
        var result = Self.quickPicks.filter { $0.contains(query) }
        if NSImage(systemSymbolName: query, accessibilityDescription: nil) != nil, !result.contains(query) {
            result.insert(query, at: 0)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SidebarText.setIcon.localized).font(.title3.bold())

            LabeledContent(LocalizedText(en: "Folder", zhHans: "文件夹", ko: "폴더").localized) {
                HStack {
                    TextField("", text: $path, prompt: Text("~/Documents/Project"))
                        .textFieldStyle(.roundedBorder)
                    Button(LocalizedText(en: "Choose…", zhHans: "选择…", ko: "선택…").localized) {
                        if let url = OpenPanel.chooseFolder() { path = url.path }
                    }
                }
            }

            LabeledContent("SF Symbol") {
                HStack {
                    TextField("", text: $symbol, prompt: Text("hammer.fill"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Image(systemName: symbolIsValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(symbolIsValid ? .green : .red)
                }
            }

            TextField(LocalizedText(en: "Search symbols (or type any SF Symbol name)", zhHans: "搜索符号（也可直接输入任意 SF Symbol 名称）",
                                    ko: "기호 검색(또는 SF Symbol 이름 입력)").localized, text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 6)], spacing: 6) {
                    ForEach(filtered, id: \.self) { name in
                        Button { symbol = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 17))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(symbol == name ? Color.accentColor.opacity(0.25) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 190)

            // Preview of the sidebar row.
            HStack(spacing: 8) {
                Image(systemName: symbolIsValid ? symbol : "folder").foregroundStyle(Color.accentColor).frame(width: 18)
                Text(path.isEmpty ? "Folder" : URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).lastPathComponent)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
            .frame(width: 220)

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button(LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(LocalizedText(en: "Save", zhHans: "保存", ko: "저장").localized) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty || !symbolIsValid)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            path = initialPath ?? ""
            symbol = initialSymbol ?? "folder"
        }
    }

    private func save() {
        let expanded = NSString(string: path.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = LocalizedText(en: "Choose an existing folder.", zhHans: "请选择一个已存在的文件夹。", ko: "기존 폴더를 선택하세요.").localized
            return
        }
        do {
            let result = try SidebarIconCoordinator(dataDirectory: context.dataDirectory).upsert(path: expanded, symbol: symbol)
            SidebarEditorState.lastResult = result.needsFinderRestart
            if offersRestart, result.needsFinderRestart {
                let alert = NSAlert()
                alert.messageText = SidebarText.restartNeeded.localized
                alert.addButton(withTitle: SidebarText.restartFinder.localized)
                alert.addButton(withTitle: LocalizedText(en: "Later", zhHans: "稍后", ko: "나중에").localized)
                if alert.runModal() == .alertFirstButtonReturn { SidebarIconCoordinator.restartFinder() }
            }
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
