import Foundation

/// A small ring buffer the Finder extension writes so the host can show what Finder asked for.
/// Used to diagnose locations where the menu does not appear (e.g. cloud-storage folders).
public struct ExtensionDiagnostics: Codable, Sendable {
    public struct Event: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var date: Date
        public var kind: String
        public var detail: String

        public init(kind: String, detail: String, date: Date = Date()) {
            id = UUID()
            self.date = date
            self.kind = kind
            self.detail = detail
        }
    }

    public var events: [Event]

    public static let maximumEvents = 40
    public static var fileURL: URL { FinderPlusPaths.sharedRoot.appendingPathComponent("finder-extension-log.json") }

    public init(events: [Event] = []) {
        self.events = events
    }

    public static func load(from url: URL = fileURL) -> ExtensionDiagnostics {
        (try? FinderPlusJSON.read(ExtensionDiagnostics.self, from: url)) ?? ExtensionDiagnostics()
    }

    /// Appends an event; failures are ignored because diagnostics must never affect Finder.
    public static func record(_ kind: String, _ detail: String, to url: URL = fileURL) {
        var log = load(from: url)
        log.events.append(Event(kind: kind, detail: detail))
        if log.events.count > maximumEvents { log.events.removeFirst(log.events.count - maximumEvents) }
        try? FinderPlusJSON.write(log, to: url, pretty: false)
    }

    public static func clear(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Plain-text report for pasting into a bug report.
    public var report: String {
        let formatter = ISO8601DateFormatter()
        return events.map { "\(formatter.string(from: $0.date)) [\($0.kind)] \($0.detail)" }.joined(separator: "\n")
    }
}
