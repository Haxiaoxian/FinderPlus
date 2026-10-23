import XCTest
@testable import FinderPlusCore

final class LocalizedTextTests: XCTestCase {
    let text = LocalizedText(en: "Copy", zhHans: "复制", ko: "복사")

    func testResolvesRegionalVariants() {
        XCTAssertEqual(text.resolved(preferredLanguages: ["zh-Hans-CN"]), "复制")
        XCTAssertEqual(text.resolved(preferredLanguages: ["zh-CN"]), "复制")
        XCTAssertEqual(text.resolved(preferredLanguages: ["ko-KR"]), "복사")
        XCTAssertEqual(text.resolved(preferredLanguages: ["fr-FR", "ko"]), "복사")
        XCTAssertEqual(text.resolved(preferredLanguages: ["de"]), "Copy")
    }

    func testTraditionalChineseDoesNotPickSimplified() {
        XCTAssertEqual(text.resolved(preferredLanguages: ["zh-Hant-TW"]), "Copy")
        XCTAssertEqual(text.resolved(preferredLanguages: ["zh-TW"]), "Copy")
    }

    func testDecodesStringOrDictionary() throws {
        let plain = try JSONDecoder().decode(LocalizedText.self, from: Data(#""Hello""#.utf8))
        XCTAssertEqual(plain.translations, ["en": "Hello"])
        let dict = try JSONDecoder().decode(LocalizedText.self, from: Data(#"{"en":"Hi","ko":"안녕"}"#.utf8))
        XCTAssertEqual(dict.resolved(preferredLanguages: ["ko"]), "안녕")
    }

    func testPlaceholderReplacement() {
        let title = LocalizedText(en: "Open with {app}", zhHans: "使用 {app} 打开").replacing("app", with: "VS Code")
        XCTAssertEqual(title.resolved(preferredLanguages: ["zh-Hans"]), "使用 VS Code 打开")
    }
}

final class SettingValueTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let value: SettingValue = ["flag": true, "count": 3, "ratio": 0.5, "name": "x", "list": ["a", "b"]]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(SettingValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testTypedDecoding() throws {
        struct Preset: Codable, Equatable { var name: String; var quality: Double }
        let value = try SettingValue(encoding: Preset(name: "Web", quality: 0.7))
        XCTAssertEqual(try value.decode(Preset.self), Preset(name: "Web", quality: 0.7))
    }

    func testModuleSettingsFallsBackToDefaults() {
        let schema = SettingsSchema(sections: [SettingsSection(id: "s", title: "S", fields: [
            .toggle("a", "A", default: true), .text("b", "B", default: "x"),
        ])])
        var settings = ModuleSettings(values: ["b": "y"], schema: schema)
        XCTAssertTrue(settings.bool("a"))
        XCTAssertEqual(settings.string("b"), "y")
        settings["a"] = false
        XCTAssertFalse(settings.bool("a"))
        XCTAssertEqual(settings.int("missing"), 0)
    }

    func testSchemaDecodesHandWrittenJSON() throws {
        let json = #"""
        {"sections":[{"id":"main","title":{"en":"Main","zh-Hans":"主要"},"fields":[
          {"key":"mode","kind":"choice","options":[{"value":"a","title":"A"}],"default":"a"},
          {"key":"verbose","kind":"toggle"}
        ]}]}
        """#
        let schema = try JSONDecoder().decode(SettingsSchema.self, from: Data(json.utf8))
        XCTAssertEqual(schema.allFields.map(\.key), ["mode", "verbose"])
        XCTAssertEqual(schema.defaultValues()["verbose"], .bool(false))
    }
}

final class MenuRuleTests: XCTestCase {
    func item(_ path: String, _ kind: ItemKind) -> SelectedItem {
        SelectedItem(url: URL(fileURLWithPath: path), kind: kind)
    }

    func selection(_ items: [SelectedItem]) -> FinderSelection {
        FinderSelection(context: .items, items: items, container: URL(fileURLWithPath: "/tmp"))
    }

    func testExtensionsAreCaseInsensitive() {
        let rule = MenuRule.files(["py"])
        XCTAssertTrue(rule.matches(selection([item("/a/x.PY", .file)])))
        XCTAssertFalse(rule.matches(selection([item("/a/x.md", .file)])))
    }

    func testAllItemsMustMatchByDefault() {
        let rule = MenuRule.files(["md"])
        XCTAssertFalse(rule.matches(selection([item("/a.md", .file), item("/b.txt", .file)])))
        var any = rule
        any.requireAllItemsMatch = false
        XCTAssertTrue(any.matches(selection([item("/a.md", .file), item("/b.txt", .file)])))
    }

    func testFoldersIgnoreExtensionFilterWhenAllowed() {
        let rule = MenuRule(contexts: [.items], itemKinds: [.file, .folder], extensions: ["md"])
        XCTAssertTrue(rule.matches(selection([item("/a/Project", .folder)])))
        XCTAssertTrue(rule.matches(selection([item("/a/x.md", .file)])))
        XCTAssertFalse(rule.matches(selection([item("/a/x.png", .file)])))
    }

    func testSelectionLimits() {
        let rule = MenuRule.files(["py"], max: 1)
        XCTAssertFalse(rule.matches(selection([item("/a.py", .file), item("/b.py", .file)])))
        XCTAssertFalse(rule.matches(selection([])))
    }

    func testContainerContext() {
        let background = FinderSelection.container(URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(MenuRule.container.matches(background))
        XCTAssertTrue(MenuRule.anything.matches(background))
        XCTAssertFalse(MenuRule.anyItems.matches(background))
    }

    func testUniformTypeConformance() {
        let rule = MenuRule.files(nil, typeIdentifiers: ["public.image"])
        XCTAssertTrue(rule.matches(selection([item("/a/photo.heic", .file)])))
        XCTAssertFalse(rule.matches(selection([item("/a/doc.pdf", .file)])))
    }

    func testDestinationFolder() {
        XCTAssertEqual(FinderSelection.container(URL(fileURLWithPath: "/tmp/x")).destinationFolder?.path, "/tmp/x")
        let folder = selection([item("/tmp/y", .folder)])
        XCTAssertEqual(folder.destinationFolder?.path, "/tmp/y")
    }
}

final class MenuSnapshotTests: XCTestCase {
    let contributions = [
        ModuleMenuContribution(moduleID: "m.path", actions: [
            ActionDescriptor(id: "copy", title: "Copy Path", group: .path, order: 10, rule: .anything),
        ]),
        ModuleMenuContribution(moduleID: "m.open", actions: [
            ActionDescriptor(id: "code", title: "Open with Code", shortTitle: "Code", group: .open, order: 10, rule: .anyItems),
            ActionDescriptor(id: "py", title: "Run Python", group: .run, order: 10, rule: .files(["py"])),
            ActionDescriptor(id: "install", title: "Install", presentation: .hostOnly),
        ]),
    ]

    func testGroupsAreOrderedAndHostOnlyActionsExcluded() {
        let snapshot = MenuSnapshotBuilder.build(contributions: contributions, preferences: MenuPreferences(),
                                                 appearance: MenuAppearance(), languages: ["en"])
        XCTAssertEqual(snapshot.groups.map(\.id), [.run, .open, .path])
        XCTAssertFalse(snapshot.items.contains { $0.actionID == "install" })
    }

    func testOverridesRenameHideAndMove() {
        var preferences = MenuPreferences()
        preferences.items["m.path/copy"] = MenuItemOverride(title: "复制路径", group: .open)
        preferences.items["m.open/py"] = MenuItemOverride(hidden: true)
        preferences.groups["open"] = MenuGroupOverride(title: "Apps", presentation: .submenu)
        let snapshot = MenuSnapshotBuilder.build(contributions: contributions, preferences: preferences,
                                                 appearance: MenuAppearance(), languages: ["en"])
        XCTAssertEqual(snapshot.groups.map(\.id), [.open])
        XCTAssertEqual(snapshot.groups.first?.title, "Apps")
        XCTAssertEqual(snapshot.groups.first?.presentation, .submenu)
        XCTAssertEqual(Set(snapshot.items.map(\.title)), ["复制路径", "Open with Code"])
    }

    func testShortTitles() {
        let snapshot = MenuSnapshotBuilder.build(contributions: contributions, preferences: MenuPreferences(),
                                                 appearance: MenuAppearance(titleStyle: .short), languages: ["en"])
        XCTAssertTrue(snapshot.items.contains { $0.title == "Code" })
    }

    func testResolverFiltersBySelection() throws {
        let snapshot = MenuSnapshotBuilder.build(contributions: contributions, preferences: MenuPreferences(),
                                                 appearance: MenuAppearance(), languages: ["en"])
        let python = FinderSelection(context: .items, items: [SelectedItem(url: URL(fileURLWithPath: "/a/x.py"), kind: .file)],
                                     container: nil)
        XCTAssertEqual(MenuResolver.resolve(snapshot, for: python).allItems.map(\.actionID), ["py", "code", "copy"])
        let background = FinderSelection.container(URL(fileURLWithPath: "/a"))
        XCTAssertEqual(MenuResolver.resolve(snapshot, for: background).allItems.map(\.actionID), ["copy"])

        let data = try FinderPlusJSON.encoder().encode(snapshot)
        var decoded = try FinderPlusJSON.decoder().decode(MenuSnapshot.self, from: data)
        // ISO 8601 drops sub-second precision; everything else must survive the round trip.
        XCTAssertEqual(decoded.generatedAt.timeIntervalSince1970, snapshot.generatedAt.timeIntervalSince1970, accuracy: 1)
        decoded.generatedAt = snapshot.generatedAt
        XCTAssertEqual(decoded, snapshot)
    }
}
