import CryptoKit
import Foundation
import FinderPlusCore

/// How a script package action runs. Declared per action under `"run"` in `finderplus-package.json`.
///
/// ```json
/// "run": {
///   "interpreter": "python3",
///   "script": "scripts/count.py",
///   "arguments": ["--mode", "{setting:mode}", "{files}"],
///   "workingDirectory": "container",
///   "output": "notification",
///   "timeout": 60
/// }
/// ```
public struct ScriptCommand: Codable, Hashable, Sendable {
    public enum WorkingDirectory: String, Codable, Sendable {
        /// The folder the menu was opened in, or the parent of the first selected item.
        case container
        /// The package's own folder.
        case package
    }

    public enum Output: String, Codable, Sendable {
        case none
        /// Show the last line of standard output as the task message / notification.
        case notification
        /// Copy standard output to the clipboard.
        case clipboard
    }

    /// Absolute path or command name (`python3`, `zsh`). `nil` executes the script file directly.
    public var interpreter: String?
    /// Path of the script relative to the package folder.
    public var script: String
    public var arguments: [String]
    public var workingDirectory: WorkingDirectory
    public var output: Output
    public var timeout: TimeInterval?

    enum CodingKeys: String, CodingKey { case interpreter, script, arguments, workingDirectory, output, timeout }

    public init(interpreter: String?, script: String, arguments: [String] = ["{files}"],
                workingDirectory: WorkingDirectory = .container, output: Output = .notification, timeout: TimeInterval? = 300) {
        self.interpreter = interpreter
        self.script = script
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.output = output
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interpreter = try container.decodeIfPresent(String.self, forKey: .interpreter)
        script = try container.decode(String.self, forKey: .script)
        arguments = try container.decode([String].self, forKey: .arguments, default: ["{files}"])
        workingDirectory = try container.decode(WorkingDirectory.self, forKey: .workingDirectory, default: .container)
        output = try container.decode(Output.self, forKey: .output, default: .notification)
        timeout = try container.decode(TimeInterval?.self, forKey: .timeout, default: 300)
    }

    /// Human-readable command line shown in the trust dialog.
    public var displayCommand: String {
        ShellQuoting.join((interpreter.map { [$0] } ?? []) + [script] + arguments)
    }
}

public enum ScriptPackageError: LocalizedError, Equatable {
    case missingManifest
    case invalidManifest(String)
    case unsupportedFormat(Int)
    case scriptOutsidePackage(String)
    case scriptMissing(String)
    case actionWithoutCommand(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "finderplus-package.json not found."
        case .invalidManifest(let detail):
            return "Invalid finderplus-package.json: \(detail)"
        case .unsupportedFormat(let version):
            return "Unsupported package format version \(version)."
        case .scriptOutsidePackage(let path):
            return "Script path escapes the package folder: \(path)"
        case .scriptMissing(let path):
            return "Script not found: \(path)"
        case .actionWithoutCommand(let id):
            return "Action “\(id)” has no \"run\" definition."
        }
    }
}

/// A parsed, validated script package folder.
public struct ScriptPackage: Sendable {
    public static let manifestFileName = "finderplus-package.json"
    public static let supportedFormatVersion = 1

    public var directory: URL
    public var manifest: ModuleManifest
    public var commands: [String: ScriptCommand]
    /// SHA-256 over every file in the package. Trust is bound to this value.
    public var contentHash: String
    public var files: [String]

    public static func load(from directory: URL) throws -> ScriptPackage {
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ScriptPackageError.missingManifest }
        let data = try Data(contentsOf: manifestURL)

        struct Header: Decodable { var formatVersion: Int? }
        struct ActionCommands: Decodable {
            struct Entry: Decodable { var id: String; var run: ScriptCommand? }
            var actions: [Entry]?
        }

        let decoder = FinderPlusJSON.decoder()
        do {
            let header = try decoder.decode(Header.self, from: data)
            let format = header.formatVersion ?? 1
            guard format <= supportedFormatVersion else { throw ScriptPackageError.unsupportedFormat(format) }

            var manifest = try decoder.decode(ModuleManifest.self, from: data)
            // A package can never claim to be native or bypass trust by declaring itself stable+enabled.
            manifest.kind = .scriptPackage
            manifest.enabledByDefault = false
            if !manifest.permissions.contains(.runProcesses) {
                manifest.permissions.append(.runProcesses)
            }

            let entries = try decoder.decode(ActionCommands.self, from: data).actions ?? []
            var commands: [String: ScriptCommand] = [:]
            for entry in entries {
                guard let run = entry.run else { throw ScriptPackageError.actionWithoutCommand(entry.id) }
                try validate(run, in: directory)
                commands[entry.id] = run
            }
            for action in manifest.actions where commands[action.id] == nil {
                throw ScriptPackageError.actionWithoutCommand(action.id)
            }
            // Script actions are always tracked tasks: their output and failures belong in the task center.
            manifest.actions = manifest.actions.map { action in
                var action = action
                if case .interactive = action.execution { action.execution = .task }
                return action
            }

            let (hash, files) = try computeHash(of: directory)
            return ScriptPackage(directory: directory, manifest: manifest, commands: commands, contentHash: hash, files: files)
        } catch let error as ScriptPackageError {
            throw error
        } catch let error as DecodingError {
            throw ScriptPackageError.invalidManifest(String(describing: error))
        }
    }

    static func validate(_ command: ScriptCommand, in directory: URL) throws {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let scriptURL = directory.appendingPathComponent(command.script).standardizedFileURL.resolvingSymlinksInPath()
        guard scriptURL.path.hasPrefix(root + "/") else {
            throw ScriptPackageError.scriptOutsidePackage(command.script)
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw ScriptPackageError.scriptMissing(command.script)
        }
    }

    /// Hash of relative paths and contents, in sorted order, so any edit invalidates trust.
    public static func computeHash(of directory: URL) throws -> (String, [String]) {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: []) else { return ("", []) }
        var files: [(String, URL)] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            if relative == ".DS_Store" || relative.hasSuffix("/.DS_Store") { continue }
            files.append((relative, url))
        }
        files.sort { $0.0 < $1.0 }
        var hasher = SHA256()
        for (relative, url) in files {
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: url))
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, files.map(\.0))
    }
}

/// Expands `{files}`, `{file}`, `{folder}`, `{package}` and `{setting:key}` into an argument vector.
/// `{files}` must be a whole argument and expands to one argument per selected path. Values are
/// passed as separate argv entries — they are never parsed by a shell.
public enum ScriptArgumentExpander {
    public static func expand(_ arguments: [String], selection: FinderSelection, settings: ModuleSettings,
                              packageDirectory: URL) -> [String] {
        let paths = selection.targetURLs.map(\.path)
        let folder = selection.destinationFolder?.path ?? ""
        return arguments.flatMap { argument -> [String] in
            if argument == "{files}" { return paths }
            var value = argument
                .replacingOccurrences(of: "{file}", with: paths.first ?? "")
                .replacingOccurrences(of: "{folder}", with: folder)
                .replacingOccurrences(of: "{package}", with: packageDirectory.path)
            while let range = value.range(of: #"\{setting:([A-Za-z0-9_.-]+)\}"#, options: .regularExpression) {
                let key = String(value[range].dropFirst("{setting:".count).dropLast())
                value.replaceSubrange(range, with: settings.string(key))
            }
            return [value]
        }
    }

    public static func environment(selection: FinderSelection, settings: ModuleSettings, packageDirectory: URL) -> [String: String] {
        var environment = [
            "FINDERPLUS_PACKAGE_DIR": packageDirectory.path,
            "FINDERPLUS_SELECTION": selection.targetURLs.map(\.path).joined(separator: "\n"),
            "FINDERPLUS_CONTAINER": selection.destinationFolder?.path ?? "",
            "FINDERPLUS_CONTEXT": selection.context.rawValue,
        ]
        for (key, _) in settings.defaults.merging(settings.values, uniquingKeysWith: { $1 }) {
            let name = "FINDERPLUS_SETTING_" + key.uppercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            environment[name] = settings.string(key)
        }
        return environment
    }
}
