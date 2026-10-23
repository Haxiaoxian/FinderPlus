import FinderPlusCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FinderPlus").font(.largeTitle.bold())
                    Text(HostStrings.tagline.localized).foregroundStyle(.secondary)
                }

                extensionCard

                HStack(spacing: 16) {
                    statCard(HostStrings.enabledModules.localized,
                             "\(model.modules.filter { model.isEnabled($0) }.count) / \(model.modules.count)", "puzzlepiece.extension", .blue)
                    statCard(HostStrings.menuItems.localized, "\(model.snapshot.items.count)", "contextualmenu.and.cursorarrow", .indigo)
                    statCard(HostStrings.runningTasks.localized, "\(model.tasks.running.count)", "clock", .orange)
                }

                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(HostStrings.recentTasks.localized).font(.headline)
                            Spacer()
                            Button(HostStrings.showAll.localized) { model.selection = .tasks }.buttonStyle(.link)
                        }
                        let recent = Array(model.tasks.records.prefix(6))
                        if recent.isEmpty {
                            Text(HostStrings.noTasksYet.localized).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(recent) { record in
                            TaskRow(record: record, showsLog: false)
                            if record.id != recent.last?.id { Divider() }
                        }
                    }
                    .padding(6)
                }
            }
            .padding(24)
        }
        .navigationTitle(HostStrings.overview.localized)
        .onAppear { model.refreshExtensionStatus() }
    }

    private var extensionCard: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(systemName: model.extensionEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(model.extensionEnabled ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.extensionEnabled ? HostStrings.extensionOn.localized : HostStrings.extensionOff.localized)
                        .font(.headline)
                    Text(HostStrings.extensionHelp.localized).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(HostStrings.openExtensionSettings.localized) { model.openExtensionSettings() }
            }
            .padding(6)
        }
    }

    private func statCard(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        GroupBox {
            HStack {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading) {
                    Text(value).font(.title2.bold()).monospacedDigit()
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(6)
        }
    }
}
