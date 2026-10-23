import XCTest
@testable import FinderPlusCore
@testable import FinderPlusEngine

final class ScriptPackageTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho \"$@\"\n".utf8).write(to: folder.appendingPathComponent("scripts/run.sh"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func writeManifest(script: String = "scripts/run.sh") throws {
        let json = """
        {
          "formatVersion": 1,
          "id": "com.example.echo",
          "name": {"en": "Echo", "zh-Hans": "回显"},
          "version": "1.2.0",
          "kind": "native",
          "enabledByDefault": true,
          "settings": {"sections": [{"id": "s", "title": "S", "fields": [{"key": "mode", "kind": "text", "default": "fast"}]}]},
          "actions": [{
            "id": "echo", "title": "Echo", "rule": {"contexts": ["items"], "extensions": ["txt"]},
            "run": {"interpreter": "/bin/sh", "script": "\(script)", "arguments": ["--mode={setting:mode}", "{files}"]}
          }]
        }
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent(ScriptPackage.manifestFileName))
    }

    func testLoadsAndCannotEscalate() throws {
        try writeManifest()
        let package = try ScriptPackage.load(from: folder)
        XCTAssertEqual(package.manifest.kind, .scriptPackage, "packages must not claim to be native")
        XCTAssertFalse(package.manifest.enabledByDefault, "packages must never start enabled")
        XCTAssertTrue(package.manifest.permissions.contains(.runProcesses))
        XCTAssertEqual(package.commands["echo"]?.interpreter, "/bin/sh")
        XCTAssertFalse(package.contentHash.isEmpty)
    }

    func testRejectsScriptsOutsideThePackage() throws {
        try writeManifest(script: "../../../../bin/sh")
        XCTAssertThrowsError(try ScriptPackage.load(from: folder)) { error in
            XCTAssertEqual(error as? ScriptPackageError, .scriptOutsidePackage("../../../../bin/sh"))
        }
    }

    func testHashChangesWhenAnyFileChanges() throws {
        try writeManifest()
        let before = try ScriptPackage.load(from: folder).contentHash
        try Data("#!/bin/sh\nrm -rf ~\n".utf8).write(to: folder.appendingPathComponent("scripts/run.sh"))
        let after = try ScriptPackage.load(from: folder).contentHash
        XCTAssertNotEqual(before, after)
    }

    func testArgumentExpansionKeepsPathsSeparate() {
        let selection = FinderSelection(context: .items, items: [
            SelectedItem(url: URL(fileURLWithPath: "/tmp/a b.txt"), kind: .file),
            SelectedItem(url: URL(fileURLWithPath: "/tmp/$(x).txt"), kind: .file),
        ], container: URL(fileURLWithPath: "/tmp"))
        let settings = ModuleSettings(values: ["mode": "slow"])
        let arguments = ScriptArgumentExpander.expand(["--mode={setting:mode}", "{files}", "{folder}"], selection: selection,
                                                      settings: settings, packageDirectory: folder)
        XCTAssertEqual(arguments, ["--mode=slow", "/tmp/a b.txt", "/tmp/$(x).txt", "/tmp"])
    }

    func testUntrustedPackageIsExcludedFromMenu() throws {
        try writeManifest()
        let package = try ScriptPackage.load(from: folder)
        let registry = ModuleRegistry(modules: [ScriptPackageModule(package: package)])
        var config = HostConfiguration()
        config.modules[package.manifest.id] = ModuleState(enabled: true)

        XCTAssertTrue(ExecutionEngine.buildSnapshot(registry: registry, configuration: config).items.isEmpty)
        config.trustedPackages[package.manifest.id] = package.contentHash
        XCTAssertEqual(ExecutionEngine.buildSnapshot(registry: registry, configuration: config).items.map(\.actionID), ["echo"])
        config.trustedPackages[package.manifest.id] = "stale-hash"
        XCTAssertTrue(ExecutionEngine.buildSnapshot(registry: registry, configuration: config).items.isEmpty)
    }
}
