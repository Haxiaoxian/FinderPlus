import Foundation
import FinderPlusCore

/// Adapts a ``ScriptPackage`` to the ``FinderPlusModule`` contract.
public final class ScriptPackageModule: FinderPlusModule {
    public let package: ScriptPackage

    public init(package: ScriptPackage) {
        self.package = package
    }

    public var manifest: ModuleManifest { package.manifest }
    public var contentHash: String { package.contentHash }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        guard let command = package.commands[invocation.actionID] else {
            throw ModuleError.unknownAction(invocation.actionID)
        }
        let scriptURL = package.directory.appendingPathComponent(command.script)
        let arguments = ScriptArgumentExpander.expand(command.arguments, selection: invocation.selection,
                                                      settings: invocation.settings, packageDirectory: package.directory)
        let executable: URL
        let argv: [String]
        if let interpreter = command.interpreter {
            guard let resolved = ExecutableLocator.locate(interpreter) else {
                throw ModuleError.dependencyMissing(ProcessRunnerError.executableNotFound(interpreter).localizedDescription)
            }
            executable = resolved
            argv = [scriptURL.path] + arguments
        } else {
            executable = scriptURL
            argv = arguments
        }

        let workingDirectory: URL
        switch command.workingDirectory {
        case .package: workingDirectory = package.directory
        case .container: workingDirectory = invocation.selection.destinationFolder ?? package.directory
        }

        context.reporter.log("$ " + ShellQuoting.join([executable.path] + argv))
        let reporter = context.reporter
        let result = try await context.processes.run(
            executable,
            arguments: argv,
            workingDirectory: workingDirectory,
            environment: ScriptArgumentExpander.environment(selection: invocation.selection, settings: invocation.settings,
                                                            packageDirectory: package.directory),
            timeout: command.timeout,
            onOutputLine: { line in reporter.log(line) }
        )
        guard result.succeeded else {
            throw ModuleError.failed("Exit code \(result.exitCode)\n\(result.diagnosticTail)")
        }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch command.output {
        case .none:
            return .none
        case .clipboard:
            await context.system.copyToPasteboard(output)
            return .message(LocalizedText(en: "Copied output to the clipboard.", zhHans: "输出已复制到剪贴板。",
                                          ko: "출력이 클립보드에 복사되었습니다.").localized)
        case .notification:
            let lastLine = output.split(separator: "\n").last.map(String.init)
            return ActionOutcome(message: lastLine)
        }
    }
}

/// Installs, loads and removes script packages under `~/Library/Application Support/FinderPlus/Packages`.
public struct ScriptPackageManager {
    public var directory: URL

    public init(directory: URL = FinderPlusPaths.packagesDirectory) {
        self.directory = directory
    }

    public struct LoadResult {
        public var packages: [ScriptPackage] = []
        public var failures: [(folder: String, error: Error)] = []
    }

    public func loadInstalled() -> LoadResult {
        var result = LoadResult()
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where folder.hasDirectoryPath {
            do {
                result.packages.append(try ScriptPackage.load(from: folder))
            } catch {
                result.failures.append((folder.lastPathComponent, error))
            }
        }
        return result
    }

    /// Parses a package folder without installing it, for the trust review sheet.
    public func inspect(_ folder: URL) throws -> ScriptPackage {
        try ScriptPackage.load(from: folder)
    }

    /// Copies the package into the packages directory, replacing an older copy with the same id.
    /// Configuration is keyed by module id, so settings survive updates.
    public func install(from folder: URL) throws -> ScriptPackage {
        let package = try ScriptPackage.load(from: folder)
        let destination = installedFolder(for: package.manifest.id)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: try stagedCopy(of: folder))
        } else {
            try fileManager.copyItem(at: folder, to: destination)
        }
        return try ScriptPackage.load(from: destination)
    }

    public func uninstall(_ id: String) throws {
        let folder = installedFolder(for: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    public func installedFolder(for id: String) -> URL {
        directory.appendingPathComponent(UniqueFileNamer.sanitizedFileName(id), isDirectory: true)
    }

    private func stagedCopy(of folder: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("finderplus-package-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: folder, to: staging)
        return staging
    }
}
