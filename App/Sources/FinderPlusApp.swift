import AppKit
import SwiftUI

@main
struct FinderPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Windows are managed by AppDelegate so the app can run headless when Finder wakes it for a
        // request, and reopen its main window from the Dock, Spotlight or the URL scheme.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(HostStrings.settingsMenu.localized) { appDelegate.showMainWindow(section: .general) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button(HostStrings.showMainWindow.localized) { appDelegate.showMainWindow() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
