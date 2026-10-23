import Foundation

/// How the FinderPlus entry appears in Finder's context menu.
public enum MenuStyle: String, Codable, Sendable, CaseIterable {
    /// One "FinderPlus" item with everything inside (default; keeps Finder's menu tidy).
    case submenu
    /// Items appear directly in Finder's context menu.
    case flat
}

/// Whether menu items use the full title ("Open with VS Code") or the short one ("VS Code").
public enum MenuTitleStyle: String, Codable, Sendable, CaseIterable {
    case full, short
}

/// Menu-wide presentation preferences (owned by the Appearance module's settings).
public struct MenuAppearance: Codable, Hashable, Sendable {
    public var rootTitle: String
    public var style: MenuStyle
    public var showIcons: Bool
    public var titleStyle: MenuTitleStyle

    public init(rootTitle: String = "FinderPlus", style: MenuStyle = .submenu, showIcons: Bool = true,
                titleStyle: MenuTitleStyle = .full) {
        self.rootTitle = rootTitle
        self.style = style
        self.showIcons = showIcons
        self.titleStyle = titleStyle
    }
}

/// Compiled, ready-to-evaluate menu written by the host and read by the Finder extension.
///
/// The extension never loads module code: it only evaluates the rules in this file against the
/// current selection. Enabling, disabling or reconfiguring a module rewrites the snapshot.
public struct MenuSnapshot: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public struct Group: Codable, Hashable, Sendable, Identifiable {
        public var id: MenuGroupID
        public var title: String
        public var icon: String?
        public var order: Int
        public var presentation: MenuGroupCatalog.Presentation

        public init(id: MenuGroupID, title: String, icon: String?, order: Int, presentation: MenuGroupCatalog.Presentation) {
            self.id = id
            self.title = title
            self.icon = icon
            self.order = order
            self.presentation = presentation
        }
    }

    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public var moduleID: String
        public var actionID: String
        public var title: String
        public var icon: String?
        public var group: MenuGroupID
        public var order: Int
        public var rule: MenuRule
        public var parameters: [String: String]

        public var id: String { ActionDescriptor.key(moduleID: moduleID, actionID: actionID) }

        public init(moduleID: String, actionID: String, title: String, icon: String?, group: MenuGroupID, order: Int,
                    rule: MenuRule, parameters: [String: String]) {
            self.moduleID = moduleID
            self.actionID = actionID
            self.title = title
            self.icon = icon
            self.group = group
            self.order = order
            self.rule = rule
            self.parameters = parameters
        }
    }

    public var formatVersion: Int
    public var generatedAt: Date
    public var appearance: MenuAppearance
    public var groups: [Group]
    public var items: [Item]

    public init(formatVersion: Int = MenuSnapshot.currentFormatVersion, generatedAt: Date = Date(),
                appearance: MenuAppearance, groups: [Group], items: [Item]) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.appearance = appearance
        self.groups = groups
        self.items = items
    }

    public static let empty = MenuSnapshot(appearance: MenuAppearance(), groups: [], items: [])

    public func write(to url: URL = FinderPlusPaths.menuSnapshotFile) throws {
        try FinderPlusJSON.write(self, to: url, pretty: false)
    }

    public static func read(from url: URL = FinderPlusPaths.menuSnapshotFile) throws -> MenuSnapshot {
        try FinderPlusJSON.read(MenuSnapshot.self, from: url)
    }
}

/// The actions one enabled module contributes, already computed from its current settings.
public struct ModuleMenuContribution: Sendable {
    public var moduleID: String
    public var actions: [ActionDescriptor]

    public init(moduleID: String, actions: [ActionDescriptor]) {
        self.moduleID = moduleID
        self.actions = actions
    }
}

/// Builds a ``MenuSnapshot`` from module contributions and the user's menu preferences.
public enum MenuSnapshotBuilder {
    public static func build(
        contributions: [ModuleMenuContribution],
        preferences: MenuPreferences,
        appearance: MenuAppearance,
        languages: [String] = LocalizedText.preferredLanguages
    ) -> MenuSnapshot {
        var items: [MenuSnapshot.Item] = []
        for contribution in contributions {
            for action in contribution.actions where action.presentation == .finderMenu {
                let key = ActionDescriptor.key(moduleID: contribution.moduleID, actionID: action.id)
                let override = preferences.items[key] ?? MenuItemOverride()
                if override.hidden { continue }
                let defaultTitle: LocalizedText
                if appearance.titleStyle == .short, let shortTitle = action.shortTitle {
                    defaultTitle = shortTitle
                } else {
                    defaultTitle = action.title
                }
                let customTitle = override.title?.trimmingCharacters(in: .whitespaces)
                items.append(MenuSnapshot.Item(
                    moduleID: contribution.moduleID,
                    actionID: action.id,
                    title: (customTitle?.isEmpty == false ? customTitle! : defaultTitle.resolved(preferredLanguages: languages)),
                    icon: action.icon,
                    group: override.group ?? action.group,
                    order: override.order ?? action.order,
                    rule: action.rule,
                    parameters: action.parameters
                ))
            }
        }

        let usedGroups = Set(items.map(\.group))
        var groups: [MenuSnapshot.Group] = []
        for groupID in usedGroups {
            let entry = MenuGroupCatalog.entry(for: groupID)
            let override = preferences.groups[groupID.rawValue] ?? MenuGroupOverride()
            if override.hidden { continue }
            let customTitle = override.title?.trimmingCharacters(in: .whitespaces)
            groups.append(MenuSnapshot.Group(
                id: groupID,
                title: customTitle?.isEmpty == false ? customTitle! : entry.title.resolved(preferredLanguages: languages),
                icon: entry.icon,
                order: override.order ?? entry.order,
                presentation: override.presentation ?? entry.presentation
            ))
        }
        groups.sort { ($0.order, $0.id) < ($1.order, $1.id) }
        let visibleGroups = Set(groups.map(\.id))
        items = items.filter { visibleGroups.contains($0.group) }
        items.sort { ($0.order, $0.title) < ($1.order, $1.title) }

        return MenuSnapshot(appearance: appearance, groups: groups, items: items)
    }
}

/// A menu resolved for one concrete selection.
public struct ResolvedMenu: Hashable, Sendable {
    public struct Section: Hashable, Sendable, Identifiable {
        public var group: MenuSnapshot.Group
        public var items: [MenuSnapshot.Item]
        public var id: MenuGroupID { group.id }
    }

    public var appearance: MenuAppearance
    public var sections: [Section]

    public var isEmpty: Bool { sections.isEmpty }
    public var allItems: [MenuSnapshot.Item] { sections.flatMap(\.items) }
}

public enum MenuResolver {
    /// Filters and groups snapshot items for `selection`. Pure and cheap: runs on every right-click.
    public static func resolve(_ snapshot: MenuSnapshot, for selection: FinderSelection) -> ResolvedMenu {
        let matching = snapshot.items.filter { $0.rule.matches(selection) }
        let byGroup = Dictionary(grouping: matching, by: \.group)
        let sections = snapshot.groups.compactMap { group -> ResolvedMenu.Section? in
            guard let items = byGroup[group.id], !items.isEmpty else { return nil }
            return ResolvedMenu.Section(group: group, items: items)
        }
        return ResolvedMenu(appearance: snapshot.appearance, sections: sections)
    }
}
