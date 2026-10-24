import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import FinderPlusBuiltinModules
@testable import FinderPlusCore
@testable import FPFileCreator
@testable import FPMarkdownPDF
@testable import FPPathTools
@testable import FPQuickOpen
@testable import FPSidebar

final class BuiltinModuleContractTests: XCTestCase {
    func testManifestsAreUniqueAndSerializable() throws {
        let modules = BuiltinModules.make()
        XCTAssertEqual(Set(modules.map(\.id)).count, modules.count)
        for module in modules {
            let manifest = module.manifest
            XCTAssertEqual(manifest.kind, .native, manifest.id)
            XCTAssertTrue(manifest.isCompatibleWithHost, manifest.id)
            let data = try FinderPlusJSON.encoder().encode(manifest)
            let decoded = try FinderPlusJSON.decoder().decode(ModuleManifest.self, from: data)
            XCTAssertEqual(decoded.id, manifest.id)
            XCTAssertEqual(decoded.settings, manifest.settings, manifest.id)

            let settings = ModuleSettings(schema: manifest.settings)
            let ids = module.menuActions(settings: settings).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate action ids in \(manifest.id)")
        }
    }

    func testMenuForCommonSelections() {
        let modules = BuiltinModules.make()
        var config = HostConfiguration()
        // Pretend every module is enabled so the test does not depend on installed apps.
        for module in modules { config.modules[module.id] = ModuleState(enabled: true, settings: ["hideMissingApps": false]) }
        let contributions = modules.map { module in
            ModuleMenuContribution(moduleID: module.id, actions: module.menuActions(settings: config.settings(for: module.manifest)))
        }
        let snapshot = MenuSnapshotBuilder.build(contributions: contributions, preferences: config.menu,
                                                 appearance: MenuAppearance(), languages: ["en"])

        func actions(_ selection: FinderSelection) -> Set<String> {
            Set(MenuResolver.resolve(snapshot, for: selection).allItems.map(\.actionID))
        }
        func file(_ name: String) -> FinderSelection {
            FinderSelection(context: .items, items: [SelectedItem(url: URL(fileURLWithPath: "/tmp/\(name)"), kind: .file)],
                            container: URL(fileURLWithPath: "/tmp"))
        }

        let python = actions(file("main.py"))
        XCTAssertTrue(python.isSuperset(of: ["runPython", "open.vs-code", "open.coteditor", "copyPath"]))
        XCTAssertFalse(python.contains("export"))

        let markdown = actions(file("notes.md"))
        XCTAssertTrue(markdown.isSuperset(of: ["export", "open.vs-code", "copyPath"]))

        let image = actions(file("photo.jpg"))
        XCTAssertTrue(image.contains("quick"))
        XCTAssertTrue(image.contains("copyPath"))

        let folder = actions(FinderSelection(context: .items, items: [SelectedItem(url: URL(fileURLWithPath: "/tmp/Project"), kind: .folder)],
                                             container: URL(fileURLWithPath: "/tmp")))
        XCTAssertTrue(folder.isSuperset(of: ["terminal", "open.vs-code", "choose", "setIcon", "copyPath"]))
        XCTAssertFalse(folder.contains("open.coteditor"))

        let background = actions(.container(URL(fileURLWithPath: "/tmp")))
        XCTAssertTrue(background.isSuperset(of: ["new.md", "new.docx", "copyPath", "terminal"]))
        XCTAssertFalse(background.contains("runPython"))
    }
}

final class DocumentFactoryTests: XCTestCase {
    func testOfficeDocumentsAreValidZipArchives() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, data) in [("a.docx", DocumentFactory.wordDocument()), ("b.xlsx", DocumentFactory.spreadsheet()),
                             ("c.pptx", DocumentFactory.presentation())] {
            let url = folder.appendingPathComponent(name)
            try data.write(to: url)
            XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], name)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-tq", url.path]
            unzip.standardOutput = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            XCTAssertEqual(unzip.terminationStatus, 0, "\(name) failed CRC/structure check")
        }
    }

    func testCRC32() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testBlankPDFOpensWithOnePage() throws {
        let data = DocumentFactory.blankPDF()
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(document.numberOfPages, 1)

        // The startxref offset must point exactly at the xref keyword.
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n")
        let offset = try XCTUnwrap(lines.firstIndex(of: "startxref").map { Int(lines[$0 + 1])! })
        XCTAssertEqual(String(decoding: data[offset..<(offset + 4)], as: UTF8.self), "xref")
    }
}

final class FileCreatorTests: XCTestCase {
    func testCreatesUniqueValidFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let module = FileCreatorModule(templatesDirectory: folder.appendingPathComponent("NoTemplates"))
        let system = MockSystemServices()
        var settings = ModuleSettings(schema: module.manifest.settings)
        settings["afterCreate"] = "reveal"
        settings["baseName"] = "Untitled"

        for _ in 0..<2 {
            _ = try await module.perform(ActionInvocation(actionID: "new.docx", parameters: ["type": "docx"],
                                                          selection: .container(folder), settings: settings),
                                         context: makeContext(system))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled.docx").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Untitled 2.docx").path))
        XCTAssertEqual(system.revealed.count, 2)
    }

    func testRenameFailureDoesNotFailCreation() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let module = FileCreatorModule(templatesDirectory: folder.appendingPathComponent("NoTemplates"))
        let system = MockSystemServices()
        system.renameError = ModuleError.failed("no accessibility")
        let outcome = try await module.perform(
            ActionInvocation(actionID: "new.md", parameters: ["type": "md"], selection: .container(folder),
                             settings: ModuleSettings(schema: module.manifest.settings)),
            context: makeContext(system))
        XCTAssertEqual(outcome.outputs.count, 1)
        XCTAssertEqual(outcome.message, "no accessibility")
    }

    func testTemplatesAppearInMenu() throws {
        let templates = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: templates) }
        FileManager.default.createFile(atPath: templates.appendingPathComponent("Weekly Report.docx").path, contents: Data())
        FileManager.default.createFile(atPath: templates.appendingPathComponent("default.md").path, contents: Data("# Hi".utf8))
        let module = FileCreatorModule(templatesDirectory: templates)
        let ids = module.menuActions(settings: ModuleSettings(schema: module.manifest.settings)).map(\.id)
        XCTAssertTrue(ids.contains("template.Weekly Report.docx"))
        XCTAssertFalse(ids.contains("template.default.md"), "default.<ext> overrides content, it is not a menu template")
    }

    func testCustomTypes() {
        let module = FileCreatorModule()
        var settings = ModuleSettings(schema: module.manifest.settings)
        settings["customTypes"] = [["extension": ".swift", "title": "Swift", "content": "import Foundation\n"]]
        let types = module.availableTypes(settings: settings)
        XCTAssertEqual(types.last?.pathExtension, "swift")
        XCTAssertEqual(types.last?.title.localized, "Swift")
    }
}

final class PathFormatterTests: XCTestCase {
    let selection = FinderSelection(context: .items, items: [
        SelectedItem(url: URL(fileURLWithPath: "/Users/me/My File.txt"), kind: .file),
        SelectedItem(url: URL(fileURLWithPath: "/Users/me/Folder"), kind: .folder),
    ], container: nil)

    func settings(_ values: [String: SettingValue]) -> ModuleSettings {
        ModuleSettings(values: values, schema: PathToolsModule().manifest.settings)
    }

    func testDefaultIsOnePathPerLine() {
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings([:])), "/Users/me/My File.txt\n/Users/me/Folder")
    }

    func testQuotingAndSeparators() {
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings(["separator": "space", "quoting": "single"])),
                       "'/Users/me/My File.txt' '/Users/me/Folder'")
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings(["quoting": "backslash", "separator": "comma"])),
                       "/Users/me/My\\ File.txt, /Users/me/Folder")
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings(["trailingSlashForFolders": true, "separator": "custom",
                                                                                      "customSeparator": "|"])),
                       "/Users/me/My File.txt|/Users/me/Folder/")
    }
}

extension PathFormatterTests {
    func testWrappingCharacters() {
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings(["wrap": "single", "separator": "space"])),
                       "'/Users/me/My File.txt' '/Users/me/Folder'")
        XCTAssertEqual(PathFormatter.format(selection: selection, settings: settings(["wrap": "double"])),
                       "\"/Users/me/My File.txt\"\n\"/Users/me/Folder\"")
        XCTAssertEqual(PathFormatter.decorate("it's.md", settings: settings(["wrap": "curlyDouble"])), "“it's.md”")
        // Plain wrapping leaves the text untouched (no escaping).
        XCTAssertEqual(PathFormatter.decorate("it's.md", settings: settings(["wrap": "single"])), "'it's.md'")
        // Shell escaping takes precedence, so quotes are never doubled.
        XCTAssertEqual(PathFormatter.decorate("a b", settings: settings(["wrap": "double", "quoting": "single"])), "'a b'")
    }

    func testNamesAreWrapped() async throws {
        let system = MockSystemServices()
        let module = PathToolsModule()
        _ = try await module.perform(ActionInvocation(actionID: "copyName", selection: selection,
                                                      settings: settings(["wrap": "double", "separator": "comma"])),
                                     context: makeContext(system))
        XCTAssertEqual(system.pasteboard, "\"My File.txt\", \"Folder\"")
    }
}

final class ScriptRunPlannerTests: XCTestCase {
    let script = URL(fileURLWithPath: "/Users/me/My Project/src/run's.py")

    func settings(_ values: [String: SettingValue]) -> ModuleSettings {
        ModuleSettings(values: values, schema: QuickOpenModule().manifest.settings)
    }

    func testUsesProjectVirtualEnvironment() throws {
        let plan = try ScriptRunPlanner.python(file: script, settings: settings([:]), locate: { _ in nil },
                                               fileExists: { $0 == "/Users/me/My Project/.venv/bin/python" })
        XCTAssertEqual(plan.arguments.first, "/Users/me/My Project/.venv/bin/python")
        XCTAssertEqual(plan.commandLine,
                       "cd '/Users/me/My Project/src' && '/Users/me/My Project/.venv/bin/python' '/Users/me/My Project/src/run'\\''s.py'")
    }

    func testCondaAndArgumentsAndExitBehavior() throws {
        let plan = try ScriptRunPlanner.python(
            file: script,
            settings: settings(["interpreterMode": "conda", "condaEnvironment": "ml", "pythonArguments": "--n 3 \"a b\"",
                                "afterRun": "exitOnSuccess", "workingDirectory": "projectRoot"]),
            locate: { $0 == "conda" ? URL(fileURLWithPath: "/opt/homebrew/bin/conda") : nil },
            fileExists: { $0 == "/Users/me/My Project/.git" })
        XCTAssertEqual(plan.arguments, ["/opt/homebrew/bin/conda", "run", "--no-capture-output", "-n", "ml", "python",
                                        script.path, "--n", "3", "a b"])
        XCTAssertEqual(plan.workingDirectory.path, "/Users/me/My Project")
        XCTAssertTrue(plan.commandLine.hasSuffix("'a b' && exit"))
    }

    func testRscript() throws {
        let plan = try ScriptRunPlanner.r(file: URL(fileURLWithPath: "/tmp/a.R"), settings: settings(["afterRun": "waitForKey"]),
                                          locate: { _ in URL(fileURLWithPath: "/usr/local/bin/Rscript") }, fileExists: { _ in false })
        XCTAssertTrue(plan.commandLine.hasPrefix("cd /tmp && /usr/local/bin/Rscript /tmp/a.R; printf"))
    }
}

final class MarkdownRendererTests: XCTestCase {
    func testMathIsProtectedFromEmphasis() {
        let html = MarkdownHTMLRenderer.fragment(from: "Energy $a_1 * b_2$ and *em*\n\n$$\\sum_{i=1}^n x_i$$")
        XCTAssertTrue(html.contains("$a_1 * b_2$"))
        XCTAssertTrue(html.contains("<em>em</em>"))
        XCTAssertTrue(html.contains("$$\\sum_{i=1}^n x_i$$"))
    }

    func testCodeIsLeftAlone() {
        let html = MarkdownHTMLRenderer.fragment(from: "Price `$5 and $6`\n\n```sh\necho $HOME $PATH\n```\n")
        XCTAssertTrue(html.contains("<code>$5 and $6</code>"))
        XCTAssertTrue(html.contains("echo $HOME $PATH"))
        XCTAssertTrue(html.contains("class=\"language-sh\""))
    }

    func testCurrencyIsNotMath() {
        let (text, math) = MathProtector.protect("It costs $5 and $10.")
        XCTAssertTrue(math.isEmpty)
        XCTAssertEqual(text, "It costs $5 and $10.")
    }

    func testTablesAndChinese() {
        let html = MarkdownHTMLRenderer.fragment(from: "| 名称 | 值 |\n|:--|--:|\n| 甲 | 1 |\n")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("名称"))
    }

    func testDocumentReferencesBundledAssets() {
        var options = MarkdownHTMLRenderer.Options()
        options.title = "T"
        let html = MarkdownHTMLRenderer.document(from: "# Hi", options: options, resources: URL(fileURLWithPath: "/res"),
                                                 baseURL: URL(fileURLWithPath: "/docs", isDirectory: true))
        XCTAssertTrue(html.contains("file:///res/katex/katex.min.js"))
        XCTAssertTrue(html.contains("hljs.highlightAll()"))
        XCTAssertTrue(html.contains("<base href=\"file:///docs/\">"))
    }
}

final class SidebarBackendTests: XCTestCase {
    /// Regression test for a use-after-free: item references must stay valid while they are read.
    func testReadingFavoritesDoesNotCrash() throws {
        guard let backend = SidebarBackend() else { throw XCTSkip("LSSharedFileList is not available on this macOS") }
        let rows: [SidebarRow]
        do {
            rows = try backend.rows()
        } catch {
            throw XCTSkip("Sidebar list unavailable: \(error.localizedDescription)")
        }
        for _ in 0..<20 {
            XCTAssertEqual(try backend.rows().map(\.name), rows.map(\.name))
        }
    }

    func testIconCodes() {
        let code = SidebarIconCode.allocate(avoiding: [])
        XCTAssertTrue(SidebarIconCode.isOurs(code))
        XCTAssertNotEqual(SidebarIconCode.allocate(avoiding: [code]), code)
        XCTAssertFalse(SidebarIconCode.isOurs("S003"))
        XCTAssertTrue(SidebarIconCode.isSidebarFavoritesCode("S003"))
    }

    /// The helper bundle must make Launch Services resolve our code to a declared type.
    func testHelperBundleRegistersIconCodes() throws {
        let folder = try temporaryFolder()
        let helper = SidebarIconHelper(directory: folder)
        defer {
            helper.unregister()
            try? FileManager.default.removeItem(at: folder)
        }
        let favorite = SidebarFavorite(id: UUID(), path: "/tmp/Projects", symbol: "hammer.fill", enabled: true,
                                       code: "FZZY", provenance: .managed)
        XCTAssertTrue(try helper.update(for: [favorite]))
        XCTAssertFalse(try helper.update(for: [favorite]), "unchanged declarations must not rebuild")
        let type = UTType(tag: "FZZY", tagClass: .init(rawValue: "com.apple.ostype"), conformingTo: nil)
        XCTAssertEqual(type?.identifier, SidebarIconHelper.typePrefix + "fzzy")
        XCTAssertTrue(type?.conforms(to: .folder) ?? false)
    }

    /// End to end on the CI Mac: add a folder with an icon, read the code back, then remove it.
    func testAddIconAndRemoveFavorite() throws {
        guard SidebarBackend() != nil else { throw XCTSkip("LSSharedFileList is not available on this macOS") }
        let data = try temporaryFolder()
        let target = try temporaryFolder()
        let coordinator = SidebarIconCoordinator(dataDirectory: data)
        defer {
            if let favorite = coordinator.store.load().first { _ = try? coordinator.delete(favorite.id) }
            coordinator.helper.unregister()
            try? FileManager.default.removeItem(at: data)
            try? FileManager.default.removeItem(at: target)
        }
        let added: SidebarIconCoordinator.Result
        do {
            added = try coordinator.upsert(path: target.path, symbol: "star.fill")
        } catch {
            throw XCTSkip("Sidebar not writable here: \(error.localizedDescription)")
        }
        let favorite = try XCTUnwrap(added.favorites.first)
        XCTAssertEqual(favorite.provenance, .managed)
        let row = try XCTUnwrap(added.rows.first { SidebarBackend.samePath($0.path, target.path) })
        XCTAssertEqual(row.iconCode, favorite.code)

        let removed = try coordinator.delete(favorite.id)
        XCTAssertFalse(removed.rows.contains { SidebarBackend.samePath($0.path, target.path) })
    }

    func testDisabledModulesRunNoDependencyChecks() async {
        XCTAssertFalse(HostConfiguration().isEnabled(SidebarModule().manifest))
    }
}
