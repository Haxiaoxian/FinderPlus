import Foundation
import FinderPlusCore
import Observation

public struct TaskRecord: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running, succeeded, failed, cancelled
    }

    public var id: UUID
    public var moduleID: String
    public var moduleName: String
    public var actionID: String
    public var title: String
    public var status: Status
    /// Tracked tasks are shown in the task center even when they succeed.
    public var isTracked: Bool
    public var progress: Double?
    public var progressMessage: String?
    public var inputs: [String]
    public var outputs: [String]
    public var message: String?
    public var log: [String]
    public var startedAt: Date
    public var finishedAt: Date?

    public var isFinished: Bool { status != .running }

    public var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

/// Observable list of recent tasks, persisted between launches.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var records: [TaskRecord] = []
    public var historyLimit: Int = 200
    private let fileURL: URL
    private static let maximumLogLines = 500

    public init(fileURL: URL = FinderPlusPaths.taskHistoryFile) {
        self.fileURL = fileURL
        if let saved = try? FinderPlusJSON.read([TaskRecord].self, from: fileURL) {
            // Anything still "running" from a previous launch was interrupted.
            records = saved.map { record in
                var record = record
                if record.status == .running {
                    record.status = .cancelled
                    record.message = record.message ?? "Interrupted"
                }
                return record
            }
        }
    }

    public var running: [TaskRecord] { records.filter { $0.status == .running } }
    public var visible: [TaskRecord] { records.filter { $0.isTracked || $0.status == .failed } }

    public func start(request: ActionRequest, moduleName: String, title: String, tracked: Bool) -> UUID {
        let record = TaskRecord(
            id: UUID(), moduleID: request.moduleID, moduleName: moduleName, actionID: request.actionID,
            title: title, status: .running, isTracked: tracked, progress: nil, progressMessage: nil,
            inputs: request.selection.targetURLs.map(\.path), outputs: [], message: nil, log: [],
            startedAt: Date(), finishedAt: nil
        )
        records.insert(record, at: 0)
        trim()
        return record.id
    }

    /// Records a request that was rejected before it could start.
    public func recordRejection(request: ActionRequest, moduleName: String, title: String, reason: String) {
        let id = start(request: request, moduleName: moduleName, title: title, tracked: true)
        finish(id, status: .failed, message: reason)
    }

    public func updateProgress(_ id: UUID, fraction: Double?, message: String?) {
        mutate(id) { record in
            record.progress = fraction.map { min(max($0, 0), 1) }
            if let message { record.progressMessage = message }
        }
    }

    public func appendLog(_ id: UUID, line: String) {
        mutate(id) { record in
            record.log.append(line)
            if record.log.count > Self.maximumLogLines {
                record.log.removeFirst(record.log.count - Self.maximumLogLines)
            }
        }
    }

    public func finish(_ id: UUID, status: TaskRecord.Status, message: String?, outputs: [URL] = []) {
        mutate(id) { record in
            record.status = status
            record.message = message
            record.outputs = outputs.map(\.path)
            record.finishedAt = Date()
            if status == .succeeded { record.progress = 1 }
        }
        persist()
    }

    public func clearFinished() {
        records.removeAll { $0.isFinished }
        persist()
    }

    public func record(_ id: UUID) -> TaskRecord? {
        records.first { $0.id == id }
    }

    private func mutate(_ id: UUID, _ change: (inout TaskRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
    }

    private func trim() {
        if records.count > historyLimit {
            records.removeLast(records.count - historyLimit)
        }
    }

    private func persist() {
        try? FinderPlusJSON.write(records, to: fileURL, pretty: false)
    }
}

/// Forwards module progress/log calls to the main-actor ``TaskStore``.
struct StoreTaskReporter: TaskReporter {
    let store: TaskStore
    let taskID: UUID

    func progress(_ fraction: Double?, message: String?) {
        Task { @MainActor in store.updateProgress(taskID, fraction: fraction, message: message) }
    }

    func log(_ line: String) {
        Task { @MainActor in store.appendLog(taskID, line: line) }
    }
}
