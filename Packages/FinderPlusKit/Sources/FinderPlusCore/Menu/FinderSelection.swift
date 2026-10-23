import Foundation

/// Which Finder context menu the user opened.
public enum MenuContextKind: String, Codable, Sendable, CaseIterable {
    /// Right-click on one or more selected items.
    case items
    /// Right-click on the empty background of a folder window.
    case container
}

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case file
    case folder
    /// Bundle directory presented as a single file (`.app`, `.rtfd`, …).
    case package
}

public struct SelectedItem: Codable, Hashable, Sendable {
    public var url: URL
    public var kind: ItemKind

    public init(url: URL, kind: ItemKind) {
        self.url = url.standardizedFileURL
        self.kind = kind
    }

    /// Lower-cased extension without the dot (`""` for none).
    public var pathExtension: String { url.pathExtension.lowercased() }
    public var path: String { url.path }
    public var name: String { url.lastPathComponent }

    /// Inspects the file system to determine the kind of `url`.
    ///
    /// Inside the sandboxed Finder extension, metadata of File Provider items (OneDrive, Dropbox,
    /// iCloud Drive…) can be unreadable. Then the URL's trailing slash decides, and a name without an
    /// extension is assumed to be a folder; the host re-inspects before running anything.
    public static func inspect(_ url: URL) -> SelectedItem {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
           let isDirectory = values.isDirectory {
            if isDirectory { return SelectedItem(url: url, kind: values.isPackage == true ? .package : .folder) }
            return SelectedItem(url: url, kind: .file)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return SelectedItem(url: url, kind: isDirectory.boolValue ? .folder : .file)
        }
        if url.hasDirectoryPath || url.pathExtension.isEmpty {
            return SelectedItem(url: url, kind: .folder)
        }
        return SelectedItem(url: url, kind: .file)
    }
}

/// The Finder state an action is invoked on.
public struct FinderSelection: Codable, Hashable, Sendable {
    public var context: MenuContextKind
    public var items: [SelectedItem]
    /// The folder the menu was opened in (Finder's "targeted URL").
    public var container: URL?

    public init(context: MenuContextKind, items: [SelectedItem], container: URL?) {
        self.context = context
        self.items = items
        self.container = container?.standardizedFileURL
    }

    public static func items(_ urls: [URL], container: URL? = nil) -> FinderSelection {
        FinderSelection(context: .items, items: urls.map(SelectedItem.inspect), container: container)
    }

    public static func container(_ url: URL) -> FinderSelection {
        FinderSelection(context: .container, items: [], container: url)
    }

    public static let empty = FinderSelection(context: .items, items: [], container: nil)

    /// The URLs an action should operate on: the selected items, or the container for background clicks.
    public var targetURLs: [URL] {
        switch context {
        case .items: return items.map(\.url)
        case .container: return container.map { [$0] } ?? []
        }
    }

    /// Folder that new files should be created in: the container, or the single selected folder.
    public var destinationFolder: URL? {
        if context == .container { return container }
        if items.count == 1, items[0].kind == .folder { return items[0].url }
        return container ?? items.first?.url.deletingLastPathComponent()
    }

    public var files: [SelectedItem] { items.filter { $0.kind != .folder } }
    public var folders: [SelectedItem] { items.filter { $0.kind == .folder } }
}
