import Foundation
import Security

/// Notices when FinderPlus.app on disk is replaced by another build, without polling.
///
/// Two places are watched: the bundle's Info.plist (a bundle overwritten in place) and the folder
/// that holds the bundle (the app replaced by a new copy, e.g. dragged from the DMG). Events are
/// coalesced; the owner then decides whether to relaunch.
@MainActor
final class BundleUpdateWatcher {
    private let bundleURL: URL
    private let onChange: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    init(bundleURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.bundleURL = bundleURL
        self.onChange = onChange
    }

    func start() {
        arm()
    }

    /// Build number (CFBundleVersion) of the bundle currently on disk.
    static func diskBuild(of bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleVersion"] as? String
    }

    /// True when the bundle's code signature is intact. A copy that is still being written is not,
    /// so this keeps a background relaunch from starting a half-copied app.
    static func isComplete(_ bundleURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    private func arm() {
        sources.forEach { $0.cancel() }
        sources = [bundleURL.deletingLastPathComponent(), bundleURL.appendingPathComponent("Contents/Info.plist")]
            .compactMap(watch)
    }

    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .extend, .attrib, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Info.plist may now be a different file (or the old one moved to the Trash).
                self.arm()
                self.onChange()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
