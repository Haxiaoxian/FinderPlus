import Foundation
import UniformTypeIdentifiers

/// Declarative condition deciding whether an action appears for a Finder selection.
///
/// Rules are evaluated inside the Finder extension on every right-click, so they are pure data:
/// no module code runs to decide visibility.
public struct MenuRule: Codable, Hashable, Sendable {
    public var contexts: Set<MenuContextKind>
    public var minSelection: Int
    public var maxSelection: Int?
    /// Allowed item kinds; `nil` allows any.
    public var itemKinds: Set<ItemKind>?
    /// Allowed lower-cased extensions without dot; `nil` allows any. Like `typeIdentifiers`, this
    /// filters files and packages only: a folder matches whenever `itemKinds` contains `.folder`.
    public var extensions: Set<String>?
    /// Uniform type identifiers an item may conform to (`public.image`). Matched in addition to `extensions`.
    public var typeIdentifiers: [String]?
    /// When `true` every selected item must match; otherwise at least one.
    public var requireAllItemsMatch: Bool

    public init(
        contexts: Set<MenuContextKind> = [.items],
        minSelection: Int = 1,
        maxSelection: Int? = nil,
        itemKinds: Set<ItemKind>? = nil,
        extensions: Set<String>? = nil,
        typeIdentifiers: [String]? = nil,
        requireAllItemsMatch: Bool = true
    ) {
        self.contexts = contexts
        self.minSelection = minSelection
        self.maxSelection = maxSelection
        self.itemKinds = itemKinds
        self.extensions = extensions.map { Set($0.map(Self.normalizeExtension)) }
        self.typeIdentifiers = typeIdentifiers
        self.requireAllItemsMatch = requireAllItemsMatch
    }

    // MARK: Common rules

    /// Background of a folder window only.
    public static let container = MenuRule(contexts: [.container], minSelection: 0)
    /// Any selection or the background (operates on the container then).
    public static let anything = MenuRule(contexts: [.items, .container])
    public static let anyItems = MenuRule(contexts: [.items])

    public static func files(_ extensions: Set<String>? = nil, typeIdentifiers: [String]? = nil, max: Int? = nil) -> MenuRule {
        MenuRule(contexts: [.items], maxSelection: max, itemKinds: [.file, .package], extensions: extensions,
                 typeIdentifiers: typeIdentifiers)
    }

    public static func folders(includeContainer: Bool = false, max: Int? = nil) -> MenuRule {
        MenuRule(contexts: includeContainer ? [.items, .container] : [.items], maxSelection: max, itemKinds: [.folder])
    }

    // MARK: Matching

    public func matches(_ selection: FinderSelection) -> Bool {
        guard contexts.contains(selection.context) else { return false }
        switch selection.context {
        case .container:
            return selection.container != nil
        case .items:
            let count = selection.items.count
            guard count >= max(minSelection, 1) else { return false }
            if let maxSelection, count > maxSelection { return false }
            if requireAllItemsMatch {
                return selection.items.allSatisfy(matches(item:))
            }
            return selection.items.contains(where: matches(item:))
        }
    }

    public func matches(item: SelectedItem) -> Bool {
        if let itemKinds, !itemKinds.contains(item.kind) { return false }
        if item.kind == .folder, itemKinds?.contains(.folder) == true { return true }
        let hasTypeFilter = extensions != nil || typeIdentifiers != nil
        guard hasTypeFilter else { return true }
        if let extensions, extensions.contains(item.pathExtension) { return true }
        if let typeIdentifiers, Self.item(item, conformsToAnyOf: typeIdentifiers) { return true }
        return false
    }

    static func item(_ item: SelectedItem, conformsToAnyOf identifiers: [String]) -> Bool {
        let type: UTType?
        switch item.kind {
        case .folder: type = .folder
        case .package: type = UTType(filenameExtension: item.pathExtension) ?? .package
        case .file: type = UTType(filenameExtension: item.pathExtension)
        }
        guard let type else { return false }
        return identifiers.contains { identifier in
            guard let target = UTType(identifier) else { return false }
            return type.conforms(to: target)
        }
    }

    static func normalizeExtension(_ value: String) -> String {
        var ext = value.trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        return ext
    }

    // MARK: Codable (lenient)

    enum CodingKeys: String, CodingKey {
        case contexts, minSelection, maxSelection, itemKinds, extensions, typeIdentifiers, requireAllItemsMatch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contexts: try container.decode(Set<MenuContextKind>.self, forKey: .contexts, default: [.items]),
            minSelection: try container.decode(Int.self, forKey: .minSelection, default: 1),
            maxSelection: try container.decodeIfPresent(Int.self, forKey: .maxSelection),
            itemKinds: try container.decodeIfPresent(Set<ItemKind>.self, forKey: .itemKinds),
            extensions: try container.decodeIfPresent(Set<String>.self, forKey: .extensions),
            typeIdentifiers: try container.decodeIfPresent([String].self, forKey: .typeIdentifiers),
            requireAllItemsMatch: try container.decode(Bool.self, forKey: .requireAllItemsMatch, default: true)
        )
    }
}
