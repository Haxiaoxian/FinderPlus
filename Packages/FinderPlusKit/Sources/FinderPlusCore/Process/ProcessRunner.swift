import Foundation

/// Finds command-line tools. GUI apps inherit a minimal PATH, so Homebrew, MacPorts, Conda and
/// user-local locations are searched explicitly. Apple Silicon Homebrew (`/opt/homebrew`) comes first.
public enum ExecutableLocator {
    public static let wellKnownDirectories: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/opt/local/bin",
        "~/.local/bin",
        "~/miniforge3/bin",
        "~/miniconda3/bin",
        "~/anaconda3/bin",
        "/opt/homebrew/Caskroom/miniforge/base/bin",
        "/opt/homebrew/Caskroom/miniconda/base/bin",
        "/Library/Frameworks/R.framework/Resources/bin",
        "/Library/Frameworks/Python.framework/Versions/Current/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    public static var searchDirectories: [String] {
        let environmentPath = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (wellKnownDirectories + environmentPath)
            .map { NSString(string: $0).expandingTildeInPath }
            .filter { seen.insert($0).inserted }
    }

    /// Resolves `name` (a bare command or an absolute/tilde path) to an executable file URL.
    public static func locate(_ name: String, extraDirectories: [String] = []) -> URL? {
        let fileManager = FileManager.default
        if name.contains("/") {
            let path = NSString(string: name).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for directory in extraDirectories.map({ NSString(string: $0).expandingTildeInPath }) + searchDirectories {
            let path = (directory as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    public static func locateFirst(_ names: [String], extraDirectories: [String] = []) -> URL? {
        for name in names {
            if let url = locate(name, extraDirectories: extraDirectories) { return url }
        }
        return nil
    }

    /// PATH value that includes the well-known directories, for child processes.
    public static var augmentedPATH: String {
        searchDirectories.joined(separator: ":")
    }
}

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public var succeeded: Bool { exitCode == 0 }

    /// Last lines of stderr (or stdout) for error messages.
    public var diagnosticTail: String {
        let source = standardError.isEmpty ? standardOutput : standardError
        return source.split(separator: "\n").suffix(8).joined(separator: "\n")
    }
}

public enum ProcessRunnerError: LocalizedError {
    case executableNotFound(String)
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return LocalizedText(en: "Executable not found: \(name)", zhHans: "找不到可执行文件：\(name)",
                                 ko: "실행 파일을 찾을 수 없음: \(name)").localized
        case .timedOut(let seconds):
            return LocalizedText(en: "Timed out after \(Int(seconds)) s", zhHans: "\(Int(seconds)) 秒后超时",
                                 ko: "\(Int(seconds))초 후 시간 초과").localized
        }
    }
}

/// Runs a program with an argument vector — never through a shell — so paths and user values
/// cannot be interpreted as shell syntax. Cancelling the calling task terminates the process.
public final class ProcessRunner: Sendable {
    public init() {}

    public func run(
        _ executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        var mergedEnvironment = ProcessInfo.processInfo.environment
        mergedEnvironment["PATH"] = ExecutableLocator.augmentedPATH
        mergedEnvironment["LANG"] = mergedEnvironment["LANG"] ?? "en_US.UTF-8"
        mergedEnvironment.merge(environment) { _, new in new }
        process.environment = mergedEnvironment
        process.standardInput = FileHandle.nullDevice

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let collector = OutputCollector(onLine: onOutputLine)
        output.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, toError: false)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, toError: true)
        }

        let timeoutState = TimeoutFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                process.terminationHandler = { finished in
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    collector.append(output.fileHandleForReading.readDataToEndOfFile(), toError: false)
                    collector.append(errors.fileHandleForReading.readDataToEndOfFile(), toError: true)
                    if timeoutState.isSet, let timeout {
                        continuation.resume(throwing: ProcessRunnerError.timedOut(timeout))
                        return
                    }
                    let (stdout, stderr) = collector.finish()
                    continuation.resume(returning: ProcessResult(exitCode: finished.terminationStatus,
                                                                 standardOutput: stdout, standardError: stderr))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            timeoutState.set()
                            process.terminate()
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Resolves `name` with ``ExecutableLocator`` and runs it.
    public func run(
        command name: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        guard let executable = ExecutableLocator.locate(name) else {
            throw ProcessRunnerError.executableNotFound(name)
        }
        return try await run(executable, arguments: arguments, workingDirectory: workingDirectory,
                             environment: environment, timeout: timeout)
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Thread-safe accumulation of process output with optional line callbacks.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var pendingLine = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data, toError: Bool) {
        guard !data.isEmpty else { return }
        var lines: [String] = []
        lock.withLock {
            if toError { stderr.append(data) } else { stdout.append(data) }
            guard onLine != nil else { return }
            pendingLine.append(data)
            while let newline = pendingLine.firstIndex(of: 0x0A) {
                let lineData = pendingLine[pendingLine.startIndex..<newline]
                lines.append(String(decoding: lineData, as: UTF8.self))
                pendingLine.removeSubrange(pendingLine.startIndex...newline)
            }
        }
        lines.forEach { onLine?($0) }
    }

    func finish() -> (String, String) {
        lock.withLock {
            if !pendingLine.isEmpty {
                onLine?(String(decoding: pendingLine, as: UTF8.self))
                pendingLine.removeAll()
            }
            return (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
        }
    }
}
