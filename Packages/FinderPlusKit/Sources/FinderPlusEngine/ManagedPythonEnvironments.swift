import CryptoKit
import FinderPlusCore
import Foundation

/// One-click Python environments for modules.
///
/// Layout under `~/Library/Application Support/FinderPlus/Runtimes`:
///   `bin/uv`        pinned uv release, verified against the SHA-256 below
///   `python/`       standalone CPython builds installed by uv
///   `envs/<name>/`  one virtual environment per module
/// Everything stays inside FinderPlus' folder, so removing it leaves the system untouched.
public struct ManagedPythonEnvironments: PythonEnvironmentProviding {
    static let uvVersion = "0.13.5"
    static let uvChecksums = [
        "aarch64": "743f85035a1996ecb350659e01cd9faea9709829be09b1b4b03c73eaf3c9cd73",
        "x86_64": "b0f52b0e3945b4107d89024ea38e625683011fbfc05a0d98f9fa2d6dcee28c66",
    ]

    let root: URL
    let processes: ProcessRunner

    public init(root: URL = FinderPlusPaths.runtimesDirectory, processes: ProcessRunner = ProcessRunner()) {
        self.root = root
        self.processes = processes
    }

    var uvExecutable: URL { root.appendingPathComponent("bin/uv") }

    var environment: [String: String] {
        [
            "UV_PYTHON_INSTALL_DIR": root.appendingPathComponent("python", isDirectory: true).path,
            "UV_CACHE_DIR": root.appendingPathComponent("cache", isDirectory: true).path,
            "UV_NO_CONFIG": "1",
            "UV_NO_PROGRESS": "1",
            "PYTHONIOENCODING": "utf-8",
        ]
    }

    public func environmentDirectory(named name: String) -> URL {
        root.appendingPathComponent("envs", isDirectory: true)
            .appendingPathComponent(UniqueFileNamer.sanitizedFileName(name), isDirectory: true)
    }

    public func executable(_ command: String, inEnvironment name: String) -> URL? {
        let url = environmentDirectory(named: name).appendingPathComponent("bin/\(command)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public func removeEnvironment(named name: String) throws {
        let folder = environmentDirectory(named: name)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    public func prepareEnvironment(named name: String, pythonVersion: String, packages: [String],
                                   reporter: TaskReporter) async throws -> URL {
        let uv = try await ensureUV(reporter: reporter)
        let folder = environmentDirectory(named: name)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)

        reporter.progress(0.25, message: Strings.installingPython.replacing("version", with: pythonVersion).localized)
        try await run(uv, ["venv", "--managed-python", "--python", pythonVersion, "--allow-existing", folder.path],
                      reporter: reporter)

        reporter.progress(0.5, message: Strings.installingPackages.replacing("packages", with: packages.joined(separator: ", ")).localized)
        let python = folder.appendingPathComponent("bin/python")
        try await run(uv, ["pip", "install", "--python", python.path, "--upgrade"] + packages, reporter: reporter)
        // Keep the disk footprint down; the cache is only needed during installation.
        _ = try? await processes.run(uv, arguments: ["cache", "prune"], environment: environment, timeout: 300)
        reporter.progress(1, message: nil)
        return folder
    }

    private func run(_ uv: URL, _ arguments: [String], reporter: TaskReporter) async throws {
        try Task.checkCancellation()
        reporter.log("$ " + ShellQuoting.join([uv.path] + arguments))
        let result = try await processes.run(uv, arguments: arguments, environment: environment, timeout: 3600,
                                             onOutputLine: { reporter.log($0) })
        guard result.succeeded else { throw ModuleError.failed(result.diagnosticTail) }
    }

    /// Downloads the pinned uv build for this Mac's architecture and verifies its checksum.
    func ensureUV(reporter: TaskReporter) async throws -> URL {
        if FileManager.default.isExecutableFile(atPath: uvExecutable.path) { return uvExecutable }
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif
        let asset = "uv-\(arch)-apple-darwin"
        let url = URL(string: "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/\(asset).tar.gz")!
        reporter.progress(0.05, message: Strings.downloadingUV.localized)
        reporter.log("Downloading \(url.absoluteString)")
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModuleError.failed(Strings.downloadFailed.localized + " (\(url.host ?? ""))")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.uvChecksums[arch] else {
            throw ModuleError.failed("uv checksum mismatch: \(digest)")
        }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("finderplus-uv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let untar = try await processes.run(URL(fileURLWithPath: "/usr/bin/tar"),
                                            arguments: ["-xzf", download.path, "-C", staging.path])
        guard untar.succeeded else { throw ModuleError.failed(untar.diagnosticTail) }

        let extracted = staging.appendingPathComponent("\(asset)/uv")
        try FileManager.default.createDirectory(at: uvExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: uvExecutable.path) {
            try FileManager.default.removeItem(at: uvExecutable)
        }
        try FileManager.default.moveItem(at: extracted, to: uvExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uvExecutable.path)
        reporter.log("uv \(Self.uvVersion) installed at \(uvExecutable.path)")
        return uvExecutable
    }

    enum Strings {
        static let downloadingUV = LocalizedText(en: "Downloading the Python installer (uv)…", zhHans: "正在下载 Python 安装工具（uv）…",
                                                 ko: "Python 설치 도구(uv) 다운로드 중…")
        static let installingPython = LocalizedText(en: "Preparing Python {version}…", zhHans: "正在准备 Python {version}…",
                                                    ko: "Python {version} 준비 중…")
        static let installingPackages = LocalizedText(en: "Installing {packages}…", zhHans: "正在安装 {packages}…",
                                                      ko: "{packages} 설치 중…")
        static let downloadFailed = LocalizedText(en: "Download failed. Check the network connection.", zhHans: "下载失败，请检查网络连接。",
                                                  ko: "다운로드에 실패했습니다. 네트워크 연결을 확인하세요.")
    }
}
