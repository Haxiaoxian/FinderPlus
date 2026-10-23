import Foundation

/// Identifiers the host needs to know about. Kept to a minimum: only modules whose settings
/// influence host-wide behavior (menu appearance, language, theme) are referenced by the host.
public enum WellKnownModule {
    public static let appearance = "io.github.finderplus.appearance"
}

/// Setting keys of the Appearance module, read by the host when it builds the menu snapshot and
/// applies the theme/language.
public enum AppearanceSettingKey {
    public static let language = "language"
    public static let theme = "theme"
    public static let menuRootTitle = "menuRootTitle"
    public static let menuStyle = "menuStyle"
    public static let showMenuIcons = "showMenuIcons"
    public static let menuTitleStyle = "menuTitleStyle"
}

public enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

extension MenuAppearance {
    /// Reads menu appearance from the Appearance module's settings (defaults when disabled).
    public init(appearanceSettings settings: ModuleSettings?) {
        guard let settings else {
            self.init()
            return
        }
        let title = settings.nonEmptyString(AppearanceSettingKey.menuRootTitle) ?? "FinderPlus"
        self.init(
            rootTitle: title,
            style: MenuStyle(rawValue: settings.string(AppearanceSettingKey.menuStyle)) ?? .submenu,
            showIcons: settings[AppearanceSettingKey.showMenuIcons].boolValue ?? true,
            titleStyle: MenuTitleStyle(rawValue: settings.string(AppearanceSettingKey.menuTitleStyle)) ?? .full
        )
    }
}
