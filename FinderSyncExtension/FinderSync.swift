import Cocoa
import FinderPlusCore
import FinderSync
import os

/// Finder Sync extension: builds the FinderPlus context menu and forwards clicks to the host app.
///
/// It deliberately knows nothing about individual modules. It reads the menu snapshot the host
/// publishes into the App Group container, evaluates its rules against the selection, and on click
/// writes an ``ActionRequest`` to the shared inbox. All work — including anything slow — happens
/// in the host app, so a failing action can never hang or crash Finder.
final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "io.github.finderplus", category: "finder-sync")
    private var snapshot = MenuSnapshot.empty
    private var snapshotModificationDate: Date?

    /// Items of the menu currently shown, keyed by `NSMenuItem.tag`. Finder copies the menu we
    /// return, so tags are the only reliable way to identify the clicked item.
    private var pendingItems: [Int: MenuSnapshot.Item] = [:]
    private var pendingSelection: FinderSelection?

    override init() {
        super.init()
        // Monitor every local and mounted volume so the menu is available everywhere.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes"),
        ]
        reloadSnapshotIfNeeded()
    }

    // MARK: Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let selection: FinderSelection
        switch menuKind {
        case .contextualMenuForItems:
            guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return nil }
            selection = .items(urls, container: controller.targetedURL())
        case .contextualMenuForContainer:
            guard let target = controller.targetedURL() else { return nil }
            selection = .container(target)
        default:
            return nil
        }

        reloadSnapshotIfNeeded()
        let resolved = MenuResolver.resolve(snapshot, for: selection)
        guard !resolved.isEmpty else { return nil }

        pendingItems.removeAll()
        pendingSelection = selection
        return makeMenu(resolved)
    }

    private func makeMenu(_ resolved: ResolvedMenu) -> NSMenu {
        let appearance = resolved.appearance
        let content = NSMenu(title: appearance.rootTitle)
        for (index, section) in resolved.sections.enumerated() {
            if index > 0 { content.addItem(.separator()) }
            switch section.group.presentation {
            case .inline:
                section.items.forEach { content.addItem(menuItem(for: $0, showIcon: appearance.showIcons)) }
            case .submenu:
                let parent = NSMenuItem(title: section.group.title, action: nil, keyEquivalent: "")
                parent.image = appearance.showIcons ? symbol(section.group.icon) : nil
                let submenu = NSMenu(title: section.group.title)
                section.items.forEach { submenu.addItem(menuItem(for: $0, showIcon: appearance.showIcons)) }
                parent.submenu = submenu
                content.addItem(parent)
            }
        }

        switch appearance.style {
        case .flat:
            return content
        case .submenu:
            let menu = NSMenu(title: "")
            let root = NSMenuItem(title: appearance.rootTitle, action: nil, keyEquivalent: "")
            root.image = appearance.showIcons ? symbol("puzzlepiece.extension") : nil
            root.submenu = content
            menu.addItem(root)
            return menu
        }
    }

    private func menuItem(for item: MenuSnapshot.Item, showIcon: Bool) -> NSMenuItem {
        let tag = pendingItems.count + 1
        pendingItems[tag] = item
        let menuItem = NSMenuItem(title: item.title, action: #selector(performAction(_:)), keyEquivalent: "")
        menuItem.tag = tag
        menuItem.image = showIcon ? symbol(item.icon) : nil
        return menuItem
    }

    private func symbol(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: Actions

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let item = pendingItems[sender.tag] else {
            logger.error("Unknown menu item tag \(sender.tag)")
            return
        }
        let selection = currentSelection() ?? pendingSelection ?? .empty
        let request = ActionRequest(moduleID: item.moduleID, actionID: item.actionID, parameters: item.parameters,
                                    selection: selection, origin: .finder)
        do {
            try RequestInbox().submit(request)
        } catch {
            logger.error("Could not write request: \(error.localizedDescription, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(FinderPlusURL.dispatch(request.id), configuration: configuration) { [logger] _, error in
            if let error {
                logger.error("Could not reach FinderPlus: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Finder also exposes the selection while an action runs; prefer it over the cached one.
    private func currentSelection() -> FinderSelection? {
        guard let pendingSelection else { return nil }
        let controller = FIFinderSyncController.default()
        switch pendingSelection.context {
        case .items:
            guard let urls = controller.selectedItemURLs(), !urls.isEmpty else { return nil }
            return .items(urls, container: controller.targetedURL())
        case .container:
            return controller.targetedURL().map { FinderSelection.container($0) }
        }
    }

    // MARK: Snapshot

    private func reloadSnapshotIfNeeded() {
        let url = FinderPlusPaths.menuSnapshotFile
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard modified != snapshotModificationDate else { return }
        do {
            let loaded = try MenuSnapshot.read(from: url)
            guard loaded.formatVersion <= MenuSnapshot.currentFormatVersion else {
                logger.error("Menu snapshot format \(loaded.formatVersion) is newer than this extension supports")
                return
            }
            snapshot = loaded
            snapshotModificationDate = modified
        } catch {
            logger.error("Could not read menu snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
