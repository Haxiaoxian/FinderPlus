import FinderPlusCore
import SwiftUI

struct MenuManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var sample: SampleSelection = .python
    @State private var confirmReset = false

    var body: some View {
        HSplitView {
            editor
                .frame(minWidth: 460)
            preview
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
        .navigationTitle(HostStrings.menuManager.localized)
        .toolbar {
            ToolbarItem {
                Button(HostStrings.resetMenu.localized) { confirmReset = true }
            }
        }
        .confirmationDialog(HostStrings.resetMenu.localized, isPresented: $confirmReset) {
            Button(HostStrings.resetMenu.localized, role: .destructive) { model.resetMenuCustomizations() }
        }
    }

    // MARK: Editor

    private var groupedActions: [(group: MenuGroupID, items: [(module: FinderPlusModule, action: ActionDescriptor)])] {
        let all = model.allMenuActions()
        let groups = Dictionary(grouping: all) { entry in
            model.itemOverride(ActionDescriptor.key(moduleID: entry.module.id, actionID: entry.action.id)).group ?? entry.action.group
        }
        return groups
            .map { (group: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                let left = model.groupOverride(lhs.group).order ?? MenuGroupCatalog.entry(for: lhs.group).order
                let right = model.groupOverride(rhs.group).order ?? MenuGroupCatalog.entry(for: rhs.group).order
                return (left, lhs.group) < (right, rhs.group)
            }
    }

    private var editor: some View {
        Form {
            Section {
                Text(HostStrings.menuManagerHelp.localized).font(.callout).foregroundStyle(.secondary)
                Button(HostStrings.menuAppearanceSettings.localized) { model.selection = .module(WellKnownModule.appearance) }
                    .buttonStyle(.link)
            }
            ForEach(groupedActions, id: \.group) { entry in
                Section {
                    GroupEditor(group: entry.group)
                    ForEach(entry.items, id: \.action.id) { item in
                        ItemEditor(module: item.module, action: item.action)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HostStrings.livePreview.localized).font(.headline)
            Picker(HostStrings.selection.localized, selection: $sample) {
                ForEach(SampleSelection.allCases) { Text($0.title).tag($0) }
            }
            let resolved = MenuResolver.resolve(model.snapshot, for: sample.selection)
            MenuPreview(menu: resolved)
            Spacer()
        }
        .padding(16)
    }
}

private struct GroupEditor: View {
    @Environment(AppModel.self) private var model
    let group: MenuGroupID

    var body: some View {
        let entry = MenuGroupCatalog.entry(for: group)
        let override = model.groupOverride(group)
        HStack {
            Image(systemName: entry.icon ?? "folder").foregroundStyle(.secondary)
            TextField(entry.title.localized, text: Binding(
                get: { override.title ?? "" },
                set: { var next = override; next.title = $0.isEmpty ? nil : $0; model.setGroupOverride(group, next) }
            ))
            .font(.headline)
            .textFieldStyle(.plain)
            Picker("", selection: Binding(
                get: { override.presentation ?? entry.presentation },
                set: { var next = override; next.presentation = $0; model.setGroupOverride(group, next) }
            )) {
                Text(HostStrings.inline.localized).tag(MenuGroupCatalog.Presentation.inline)
                Text(HostStrings.submenu.localized).tag(MenuGroupCatalog.Presentation.submenu)
            }
            .labelsHidden()
            .frame(width: 110)
            Stepper(value: Binding(
                get: { override.order ?? entry.order },
                set: { var next = override; next.order = $0; model.setGroupOverride(group, next) }
            ), in: 0...999, step: 5) {
                Text("\(override.order ?? entry.order)").monospacedDigit().foregroundStyle(.secondary)
            }
            .help(HostStrings.orderHelp.localized)
            Toggle("", isOn: Binding(
                get: { !override.hidden },
                set: { var next = override; next.hidden = !$0; model.setGroupOverride(group, next) }
            ))
            .labelsHidden()
            .help(HostStrings.showGroup.localized)
        }
    }
}

private struct ItemEditor: View {
    @Environment(AppModel.self) private var model
    let module: FinderPlusModule
    let action: ActionDescriptor

    private var key: String { ActionDescriptor.key(moduleID: module.id, actionID: action.id) }

    var body: some View {
        let override = model.itemOverride(key)
        HStack {
            Image(systemName: action.icon ?? "circle").frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                TextField(action.title.localized, text: Binding(
                    get: { override.title ?? "" },
                    set: { var next = override; next.title = $0.isEmpty ? nil : $0; model.setItemOverride(key, next) }
                ))
                .textFieldStyle(.plain)
                Text("\(module.manifest.name.localized) · \(RuleDescription.describe(action.rule))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Picker("", selection: Binding(
                get: { override.group ?? action.group },
                set: { var next = override; next.group = $0 == action.group ? nil : $0; model.setItemOverride(key, next) }
            )) {
                ForEach(MenuGroupCatalog.entries, id: \.id) { entry in
                    Text(entry.title.localized).tag(entry.id)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Stepper(value: Binding(
                get: { override.order ?? action.order },
                set: { var next = override; next.order = $0; model.setItemOverride(key, next) }
            ), in: 0...999, step: 5) {
                Text("\(override.order ?? action.order)").monospacedDigit().foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { !override.hidden },
                set: { var next = override; next.hidden = !$0; model.setItemOverride(key, next) }
            ))
            .labelsHidden()
        }
        .padding(.leading, 12)
    }
}

/// Visual approximation of the Finder context menu for a selection.
struct MenuPreview: View {
    let menu: ResolvedMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if menu.isEmpty {
                Text(HostStrings.previewEmpty.localized).foregroundStyle(.secondary).padding(10)
            } else {
                if menu.appearance.style == .submenu {
                    row(menu.appearance.rootTitle, icon: "puzzlepiece.extension", chevron: true).font(.body.weight(.semibold))
                    Divider()
                }
                ForEach(Array(menu.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 { Divider().padding(.vertical, 3) }
                    if section.group.presentation == .submenu {
                        row(section.group.title, icon: section.group.icon, chevron: true)
                        ForEach(section.items) { item in
                            row(item.title, icon: item.icon).padding(.leading, 18).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(section.items) { item in row(item.title, icon: item.icon) }
                    }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func row(_ title: String, icon: String?, chevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            if menu.appearance.showIcons {
                Image(systemName: icon ?? "circle").frame(width: 16).opacity(icon == nil ? 0 : 1)
            }
            Text(title)
            Spacer()
            if chevron { Image(systemName: "chevron.right").font(.caption) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

enum SampleSelection: String, CaseIterable, Identifiable {
    case python, markdown, image, document, folder, background, multipleFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .python: return HostStrings.samplePython.localized
        case .markdown: return HostStrings.sampleMarkdown.localized
        case .image: return HostStrings.sampleImage.localized
        case .document: return HostStrings.sampleDocument.localized
        case .folder: return HostStrings.sampleFolder.localized
        case .background: return HostStrings.sampleBackground.localized
        case .multipleFiles: return HostStrings.sampleMultiple.localized
        }
    }

    var selection: FinderSelection {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        func file(_ name: String) -> SelectedItem {
            SelectedItem(url: home.appendingPathComponent("Documents/\(name)"), kind: .file)
        }
        let container = home.appendingPathComponent("Documents", isDirectory: true)
        switch self {
        case .python: return FinderSelection(context: .items, items: [file("analysis.py")], container: container)
        case .markdown: return FinderSelection(context: .items, items: [file("README.md")], container: container)
        case .image: return FinderSelection(context: .items, items: [file("photo.jpg")], container: container)
        case .document: return FinderSelection(context: .items, items: [file("report.docx")], container: container)
        case .folder:
            return FinderSelection(context: .items,
                                   items: [SelectedItem(url: home.appendingPathComponent("Documents/Project"), kind: .folder)],
                                   container: container)
        case .background: return .container(container)
        case .multipleFiles:
            return FinderSelection(context: .items, items: [file("a.png"), file("b.jpg"), file("c.heic")], container: container)
        }
    }
}
