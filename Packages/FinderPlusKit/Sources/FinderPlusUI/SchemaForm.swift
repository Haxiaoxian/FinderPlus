import AppKit
import FinderPlusCore
import SwiftUI
import UniformTypeIdentifiers

/// Renders a module's ``SettingsSchema`` as a native grouped form.
public struct SchemaForm: View {
    let schema: SettingsSchema
    @Binding var settings: ModuleSettings

    public init(schema: SettingsSchema, settings: Binding<ModuleSettings>) {
        self.schema = schema
        _settings = settings
    }

    public var body: some View {
        ForEach(schema.sections) { section in
            Section {
                ForEach(section.fields) { field in
                    if field.visibleWhen?.isSatisfied(by: settings) ?? true {
                        SettingFieldEditor(field: field, value: binding(for: field))
                    }
                }
            } header: {
                if !section.title.isEmpty { Text(section.title.localized) }
            } footer: {
                if let footer = section.footer { Text(footer.localized).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func binding(for field: SettingField) -> Binding<SettingValue> {
        Binding(
            get: { settings[field.key] },
            set: { settings[field.key] = $0 }
        )
    }
}

/// Editor for a single field; used recursively for object lists.
public struct SettingFieldEditor: View {
    let field: SettingField
    @Binding var value: SettingValue

    public init(field: SettingField, value: Binding<SettingValue>) {
        self.field = field
        _value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let help = field.help, field.kind != .toggle {
                Text(help.localized).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        let title = field.title.localized
        switch field.kind {
        case .toggle:
            Toggle(isOn: Binding(get: { value.boolValue ?? false }, set: { value = .bool($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let help = field.help { Text(help.localized).font(.caption).foregroundStyle(.secondary) }
                }
            }
        case .text:
            TextField(title, text: stringBinding, prompt: field.placeholder.map { Text($0.localized) })
        case .multilineText:
            VStack(alignment: .leading) {
                Text(title)
                TextEditor(text: stringBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        case .integer:
            IntegerField(title: title, value: $value, range: range, step: Int(field.step ?? 1))
        case .number:
            NumberField(title: title, value: $value, range: range, step: field.step ?? 0.05)
        case .choice:
            Picker(title, selection: stringBinding) {
                ForEach(field.options) { option in
                    Text(option.title.localized).tag(option.value)
                }
            }
        case .multiChoice:
            MultiChoiceEditor(title: title, options: field.options, value: $value)
        case .path:
            PathField(title: title, kind: field.pathKind ?? .file, placeholder: field.placeholder?.localized, path: stringBinding)
        case .stringList:
            StringListEditor(title: title, placeholder: field.placeholder?.localized, value: $value)
        case .objectList:
            ObjectListEditor(field: field, value: $value)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(get: { value.stringValue ?? "" }, set: { value = .string($0) })
    }

    private var range: ClosedRange<Double> {
        (field.minimum ?? 0)...(field.maximum ?? 1_000_000)
    }
}

// MARK: - Controls

struct IntegerField: View {
    let title: String
    @Binding var value: SettingValue
    let range: ClosedRange<Double>
    let step: Int

    var body: some View {
        let binding = Binding<Int>(
            get: { value.intValue ?? Int(range.lowerBound) },
            set: { value = .int(min(max($0, Int(range.lowerBound)), Int(range.upperBound))) }
        )
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: binding, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper("", value: binding, in: Int(range.lowerBound)...Int(range.upperBound), step: max(step, 1))
                    .labelsHidden()
            }
        }
    }
}

struct NumberField: View {
    let title: String
    @Binding var value: SettingValue
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        let binding = Binding<Double>(
            get: { value.doubleValue ?? range.lowerBound },
            set: { value = .double(($0 / step).rounded() * step) }
        )
        LabeledContent(title) {
            HStack {
                Slider(value: binding, in: range)
                    .frame(minWidth: 140)
                Text(binding.wrappedValue, format: .number.precision(.fractionLength(step < 1 ? 2 : 0)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

struct MultiChoiceEditor: View {
    let title: String
    let options: [SettingOption]
    @Binding var value: SettingValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            let selected = Set(value.stringArray ?? [])
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(options) { option in
                    Toggle(option.title.localized, isOn: Binding(
                        get: { selected.contains(option.value) },
                        set: { isOn in
                            var next = selected
                            if isOn { next.insert(option.value) } else { next.remove(option.value) }
                            // Keep option order so menus stay stable.
                            value = .strings(options.map(\.value).filter(next.contains))
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

public struct PathField: View {
    let title: String
    let kind: SettingField.PathKind
    let placeholder: String?
    @Binding var path: String

    public init(title: String, kind: SettingField.PathKind, placeholder: String? = nil, path: Binding<String>) {
        self.title = title
        self.kind = kind
        self.placeholder = placeholder
        _path = path
    }

    public var body: some View {
        LabeledContent(title) {
            HStack {
                TextField("", text: $path, prompt: placeholder.map { Text($0) })
                    .textFieldStyle(.roundedBorder)
                Button(UIStrings.choose.localized) { choose() }
                if !path.isEmpty {
                    Button { path = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func choose() {
        if let url = OpenPanel.choose(kind) { path = url.path }
    }
}

public enum OpenPanel {
    @MainActor
    public static func choose(_ kind: SettingField.PathKind, allowedContentTypes: [UTTypeReference] = []) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind != .folder
        panel.canChooseDirectories = kind == .folder
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if kind == .application {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
        } else if !allowedContentTypes.isEmpty {
            panel.allowedContentTypes = allowedContentTypes.map(\.type)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    public static func chooseFolder() -> URL? { choose(.folder) }
}

/// Wrapper so callers don't need to import UniformTypeIdentifiers.
public struct UTTypeReference {
    public var type: UTType
    public init(_ type: UTType) { self.type = type }
}

struct StringListEditor: View {
    let title: String
    let placeholder: String?
    @Binding var value: SettingValue

    var body: some View {
        let items = value.stringArray ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button { value = .strings(items + [""]) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
            }
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField("", text: Binding(
                        get: { index < items.count ? items[index] : "" },
                        set: { newValue in
                            var next = value.stringArray ?? []
                            guard index < next.count else { return }
                            next[index] = newValue
                            value = .strings(next)
                        }
                    ), prompt: placeholder.map { Text($0) })
                    .textFieldStyle(.roundedBorder)
                    Button {
                        var next = value.stringArray ?? []
                        guard index < next.count else { return }
                        next.remove(at: index)
                        value = .strings(next)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

struct ObjectListEditor: View {
    let field: SettingField
    @Binding var value: SettingValue

    var body: some View {
        let items = value.arrayValue ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.title.localized)
                Spacer()
                Button {
                    let defaults = Dictionary(field.itemFields.map { ($0.key, $0.defaultValue) }, uniquingKeysWith: { a, _ in a })
                    value = .array(items + [.object(defaults)])
                } label: { Label(UIStrings.add.localized, systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            ForEach(items.indices, id: \.self) { index in
                ObjectItemRow(field: field, index: index, value: $value)
            }
        }
    }
}

struct ObjectItemRow: View {
    let field: SettingField
    let index: Int
    @Binding var value: SettingValue
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(field.itemFields) { itemField in
                    if isVisible(itemField) {
                        SettingFieldEditor(field: itemField, value: binding(for: itemField))
                    }
                }
                HStack {
                    Button { move(by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { move(by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index >= count - 1)
                    Spacer()
                    Button(role: .destructive) { remove() } label: { Label(UIStrings.remove.localized, systemImage: "trash") }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        } label: {
            Text(rowTitle).lineLimit(1)
        }
    }

    private var items: [SettingValue] { value.arrayValue ?? [] }
    private var count: Int { items.count }
    private var object: [String: SettingValue] { index < count ? (items[index].objectValue ?? [:]) : [:] }

    private var rowTitle: String {
        if let key = field.itemTitleKey, let title = object[key]?.stringValue, !title.isEmpty { return title }
        return "#\(index + 1)"
    }

    private func isVisible(_ itemField: SettingField) -> Bool {
        guard let condition = itemField.visibleWhen else { return true }
        let current = object[condition.key] ?? field.itemFields.first { $0.key == condition.key }?.defaultValue ?? .null
        return condition.equals.contains(current)
    }

    private func binding(for itemField: SettingField) -> Binding<SettingValue> {
        Binding(
            get: { object[itemField.key] ?? itemField.defaultValue },
            set: { newValue in
                var all = value.arrayValue ?? []
                guard index < all.count else { return }
                var dictionary = all[index].objectValue ?? [:]
                dictionary[itemField.key] = newValue
                all[index] = .object(dictionary)
                value = .array(all)
            }
        )
    }

    private func move(by offset: Int) {
        var all = items
        let target = index + offset
        guard all.indices.contains(index), all.indices.contains(target) else { return }
        all.swapAt(index, target)
        value = .array(all)
    }

    private func remove() {
        var all = items
        guard all.indices.contains(index) else { return }
        all.remove(at: index)
        value = .array(all)
    }
}

enum UIStrings {
    static let choose = LocalizedText(en: "Choose…", zhHans: "选择…", ko: "선택…")
    static let add = LocalizedText(en: "Add", zhHans: "添加", ko: "추가")
    static let remove = LocalizedText(en: "Remove", zhHans: "移除", ko: "제거")
}
