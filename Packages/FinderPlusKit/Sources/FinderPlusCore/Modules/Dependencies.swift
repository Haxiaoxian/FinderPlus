import Foundation

public struct DependencyStatus: Hashable, Sendable, Identifiable {
    public enum State: Hashable, Sendable {
        case satisfied
        case missing
        /// Present but problematic (old version, wrong architecture, …).
        case warning(String)
    }

    public var id: String
    public var displayName: String
    public var state: State
    /// Where the dependency was found, or other detail such as a version string.
    public var detail: String?
    public var isRequired: Bool
    public var installHint: String?
    /// A `hostOnly` action of the same module that installs or repairs the dependency.
    public var fixActionID: String?

    public init(id: String, displayName: String, state: State, detail: String? = nil, isRequired: Bool = true,
                installHint: String? = nil, fixActionID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.detail = detail
        self.isRequired = isRequired
        self.installHint = installHint
        self.fixActionID = fixActionID
    }

    public var isSatisfied: Bool { state == .satisfied }
}

/// Generic dependency checks offered to modules.
public protocol DependencyChecking: Sendable {
    func statuses(for descriptors: [DependencyDescriptor]) async -> [DependencyStatus]
    func locateExecutable(_ names: [String]) -> URL?
    func locateApplication(_ bundleIdentifiers: [String]) -> URL?
}

extension DependencyChecking {
    public func status(for descriptor: DependencyDescriptor) async -> DependencyStatus {
        await statuses(for: [descriptor]).first
            ?? DependencyStatus(id: descriptor.id, displayName: descriptor.displayName.localized, state: .missing)
    }
}
