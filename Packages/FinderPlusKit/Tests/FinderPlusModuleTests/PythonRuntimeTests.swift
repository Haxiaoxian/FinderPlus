import XCTest
@testable import FinderPlusCore
@testable import FinderPlusEngine
@testable import FPMarkItDown

/// End-to-end check of the one-click Python setup. Downloads uv, a standalone Python and
/// MarkItDown (~450 MB), so it only runs when FINDERPLUS_NETWORK_TESTS=1 (set in CI).
final class PythonRuntimeTests: XCTestCase {
    func testOneClickMarkItDownSetupAndConversion() async throws {
        guard ProcessInfo.processInfo.environment["FINDERPLUS_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set FINDERPLUS_NETWORK_TESTS=1 to run network tests")
        }
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimes = root.appendingPathComponent("Runtimes", isDirectory: true)
        let module = MarkItDownModule(runtimesRoot: runtimes)
        let system = MockSystemServices()
        let context = ModuleContext(moduleID: MarkItDownModule.id, dataDirectory: root.appendingPathComponent("data"),
                                    system: system, processes: ProcessRunner(), reporter: SilentTaskReporter(),
                                    dependencies: NoDependencies(),
                                    python: ManagedPythonEnvironments(root: runtimes))
        let settings = ModuleSettings(schema: module.manifest.settings)

        // Before: missing, with a one-click fix that needs no system Python.
        let before = await module.dependencyStatuses(settings: settings, checker: NoDependencies())
        XCTAssertEqual(before.first?.state, .missing)
        XCTAssertEqual(before.first?.fixActionID, "installRuntime")

        _ = try await module.perform(ActionInvocation(actionID: "installRuntime", selection: .empty, settings: settings),
                                     context: context)
        let after = await module.dependencyStatuses(settings: settings, checker: NoDependencies())
        XCTAssertEqual(after.first?.state, .satisfied)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: runtimes.appendingPathComponent("bin/uv").path))

        // Convert an HTML file and check the Markdown output.
        let html = root.appendingPathComponent("page.html")
        try Data("<html><body><h1>Hello FinderPlus</h1><table><tr><th>A</th></tr><tr><td>1</td></tr></table></body></html>".utf8)
            .write(to: html)
        let selection = FinderSelection(context: .items, items: [SelectedItem(url: html, kind: .file)], container: root)
        let outcome = try await module.perform(ActionInvocation(actionID: "convert", selection: selection, settings: settings),
                                               context: context)
        let markdown = try String(contentsOf: try XCTUnwrap(outcome.outputs.first), encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Hello FinderPlus"), markdown)
    }
}

final class CloudSupportTests: XCTestCase {
    func testOldSnapshotsWithoutMonitoredDirectoriesStillDecode() throws {
        let json = #"{"formatVersion":1,"generatedAt":"2026-10-23T00:00:00Z","appearance":{"rootTitle":"FinderPlus","style":"submenu","showIcons":true,"titleStyle":"full"},"groups":[],"items":[]}"#
        let snapshot = try FinderPlusJSON.decoder().decode(MenuSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.monitoredDirectories, [])
    }

    func testUnreadableItemsAreGuessedFromTheirName() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertEqual(SelectedItem.inspect(missing.appendingPathComponent("Folder")).kind, .folder)
        XCTAssertEqual(SelectedItem.inspect(missing.appendingPathComponent("notes.md")).kind, .file)
    }

    func testCloudPathsAreRecognized() {
        XCTAssertTrue(CloudStorageLocations.isCloudItem(URL(fileURLWithPath: "/Users/me/Library/CloudStorage/OneDrive-Personal/a.docx")))
        XCTAssertFalse(CloudStorageLocations.isCloudItem(URL(fileURLWithPath: "/Users/me/Documents/a.docx")))
    }
}
