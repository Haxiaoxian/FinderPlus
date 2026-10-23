import AppKit
import FinderPlusCore

/// Default dependency checks: executables on PATH/well-known directories and apps by bundle id.
public struct DependencyChecker: DependencyChecking {
    public init() {}

    public func statuses(for descriptors: [DependencyDescriptor]) async -> [DependencyStatus] {
        descriptors.compactMap { descriptor in
            let name = descriptor.displayName.localized
            let hint = descriptor.installHint?.localized
            switch descriptor.kind {
            case .executable:
                if let url = locateExecutable(descriptor.executableNames) {
                    return DependencyStatus(id: descriptor.id, displayName: name, state: .satisfied, detail: url.path,
                                            isRequired: descriptor.isRequired, installHint: hint)
                }
                return DependencyStatus(id: descriptor.id, displayName: name, state: .missing,
                                        isRequired: descriptor.isRequired, installHint: hint)
            case .application:
                if let url = locateApplication(descriptor.bundleIdentifiers) {
                    return DependencyStatus(id: descriptor.id, displayName: name, state: .satisfied, detail: url.path,
                                            isRequired: descriptor.isRequired, installHint: hint)
                }
                return DependencyStatus(id: descriptor.id, displayName: name, state: .missing,
                                        isRequired: descriptor.isRequired, installHint: hint)
            case .custom:
                // Custom dependencies are reported by the module's own `dependencyStatuses`.
                return nil
            }
        }
    }

    public func locateExecutable(_ names: [String]) -> URL? {
        ExecutableLocator.locateFirst(names)
    }

    public func locateApplication(_ bundleIdentifiers: [String]) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
        }
        return nil
    }
}
