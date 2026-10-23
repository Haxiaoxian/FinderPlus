import Foundation
import FinderPlusCore
import os

/// Holds every module known to this process: native modules registered at compile time and
/// script packages loaded from disk.
public final class ModuleRegistry {
    public private(set) var modules: [FinderPlusModule] = []
    /// Modules that were rejected (duplicate id, incompatible host API, invalid package…).
    public private(set) var rejected: [RejectedModule] = []

    public struct RejectedModule: Hashable, Sendable {
        public var id: String
        public var reason: String
    }

    private let logger = Logger(subsystem: "io.github.finderplus", category: "registry")

    public init(modules: [FinderPlusModule] = []) {
        modules.forEach { register($0) }
    }

    public func register(_ module: FinderPlusModule) {
        let manifest = module.manifest
        guard !modules.contains(where: { $0.id == manifest.id }) else {
            reject(manifest.id, reason: "Duplicate module identifier")
            return
        }
        guard manifest.isCompatibleWithHost else {
            reject(manifest.id, reason: "Requires host API \(manifest.minimumHostAPI), this FinderPlus provides \(finderPlusHostAPIVersion)")
            return
        }
        let invalidActions = Dictionary(grouping: manifest.actions, by: \.id).filter { $0.value.count > 1 }.keys
        if !invalidActions.isEmpty {
            logger.warning("Module \(manifest.id, privacy: .public) declares duplicate action ids: \(invalidActions.sorted().joined(separator: ", "), privacy: .public)")
        }
        modules.append(module)
    }

    public func unregister(_ id: String) {
        modules.removeAll { $0.id == id }
    }

    public func reject(_ id: String, reason: String) {
        logger.error("Rejected module \(id, privacy: .public): \(reason, privacy: .public)")
        rejected.append(RejectedModule(id: id, reason: reason))
    }

    public func module(_ id: String) -> FinderPlusModule? {
        modules.first { $0.id == id }
    }

    public var manifests: [ModuleManifest] { modules.map(\.manifest) }
}
