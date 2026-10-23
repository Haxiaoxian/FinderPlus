import FinderPlusCore
import FinderPlusEngine
import SwiftUI

/// Rounded, tinted SF Symbol tile used for module icons.
struct ModuleIconView: View {
    let symbol: String
    var size: CGFloat = 36
    var tint: Color = .accentColor

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}

struct Badge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

extension ModuleCategory {
    var tint: Color {
        switch self {
        case .create: return .blue
        case .path: return .gray
        case .open: return .indigo
        case .convert: return .orange
        case .appearance: return .pink
        case .finder: return .teal
        case .utility: return .purple
        }
    }
}

extension TaskRecord.Status {
    var symbol: String {
        switch self {
        case .running: return "clock"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}

extension DependencyStatus.State {
    var symbol: String {
        switch self {
        case .satisfied: return "checkmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .satisfied: return .green
        case .missing: return .red
        case .warning: return .orange
        }
    }
}

/// Human-readable summary of where an action appears, for settings and the menu manager.
enum RuleDescription {
    static func describe(_ rule: MenuRule) -> String {
        var parts: [String] = []
        if rule.contexts.contains(.container) { parts.append(HostStrings.ruleBackground.localized) }
        if rule.contexts.contains(.items) {
            if let kinds = rule.itemKinds, kinds == [.folder] {
                parts.append(HostStrings.ruleFolders.localized)
            } else if let extensions = rule.extensions {
                parts.append(extensions.sorted().map { ".\($0)" }.joined(separator: " "))
            } else if let types = rule.typeIdentifiers {
                parts.append(types.joined(separator: ", "))
            } else {
                parts.append(HostStrings.ruleAnyItem.localized)
            }
        }
        if let max = rule.maxSelection { parts.append("≤ \(max)") }
        return parts.joined(separator: " · ")
    }
}

/// One task row, used by the overview and the task center.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let record: TaskRecord
    var showsLog = true
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: record.status.symbol).foregroundStyle(record.status.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(.body.weight(.medium))
                    Text("\(record.moduleName) · \(record.startedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if record.status == .running {
                    Button(HostStrings.cancel.localized) { model.engine.cancel(record.id) }
                        .controlSize(.small)
                } else if !record.outputs.isEmpty {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(record.outputs.map { URL(fileURLWithPath: $0) })
                    } label: { Label(HostStrings.showInFinder.localized, systemImage: "magnifyingglass") }
                        .controlSize(.small)
                }
            }
            if record.status == .running {
                if let progress = record.progress {
                    ProgressView(value: progress) { Text(record.progressMessage ?? "").font(.caption) }
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            if let message = record.message, !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(record.status == .failed ? .red : .secondary).textSelection(.enabled)
            }
            if showsLog, !record.log.isEmpty {
                DisclosureGroup(HostStrings.log.localized, isExpanded: $expanded) {
                    ScrollView {
                        Text(record.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
