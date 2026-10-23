import FinderPlusCore
import Foundation

/// Block 07 — language, theme and Finder menu presentation. Has no Finder actions of its own;
/// the host reads these settings (keys in ``AppearanceSettingKey``) when it builds the menu
/// snapshot and when it applies the app theme and language.
public final class AppearanceModule: FinderPlusModule {
    public static let id = WellKnownModule.appearance

    public init() {}

    public let manifest = ModuleManifest(
        id: AppearanceModule.id,
        name: LocalizedText(en: "Appearance", zhHans: "个性化与外观", ko: "모양"),
        summary: LocalizedText(en: "Language, light/dark theme and how the FinderPlus menu looks in Finder.",
                               zhHans: "语言、浅色/深色主题，以及 FinderPlus 菜单在 Finder 中的呈现方式。",
                               ko: "언어, 라이트/다크 테마 및 Finder에서 FinderPlus 메뉴가 보이는 방식."),
        version: "1.0.0",
        icon: "paintbrush",
        category: .appearance,
        capabilities: ["host.appearance"],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "app", title: LocalizedText(en: "FinderPlus", zhHans: "FinderPlus", ko: "FinderPlus"), fields: [
                .choice(AppearanceSettingKey.language, LocalizedText(en: "Language", zhHans: "语言", ko: "언어"), options: [
                    SettingOption("system", LocalizedText(en: "Follow system", zhHans: "跟随系统", ko: "시스템 설정 따르기")),
                    SettingOption("zh-Hans", "简体中文"),
                    SettingOption("en", "English"),
                    SettingOption("ko", "한국어"),
                ], default: "system",
                        help: LocalizedText(en: "Takes full effect after restarting FinderPlus.", zhHans: "重新启动 FinderPlus 后完全生效。",
                                            ko: "FinderPlus를 다시 시작하면 완전히 적용됩니다.")),
                .choice(AppearanceSettingKey.theme, LocalizedText(en: "Theme", zhHans: "主题", ko: "테마"), options: [
                    SettingOption(AppTheme.system.rawValue, LocalizedText(en: "Follow system", zhHans: "跟随系统", ko: "시스템 설정 따르기")),
                    SettingOption(AppTheme.light.rawValue, LocalizedText(en: "Light", zhHans: "浅色", ko: "라이트")),
                    SettingOption(AppTheme.dark.rawValue, LocalizedText(en: "Dark", zhHans: "深色", ko: "다크")),
                ], default: AppTheme.system.rawValue),
            ]),
            SettingsSection(id: "menu", title: LocalizedText(en: "Finder menu", zhHans: "Finder 右键菜单", ko: "Finder 메뉴"), fields: [
                .text(AppearanceSettingKey.menuRootTitle, LocalizedText(en: "Menu title", zhHans: "菜单名称", ko: "메뉴 이름"), default: "FinderPlus"),
                .choice(AppearanceSettingKey.menuStyle, LocalizedText(en: "Layout", zhHans: "布局", ko: "레이아웃"), options: [
                    SettingOption(MenuStyle.submenu.rawValue, LocalizedText(en: "One “FinderPlus” submenu", zhHans: "统一的“FinderPlus”子菜单",
                                                                            ko: "하나의 “FinderPlus” 하위 메뉴")),
                    SettingOption(MenuStyle.flat.rawValue, LocalizedText(en: "Items directly in Finder’s menu", zhHans: "直接显示在 Finder 菜单中",
                                                                         ko: "Finder 메뉴에 바로 표시")),
                ], default: MenuStyle.submenu.rawValue),
                .toggle(AppearanceSettingKey.showMenuIcons, LocalizedText(en: "Show icons in menu items", zhHans: "菜单项显示图标", ko: "메뉴 항목에 아이콘 표시"),
                        default: true),
                .choice(AppearanceSettingKey.menuTitleStyle, LocalizedText(en: "Item names", zhHans: "菜单项命名", ko: "항목 이름"), options: [
                    SettingOption(MenuTitleStyle.full.rawValue, LocalizedText(en: "Descriptive (“Open with VS Code”)", zhHans: "完整（“使用 VS Code 打开”）",
                                                                              ko: "설명형(“VS Code로 열기”)")),
                    SettingOption(MenuTitleStyle.short.rawValue, LocalizedText(en: "Short (“VS Code”)", zhHans: "简短（“VS Code”）", ko: "짧게(“VS Code”)")),
                ], default: MenuTitleStyle.full.rawValue),
            ]),
        ]),
        permissions: []
    )

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        throw ModuleError.unknownAction(invocation.actionID)
    }
}
