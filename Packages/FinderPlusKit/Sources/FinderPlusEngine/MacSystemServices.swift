import AppKit
import ApplicationServices
import FinderPlusCore
import UserNotifications

public enum SystemServiceError: LocalizedError {
    case appleScript(String)
    case accessibilityNotGranted

    public var errorDescription: String? {
        switch self {
        case .appleScript(let message):
            return message
        case .accessibilityNotGranted:
            return LocalizedText(
                en: "FinderPlus needs Accessibility access to start renaming in Finder. Enable it in System Settings › Privacy & Security › Accessibility.",
                zhHans: "FinderPlus 需要“辅助功能”权限才能让 Finder 进入重命名状态。请在“系统设置 › 隐私与安全性 › 辅助功能”中开启。",
                ko: "Finder에서 이름 변경을 시작하려면 손쉬운 사용 권한이 필요합니다. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 허용하세요."
            ).localized
        }
    }
}

/// AppKit implementation of ``SystemServices`` used by the host app.
public final class MacSystemServices: SystemServices, @unchecked Sendable {
    public init() {}

    public func copyToPasteboard(_ string: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    public func open(_ urls: [URL], withApplicationAt application: URL?) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let application {
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        } else {
            for url in urls {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            }
        }
    }

    public func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func reveal(_ urls: [URL]) async {
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    public func beginRenameInFinder() async throws {
        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            throw SystemServiceError.accessibilityNotGranted
        }
        // Give Finder a moment to finish selecting the new item, then press Return.
        try await Task.sleep(nanoseconds: 350_000_000)
        try await runAppleScript("""
        tell application "Finder" to activate
        delay 0.15
        tell application "System Events" to tell process "Finder" to key code 36
        """)
    }

    public func runInTerminal(_ command: TerminalCommand) async throws {
        let line = AppleScriptString.literal(command.commandLine)
        switch command.application {
        case .terminal:
            if command.execute {
                try await runAppleScript("""
                tell application id "com.apple.Terminal"
                    activate
                    do script \(line)
                end tell
                """)
            } else {
                // Terminal.app cannot type text without executing it; hand the command over via the clipboard.
                await copyToPasteboard(command.commandLine)
                try await runAppleScript("""
                tell application id "com.apple.Terminal"
                    activate
                    do script ""
                end tell
                """)
                await notify(
                    title: "Terminal",
                    body: LocalizedText(en: "Command copied — press ⌘V to paste it.", zhHans: "命令已复制，按 ⌘V 粘贴即可。",
                                        ko: "명령이 복사되었습니다. ⌘V로 붙여 넣으세요.").localized
                )
            }
        case .iTerm:
            try await runAppleScript("""
            tell application id "com.googlecode.iterm2"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text \(line) newline \(command.execute ? "true" : "false")
                end tell
            end tell
            """)
        }
    }

    public func openTerminal(_ application: TerminalApplication, at folder: URL) async throws {
        guard let appURL = applicationURL(bundleIdentifier: application.bundleIdentifier) else {
            throw ModuleError.dependencyMissing(
                LocalizedText(en: "\(application.displayName) is not installed.", zhHans: "未安装 \(application.displayName)。",
                              ko: "\(application.displayName)이(가) 설치되어 있지 않습니다.").localized
            )
        }
        try await open([folder], withApplicationAt: appURL)
    }

    public func confirm(title: String, message: String, confirmButton: String) async -> Bool {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: confirmButton)
            alert.addButton(withTitle: LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized)
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    public func promptForText(title: String, message: String, defaultValue: String) async -> String? {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: LocalizedText(en: "OK", zhHans: "好", ko: "확인").localized)
            alert.addButton(withTitle: LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = defaultValue
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    public func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Requests notification permission once; call at launch.
    public static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    private func runAppleScript(_ source: String) async throws {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw SystemServiceError.appleScript("Invalid AppleScript")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            let code = errorInfo[NSAppleScript.errorNumber] as? Int
            if code == -1743 {
                throw SystemServiceError.appleScript(LocalizedText(
                    en: "FinderPlus is not allowed to control this app. Enable it in System Settings › Privacy & Security › Automation.",
                    zhHans: "FinderPlus 没有控制该应用的权限。请在“系统设置 › 隐私与安全性 › 自动化”中允许。",
                    ko: "FinderPlus가 이 앱을 제어할 권한이 없습니다. 시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 허용하세요."
                ).localized)
            }
            throw SystemServiceError.appleScript(message)
        }
    }
}
