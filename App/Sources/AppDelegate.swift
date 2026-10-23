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

    func applicationWillFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.presentInteractive = { [weak self] request in self?.presentInteractive(request) }
        installURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI installs its own handlers during launch; make sure ours is the one in place.
        installURLHandler()
        MacSystemServices.requestNotificationAuthorization()

        let launchedNormally = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if launchedNormally {
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
        showMainWindow()
        return false
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
