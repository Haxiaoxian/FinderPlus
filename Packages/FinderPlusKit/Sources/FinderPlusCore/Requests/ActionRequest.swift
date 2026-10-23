import Foundation

/// A user's click on a menu item, handed from the Finder extension (or the host UI) to the engine.
public struct ActionRequest: Codable, Hashable, Sendable, Identifiable {
    public enum Origin: String, Codable, Sendable {
        case finder, host
    }

    public var id: UUID
    public var moduleID: String
    public var actionID: String
    public var parameters: [String: String]
    public var selection: FinderSelection
    public var origin: Origin
    public var createdAt: Date

    public init(id: UUID = UUID(), moduleID: String, actionID: String, parameters: [String: String] = [:],
                selection: FinderSelection, origin: Origin, createdAt: Date = Date()) {
        self.id = id
        self.moduleID = moduleID
        self.actionID = actionID
        self.parameters = parameters
        self.selection = selection
        self.origin = origin
        self.createdAt = createdAt
    }

    public var key: String { ActionDescriptor.key(moduleID: moduleID, actionID: actionID) }
}

/// Request hand-off through the shared container.
///
/// The extension writes `<id>.json` into the inbox and then opens `finderplus://dispatch?id=<id>`,
/// which launches the host if needed. The URL carries only the identifier, so other apps cannot
/// inject work through the URL scheme: the request itself must exist in the App Group container.
public struct RequestInbox: Sendable {
    public let directory: URL
    /// Requests older than this are discarded instead of executed (e.g. after a crash or reboot).
    public var maximumAge: TimeInterval = 120

    public init(directory: URL = FinderPlusPaths.inboxDirectory) {
        self.directory = directory
    }

    @discardableResult
    public func submit(_ request: ActionRequest) throws -> URL {
        let url = fileURL(for: request.id)
        try FinderPlusJSON.write(request, to: url, pretty: false)
        return url
    }

    /// Reads and removes a request. Returns `nil` if it does not exist or has expired.
    public func take(_ id: UUID, now: Date = Date()) -> ActionRequest? {
        let url = fileURL(for: id)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let request = try? FinderPlusJSON.read(ActionRequest.self, from: url) else { return nil }
        guard request.id == id, now.timeIntervalSince(request.createdAt) <= maximumAge else { return nil }
        return request
    }

    /// Takes every pending request (used at launch in case a URL event was missed).
    public func takeAll(now: Date = Date()) -> [ActionRequest] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .compactMap { take($0, now: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}

/// `finderplus://` URLs understood by the host.
public enum FinderPlusURL {
    public static let scheme = "finderplus"

    public static func dispatch(_ id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "dispatch"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url!
    }

    public static func openModule(_ moduleID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "module"
        components.queryItems = [URLQueryItem(name: "id", value: moduleID)]
        return components.url!
    }

    public enum Route: Equatable, Sendable {
        case dispatch(UUID)
        case module(String)
        case main
    }

    public static func parse(_ url: URL) -> Route? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = components.queryItems?.first(where: { $0.name == "id" })?.value
        switch components.host?.lowercased() {
        case "dispatch":
            guard let id, let uuid = UUID(uuidString: id) else { return nil }
            return .dispatch(uuid)
        case "module":
            guard let id, !id.isEmpty else { return nil }
            return .module(id)
        case nil, "", "main":
            return .main
        default:
            return nil
        }
    }
}
