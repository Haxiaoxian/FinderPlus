import XCTest
@testable import FinderPlusCore

final class ShellQuotingTests: XCTestCase {
    func testQuote() {
        XCTAssertEqual(ShellQuoting.quote("/usr/bin/python3"), "/usr/bin/python3")
        XCTAssertEqual(ShellQuoting.quote("/a b/c"), "'/a b/c'")
        XCTAssertEqual(ShellQuoting.quote("it's"), "'it'\\''s'")
        XCTAssertEqual(ShellQuoting.quote("$(rm -rf ~)"), "'$(rm -rf ~)'")
        XCTAssertEqual(ShellQuoting.quote(""), "''")
    }

    func testBackslashAndDoubleQuote() {
        XCTAssertEqual(ShellQuoting.backslashEscape("/a b(1)"), "/a\\ b\\(1\\)")
        XCTAssertEqual(ShellQuoting.doubleQuote("a\"$b`"), "\"a\\\"\\$b\\`\"")
    }

    func testShellWords() throws {
        XCTAssertEqual(try ShellWords.split(#"--name "two words" 'single quoted' a\ b"#),
                       ["--name", "two words", "single quoted", "a b"])
        XCTAssertEqual(try ShellWords.split("  "), [])
        XCTAssertEqual(try ShellWords.split(#""""#), [""])
        XCTAssertThrowsError(try ShellWords.split("\"open"))
    }

    func testAppleScriptLiteral() {
        XCTAssertEqual(AppleScriptString.literal(#"say "hi" \ bye"#), #""say \"hi\" \\ bye""#)
    }
}

final class FileNamingTests: XCTestCase {
    func testAppendsNumbersLikeFinder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = UniqueFileNamer.availableURL(in: folder, baseName: "Untitled", pathExtension: "md")
        XCTAssertEqual(first.lastPathComponent, "Untitled.md")
        FileManager.default.createFile(atPath: first.path, contents: nil)
        let second = UniqueFileNamer.availableURL(in: folder, baseName: "Untitled", pathExtension: "md")
        XCTAssertEqual(second.lastPathComponent, "Untitled 2.md")
    }

    func testSanitizes() {
        XCTAssertEqual(UniqueFileNamer.sanitizedFileName(" a/b:c "), "a-b-c")
        XCTAssertEqual(UniqueFileNamer.sanitizedFileName("..hidden"), "hidden")
    }

    func testPatternExpansion() {
        let date = ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z")!
        let name = UniqueFileNamer.expand(pattern: "{name}-{date}.pdf", sourceURL: URL(fileURLWithPath: "/x/Notes.md"), date: date)
        XCTAssertTrue(name.hasPrefix("Notes-2026-01-0"))
    }
}

final class RequestInboxTests: XCTestCase {
    var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSubmitAndTakeOnce() throws {
        let inbox = RequestInbox(directory: directory)
        let request = ActionRequest(moduleID: "m", actionID: "a", selection: .container(URL(fileURLWithPath: "/tmp")), origin: .finder)
        try inbox.submit(request)
        XCTAssertEqual(inbox.take(request.id)?.actionID, "a")
        XCTAssertNil(inbox.take(request.id))
    }

    func testExpiredRequestsAreDropped() throws {
        let inbox = RequestInbox(directory: directory)
        let old = ActionRequest(moduleID: "m", actionID: "a", selection: .empty, origin: .finder,
                                createdAt: Date(timeIntervalSinceNow: -3600))
        try inbox.submit(old)
        XCTAssertNil(inbox.take(old.id))
        XCTAssertTrue(inbox.takeAll().isEmpty)
    }

    func testURLRoutes() {
        let id = UUID()
        XCTAssertEqual(FinderPlusURL.parse(FinderPlusURL.dispatch(id)), .dispatch(id))
        XCTAssertEqual(FinderPlusURL.parse(FinderPlusURL.openModule("x.y")), .module("x.y"))
        XCTAssertNil(FinderPlusURL.parse(URL(string: "finderplus://dispatch?id=nope")!))
        XCTAssertNil(FinderPlusURL.parse(URL(string: "https://example.com")!))
    }
}

final class ConfigurationStoreTests: XCTestCase {
    func testSaveLoadExportImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FinderPlusPaths.overrideHostDataRoot = root
        defer {
            FinderPlusPaths.overrideHostDataRoot = nil
            try? FileManager.default.removeItem(at: root)
        }
        let store = ConfigurationStore(fileURL: root.appendingPathComponent("configuration.json"))
        try store.update { config in
            config.modules["m"] = ModuleState(enabled: false, settings: ["k": "v"])
            config.menu.items["m/a"] = MenuItemOverride(title: "Renamed")
        }
        XCTAssertEqual(ConfigurationStore(fileURL: store.fileURL).load().modules["m"]?.settings["k"], "v")

        let export = root.appendingPathComponent("export.json")
        try store.export(to: export)
        try store.update { $0.modules.removeAll() }
        let imported = try store.importConfiguration(from: export)
        XCTAssertEqual(imported.menu.items["m/a"]?.title, "Renamed")
        XCTAssertEqual(store.load().modules["m"]?.enabled, false)
    }

    func testUnreadableFileFallsBackToDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FinderPlusPaths.overrideHostDataRoot = root
        defer {
            FinderPlusPaths.overrideHostDataRoot = nil
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: file)
        XCTAssertEqual(ConfigurationStore(fileURL: file).load(), HostConfiguration())
    }

    func testExperimentalModulesStartDisabled() {
        let manifest = ModuleManifest(id: "x", name: "X", summary: "", version: "1.0.0", icon: "star", category: .utility,
                                      stability: .experimental)
        XCTAssertFalse(HostConfiguration().isEnabled(manifest))
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndExitCode() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo out; echo err >&2; exit 3"])
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.standardOutput, "out\n")
        XCTAssertEqual(result.standardError, "err\n")
    }

    /// Regression test: output of short-lived processes used to be lost occasionally.
    func testNeverLosesOutputOfFastProcesses() async throws {
        let runner = ProcessRunner()
        for index in 0..<200 {
            let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["run-\(index)"])
            XCTAssertEqual(result.standardOutput, "run-\(index)\n")
        }
    }

    func testStreamsLargeOutputAndLines() async throws {
        let runner = ProcessRunner()
        let lines = LineCounter()
        let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/seq"), arguments: ["1", "50000"],
                                          onOutputLine: { _ in lines.increment() })
        XCTAssertEqual(result.standardOutput.split(separator: "\n").count, 50000)
        XCTAssertEqual(lines.value, 50000)
    }

    func testArgumentsAreNotInterpretedByAShell() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["$(whoami)", "; ls"])
        XCTAssertEqual(result.standardOutput, "$(whoami) ; ls\n")
    }

    func testTimeout() async {
        let runner = ProcessRunner()
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.3)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertTrue(error is ProcessRunnerError)
        }
    }
}

final class LineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
