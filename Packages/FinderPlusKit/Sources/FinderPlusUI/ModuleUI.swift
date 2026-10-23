import FinderPlusCore
import SwiftUI

/// What the host hands to a module's custom view.
@MainActor
public struct ModuleUIContext {
    public var moduleID: String
    /// Live, persisted settings of the module. Writes are saved and the menu is republished.
    public var settings: Binding<ModuleSettings>
    /// The Finder selection that triggered an interactive action (`.empty` for settings views).
    public var selection: FinderSelection
    public var dataDirectory: URL
    public var system: SystemServices
    /// Dispatches one of the module's actions through the engine (tracked in the task center).
    public var perform: (_ actionID: String, _ parameters: [String: String], _ selection: FinderSelection) -> Void
    /// Closes the window hosting an interactive view.
    public var dismiss: () -> Void

    public init(moduleID: String, settings: Binding<ModuleSettings>, selection: FinderSelection, dataDirectory: URL,
                system: SystemServices,
                perform: @escaping (_ actionID: String, _ parameters: [String: String], _ selection: FinderSelection) -> Void,
                dismiss: @escaping () -> Void) {
        self.moduleID = moduleID
        self.settings = settings
        self.selection = selection
        self.dataDirectory = dataDirectory
        self.system = system
        self.perform = perform
        self.dismiss = dismiss
    }
}

/// Adopt to show a custom SwiftUI section below (or instead of) the generated settings form.
public protocol ModuleSettingsViewProviding {
    /// When `true` the generated form is hidden and only the custom view is shown.
    var replacesGeneratedSettings: Bool { get }
    @MainActor func makeSettingsView(context: ModuleUIContext) -> AnyView
}

extension ModuleSettingsViewProviding {
    public var replacesGeneratedSettings: Bool { false }
}

/// Adopt to provide windows for actions with ``ExecutionStyle/interactive(route:)``.
public protocol ModuleInteractiveUIProviding {
    @MainActor func makeInteractiveView(route: String, context: ModuleUIContext) -> AnyView?
}

/// Adopt to add pages to the host's "Icons" or "Templates" sections.
public protocol ModuleLibraryProviding {
    var librarySection: ModuleLibrarySection { get }
    @MainActor func makeLibraryView(context: ModuleUIContext) -> AnyView
}

public enum ModuleLibrarySection: String, Sendable {
    case templates, icons
}
