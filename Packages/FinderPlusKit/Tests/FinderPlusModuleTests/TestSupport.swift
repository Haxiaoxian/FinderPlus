import Foundation
import FinderPlusCore

/// Records system interactions instead of performing them.
final class MockSystemServices: SystemServices, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pasteboard: String?
    private(set) var opened: [(urls: [URL], app: URL?)] = []
    private(set) var revealed: [URL] = []
    private(set) var terminalCommands: [TerminalCommand] = []
    var promptAnswer: String?
    var renameError: Error?

    func copyToPasteboard(_ string: String) async { lock.withLock { pasteboard = string } }
    func open(_ urls: [URL], withApplicationAt application: URL?) async throws { lock.withLock { opened.append((urls, application)) } }
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func reveal(_ urls: [URL]) async { lock.withLock { revealed += urls } }
    func beginRenameInFinder() async throws { if let renameError { throw renameError } }
    func runInTerminal(_ command: TerminalCommand) async throws { lock.withLock { terminalCommands.append(command) } }
    func openTerminal(_ application: TerminalApplication, at folder: URL) async throws {}
    func confirm(title: String, message: String, confirmButton: String) async -> Bool { true }
    func promptForText(title: String, message: String, defaultValue: String) async -> String? { promptAnswer }
    func notify(title: String, body: String) async {}
}

struct NoDependencies: DependencyChecking {
    func statuses(for descriptors: [DependencyDescriptor]) async -> [DependencyStatus] { [] }
    func locateExecutable(_ names: [String]) -> URL? { nil }
    func locateApplication(_ bundleIdentifiers: [String]) -> URL? { nil }
}

func makeContext(_ system: MockSystemServices, moduleID: String = "test") -> ModuleContext {
    ModuleContext(moduleID: moduleID,
                  dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("fp-test-\(UUID().uuidString)"),
                  system: system, processes: ProcessRunner(), reporter: SilentTaskReporter(), dependencies: NoDependencies())
}

func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
