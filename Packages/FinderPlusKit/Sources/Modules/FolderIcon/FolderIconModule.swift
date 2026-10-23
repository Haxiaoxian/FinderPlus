import AppKit
import FinderPlusCore
import FinderPlusUI
import SwiftUI

/// Block 05 — custom folder icons through the public `NSWorkspace.setIcon` API, with history and restore.
public final class FolderIconModule: FinderPlusModule {
    public static let id = "io.github.finderplus.folder-icon"

    enum Key {
        static let recentSpecs = "recentSpecs"
        static let showRecentInMenu = "showRecentInMenu"
    }

    public let iconPacksDirectory: URL

    public init(iconPacksDirectory: URL = FinderPlusPaths.iconPacksDirectory) {
        self.iconPacksDirectory = iconPacksDirectory
    }

    public let manifest = ModuleManifest(
        id: FolderIconModule.id,
        name: LocalizedText(en: "Folder Icons", zhHans: "文件夹图标", ko: "폴더 아이콘"),
        summary: LocalizedText(en: "Color folders, add emblems or use your own images. Every change can be undone.",
                               zhHans: "为文件夹设置颜色、徽标或自定义图片，所有修改均可恢复。",
                               ko: "폴더에 색상, 엠블럼 또는 사용자 이미지를 적용합니다. 모든 변경은 되돌릴 수 있습니다."),
        version: "1.0.0",
        icon: "folder.badge.gearshape",
        category: .finder,
        capabilities: ["finder.menu", "host.interactive-ui", "library.icons"],
        supportedTypes: ["folder"],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "menu", title: LocalizedText(en: "Menu", zhHans: "菜单", ko: "메뉴"), fields: [
                .toggle(Key.showRecentInMenu, LocalizedText(en: "Offer recently used icons in the Finder menu", zhHans: "在右键菜单中提供最近使用的图标",
                                                            ko: "Finder 메뉴에 최근 사용 아이콘 표시"), default: true),
            ]),
        ]),
        permissions: [.readSelection, .modifyFinder]
    )

    func recentSpecs(settings: ModuleSettings) -> [FolderIconSpec] {
        settings[Key.recentSpecs].arrayValue?.compactMap { try? $0.decode(FolderIconSpec.self) } ?? []
    }

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        var actions = [
            ActionDescriptor(id: "choose", title: LocalizedText(en: "Set Folder Icon…", zhHans: "设置文件夹图标…", ko: "폴더 아이콘 설정…"),
                             icon: "paintpalette", group: .folder, order: 10, rule: .folders(),
                             execution: .interactive(route: "picker")),
            ActionDescriptor(id: "restore", title: LocalizedText(en: "Restore Default Icon", zhHans: "恢复默认图标", ko: "기본 아이콘으로 복원"),
                             icon: "arrow.uturn.backward", group: .folder, order: 30, rule: .folders(), execution: .immediate),
        ]
        if settings[Key.showRecentInMenu].boolValue ?? true {
            for (index, spec) in recentSpecs(settings: settings).prefix(3).enumerated() {
                actions.append(ActionDescriptor(
                    id: "recent.\(index)",
                    title: LocalizedText(en: "Apply Recent: {name}", zhHans: "应用最近：{name}", ko: "최근 항목 적용: {name}")
                        .replacing("name", with: spec.displayName),
                    icon: spec.symbol ?? "photo", group: .folder, order: 20 + index, rule: .folders(), execution: .immediate,
                    parameters: ["recent": String(index)]
                ))
            }
        }
        return actions
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let folders = invocation.selection.folders.map(\.url)
        guard !folders.isEmpty else { throw ModuleError.invalidSelection("Select folders.") }
        let history = FolderIconHistory(directory: try context.ensuredDataDirectory())
        switch invocation.actionID {
        case "restore":
            for folder in folders {
                try await history.apply(nil, image: nil, to: folder)
            }
            return .message(LocalizedText(en: "Restored \(folders.count) folder(s).", zhHans: "已恢复 \(folders.count) 个文件夹。",
                                          ko: "폴더 \(folders.count)개를 복원했습니다.").localized)
        case _ where invocation.parameters["recent"] != nil:
            let index = Int(invocation.parameters["recent"] ?? "") ?? 0
            let recents = recentSpecs(settings: invocation.settings)
            guard index < recents.count else { throw ModuleError.unknownAction(invocation.actionID) }
            try await Self.apply(recents[index], to: folders, history: history)
            return .message(LocalizedText(en: "Icon applied.", zhHans: "图标已应用。", ko: "아이콘을 적용했습니다.").localized)
        default:
            throw ModuleError.unknownAction(invocation.actionID)
        }
    }

    @MainActor
    static func apply(_ spec: FolderIconSpec, to folders: [URL], history: FolderIconHistory) throws {
        guard let image = FolderIconRenderer.image(for: spec, size: 1024) else {
            throw ModuleError.failed(LocalizedText(en: "Cannot load the icon image.", zhHans: "无法加载图标图片。",
                                                   ko: "아이콘 이미지를 불러올 수 없습니다.").localized)
        }
        for folder in folders {
            try history.apply(spec, image: image, to: folder)
        }
    }

    /// Keeps the three most recent distinct specs in settings so the menu can offer them.
    static func remember(_ spec: FolderIconSpec, in settings: inout ModuleSettings) {
        var recents = settings[Key.recentSpecs].arrayValue?.compactMap { try? $0.decode(FolderIconSpec.self) } ?? []
        recents.removeAll { $0 == spec }
        recents.insert(spec, at: 0)
        settings[Key.recentSpecs] = .array(recents.prefix(3).compactMap { try? SettingValue(encoding: $0) })
    }

    /// Images found in icon packs: `IconPacks/<pack>/*.{png,icns,jpg,heic,tiff}`.
    struct IconPackImage: Hashable {
        var pack: String
        var url: URL
    }

    func iconPackImages() -> [IconPackImage] {
        let fileManager = FileManager.default
        let packs = (try? fileManager.contentsOfDirectory(at: iconPacksDirectory, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
        let allowed: Set<String> = ["png", "icns", "jpg", "jpeg", "heic", "tiff", "tif"]
        var result: [IconPackImage] = []
        for pack in packs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let files = (try? fileManager.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where allowed.contains(file.pathExtension.lowercased()) {
                result.append(IconPackImage(pack: pack.lastPathComponent, url: file))
            }
        }
        return result
    }
}

extension FolderIconModule: ModuleInteractiveUIProviding, ModuleLibraryProviding {
    @MainActor
    public func makeInteractiveView(route: String, context: ModuleUIContext) -> AnyView? {
        guard route == "picker" else { return nil }
        return AnyView(FolderIconPickerView(module: self, context: context))
    }

    public var librarySection: ModuleLibrarySection { .icons }

    @MainActor
    public func makeLibraryView(context: ModuleUIContext) -> AnyView {
        AnyView(FolderIconLibraryView(module: self, context: context))
    }
}
