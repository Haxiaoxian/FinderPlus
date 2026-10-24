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
    private var updateWatcher: BundleUpdateWatcher?
    /// Runs only while a new build is waiting for FinderPlus to become idle.
    private var updateRetryTimer: Timer?
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
        // FinderPlus is an agent app (LSUIElement): launching it for a Finder request, a login item
        // or an update never shows a Dock icon. The Dock icon only appears while the window is open.
        if launchedNormally, !relaunchedInBackground {
            showMainWindow()
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

    /// File-system events instead of a polling timer: FinderPlus stays asleep until the app on
    /// disk actually changes.
    private func startUpdateWatcher() {
        let watcher = BundleUpdateWatcher(bundleURL: Bundle.main.bundleURL) { [weak self] in
            self?.relaunchInBackgroundWhenIdle()
        }
        watcher.start()
        updateWatcher = watcher
    }

    private var isUpdatePending: Bool {
        guard let runningBuild, let diskBuild = BundleUpdateWatcher.diskBuild(of: Bundle.main.bundleURL) else { return false }
        return diskBuild != runningBuild
    }

    /// Switches to a new build once nothing is running and no window is open; until then it
    /// checks again every minute (and whenever a window closes).
    private func relaunchInBackgroundWhenIdle() {
        guard isUpdatePending else {
            updateRetryTimer?.invalidate()
            updateRetryTimer = nil
            return
        }
        let idle = model.tasks.running.isEmpty && mainWindow == nil && moduleWindows.isEmpty
        if idle, BundleUpdateWatcher.isComplete(Bundle.main.bundleURL), relaunch(inBackground: true) { return }
        guard updateRetryTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.relaunchInBackgroundWhenIdle() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        updateRetryTimer = timer
    }

    /// If FinderPlus.app on disk is a different build than this process, starts the new build and quits.
    private func relaunchIfUpdated(inBackground: Bool) -> Bool {
        isUpdatePending && relaunch(inBackground: inBackground)
    }

    private func relaunch(inBackground: Bool) -> Bool {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, then open the new build (in the background if requested).
        shell.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; "
            + (inBackground ? "/usr/bin/open -g \"$2\" --args \"$3\"" : "/usr/bin/open \"$2\""),
            "relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath, Self.backgroundArgument]
        do {
            try shell.run()
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
        // After switching from agent to regular, macOS only shows the menu bar once the app is
        // activated again on the next run-loop pass.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.mainWindow?.makeKeyAndOrderFront(nil)
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Closed windows are released together with their SwiftUI views, so FinderPlus idles in
            // the background with no UI in memory; the main window is rebuilt when reopened.
            window.contentViewController = nil
            window.delegate = nil
            if self.mainWindow === window { self.mainWindow = nil }
            if self.mainWindow == nil, self.moduleWindows.isEmpty {
                if self.model.configuration.general.keepRunningInBackground {
                    // Back to agent mode: stay available for Finder requests without a Dock icon.
                    NSApp.setActivationPolicy(.accessory)
                    if self.updateRetryTimer != nil { self.relaunchInBackgroundWhenIdle() }
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
