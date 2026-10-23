import AppKit
import FinderPlusCore
import FinderPlusEngine
import FinderPlusUI
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var model: AppModel!
    private var mainWindow: NSWindow?
    private var moduleWindows: [NSWindow] = []
    private var finishedLaunching = false
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    /// Build number this process was launched from; compared with the bundle on disk to detect updates.
    private let runningBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    func applicationWillFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.presentInteractive = { [weak self] request in self?.presentInteractive(request) }
        installURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI installs its own handlers during launch; make sure ours is the one in place.
        installURLHandler()
        MacSystemServices.requestNotificationAuthorization()

        installStatusItem()
        startUpdateWatcher()

        let launchedNormally = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        let relaunchedInBackground = CommandLine.arguments.contains(Self.backgroundArgument)
        if launchedNormally, !relaunchedInBackground {
            showMainWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        finishedLaunching = true
        // The URL only wakes us up; the request itself lives in the shared inbox. Process anything
        // that is waiting, in case the URL event was delivered before we were ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.model.processPendingRequests()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopening after the user replaced FinderPlus.app must start the new version, not show
        // the old one that kept running in the background.
        if relaunchIfUpdated(inBackground: false) { return false }
        showMainWindow()
        return false
    }

    // MARK: Menu bar item & updates

    static let backgroundArgument = "--finderplus-background"

    /// Menu bar icon: the app keeps running without a Dock icon after its window closes, so this
    /// is how the user can always see it is running, reopen it, or quit it.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "FinderPlus"
        let menu = NSMenu()
        menu.addItem(withTitle: HostStrings.openApp.localized, action: #selector(statusOpen), keyEquivalent: "").target = self
        menu.addItem(withTitle: HostStrings.taskCenter.localized, action: #selector(statusTasks), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: HostStrings.quitApp.localized, action: #selector(statusQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    /// The app icon at menu bar size. The icon artwork has a transparent margin, so it is drawn
    /// slightly enlarged to match the visual size of neighbouring menu bar icons.
    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        let image = NSImage(size: size, flipped: false) { rect in
            appIcon.draw(in: rect.insetBy(dx: -1.5, dy: -1.5), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "FinderPlus"
        return image
    }

    @objc private func statusOpen() {
        if relaunchIfUpdated(inBackground: false) { return }
        showMainWindow()
    }

    @objc private func statusTasks() {
        if relaunchIfUpdated(inBackground: false) { return }
        showMainWindow(section: .tasks)
    }

    @objc private func statusQuit() {
        NSApp.terminate(nil)
    }

    private func startUpdateWatcher() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.tasks.running.isEmpty else { return }
                let windowsOpen = (self.mainWindow?.isVisible ?? false) || !self.moduleWindows.isEmpty
                if !windowsOpen { _ = self.relaunchIfUpdated(inBackground: true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// If FinderPlus.app on disk is a different build than this process, starts the new build and quits.
    private func relaunchIfUpdated(inBackground: Bool) -> Bool {
        let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let diskBuild = info["CFBundleVersion"] as? String,
              let runningBuild, diskBuild != runningBuild else { return false }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, then open the new build (in the background if requested).
        relaunch.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; "
            + (inBackground ? "/usr/bin/open -g \"$2\" --args \"$3\"" : "/usr/bin/open \"$2\""),
            "relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath, Self.backgroundArgument]
        do {
            try relaunch.run()
        } catch {
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshExtensionStatus()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { handle($0) }
    }

    // MARK: URL scheme

    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else { return }
        handle(url)
    }

    private func handle(_ url: URL) {
        switch FinderPlusURL.parse(url) {
        case .dispatch:
            model.handle(url: url)
        case .module, .main:
            model.handle(url: url)
            showMainWindow()
        case nil:
            break
        }
    }

    // MARK: Windows

    func showMainWindow(section: SidebarSection? = nil) {
        if let section { model.selection = section }
        NSApp.setActivationPolicy(.regular)
        if mainWindow == nil {
            let root = RootView().environment(model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "FinderPlus"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.setContentSize(NSSize(width: 1080, height: 720))
            window.minSize = NSSize(width: 820, height: 560)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("FinderPlusMainWindow")
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentInteractive(_ request: InteractiveRequest) {
        guard let provider = request.module as? ModuleInteractiveUIProviding else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = request.module.manifest.name.localized
        let context = model.uiContext(for: request.module, selection: request.request.selection) { [weak window] in
            window?.close()
        }
        guard let view = provider.makeInteractiveView(route: request.route, context: context) else { return }
        window.contentViewController = NSHostingController(rootView: view.environment(model))
        window.delegate = self
        window.center()
        moduleWindows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        moduleWindows.removeAll { $0 === window }
        let mainClosing = window === mainWindow
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let mainVisible = !mainClosing && (self.mainWindow?.isVisible ?? false)
            if !mainVisible, self.moduleWindows.isEmpty {
                if self.model.configuration.general.keepRunningInBackground {
                    // Stay available for Finder requests without a Dock icon.
                    NSApp.setActivationPolicy(.accessory)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
