import Foundation

public enum TerminalApplication: String, Codable, Sendable, CaseIterable {
    case terminal
    case iTerm

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        }
    }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iTerm: return "iTerm2"
        }
    }
}

/// A command to show in a terminal window.
public struct TerminalCommand: Sendable, Hashable {
    public var application: TerminalApplication
    /// Already shell-quoted command line. Build it with ``ShellQuoting`` — never interpolate paths raw.
    public var commandLine: String
    /// `true` runs the command; `false` only types it (iTerm2) or copies it to the clipboard (Terminal).
    public var execute: Bool

    public init(application: TerminalApplication, commandLine: String, execute: Bool) {
        self.application = application
        self.commandLine = commandLine
        self.execute = execute
    }
}

/// System interactions a module may request. Implemented with AppKit by the engine
/// (`MacSystemServices`) and by mocks in tests. All methods may be called from any thread.
public protocol SystemServices: Sendable {
    func copyToPasteboard(_ string: String) async
    /// Opens URLs with an application, or with their default application when `application` is `nil`.
    func open(_ urls: [URL], withApplicationAt application: URL?) async throws
    func applicationURL(bundleIdentifier: String) -> URL?
    func reveal(_ urls: [URL]) async
    /// Starts inline renaming of the item currently selected in Finder (needs Accessibility access).
    func beginRenameInFinder() async throws
    func runInTerminal(_ command: TerminalCommand) async throws
    /// Opens a folder in a new terminal window.
    func openTerminal(_ application: TerminalApplication, at folder: URL) async throws
    func confirm(title: String, message: String, confirmButton: String) async -> Bool
    func promptForText(title: String, message: String, defaultValue: String) async -> String?
    func notify(title: String, body: String) async
}
