import Foundation

/// Folders of cloud-storage providers that use Apple's File Provider (OneDrive, Dropbox, Google
/// Drive, Box, …) plus iCloud Drive. Finder treats these as separate domains, so the Finder
/// extension registers each one explicitly in addition to `/`.
public enum CloudStorageLocations {
    /// Discovers locations by listing `~/Library/CloudStorage`. Must run in the (unsandboxed) host:
    /// the sandboxed extension cannot list that folder, so the host passes the result along in the
    /// menu snapshot.
    public static func discover(home: URL = FinderPlusPaths.realHomeDirectory) -> [String] {
        let fileManager = FileManager.default
        var locations: [String] = []
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let providers = (try? fileManager.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [.skipsHiddenFiles])) ?? []
        for provider in providers.sorted(by: { $0.path < $1.path }) {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: provider.path, isDirectory: &isDirectory), isDirectory.boolValue {
                locations.append(provider.path)
            }
        }
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if fileManager.fileExists(atPath: iCloud.path) { locations.append(iCloud.path) }
        return locations
    }

    /// Whether `url` lives in a cloud-storage location (used for diagnostics).
    public static func isCloudItem(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/Library/CloudStorage/") || path.contains("/Library/Mobile Documents/")
    }
}
