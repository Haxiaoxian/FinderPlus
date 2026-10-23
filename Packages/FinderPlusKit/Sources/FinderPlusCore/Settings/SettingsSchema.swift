import Foundation

/// Declarative description of a module's settings.
///
/// The host renders this schema into a native settings form, stores the values and hands them back
/// to the module on every invocation. Modules that need richer interaction can additionally provide
/// a custom SwiftUI view (see `ModuleSettingsViewProviding` in FinderPlusUI).
public struct SettingsSchema: Codable, Hashable, Sendable {
    public var sections: [SettingsSection]

    public init(sections: [SettingsSection] = []) {
        self.sections = sections
    }

    public static let empty = SettingsSchema()

    public var allFields: [SettingField] { sections.flatMap(\.fields) }

    public var isEmpty: Bool { allFields.isEmpty }

    public func field(_ key: String) -> SettingField? {
        allFields.first { $0.key == key }
    }

    public func defaultValues() -> [String: SettingValue] {
        Dictionary(allFields.map { ($0.key, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decode([SettingsSection].self, forKey: .sections, default: [])
    }

    enum CodingKeys: String, CodingKey { case sections }
}

public struct SettingsSection: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: LocalizedText
    public var footer: LocalizedText?
    public var fields: [SettingField]

    public init(id: String, title: LocalizedText, footer: LocalizedText? = nil, fields: [SettingField]) {
        self.id = id
        self.title = title
        self.footer = footer
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id, default: UUID().uuidString)
        title = try container.decode(LocalizedText.self, forKey: .title, default: "")
        footer = try container.decodeIfPresent(LocalizedText.self, forKey: .footer)
        fields = try container.decode([SettingField].self, forKey: .fields, default: [])
    }

    enum CodingKeys: String, CodingKey { case id, title, footer, fields }
}

public struct SettingOption: Codable, Hashable, Sendable, Identifiable {
    public var value: String
    public var title: LocalizedText
    public var id: String { value }

    public init(_ value: String, _ title: LocalizedText) {
        self.value = value
        self.title = title
    }
}

/// Shows a field only when another setting has one of the listed values.
public struct SettingCondition: Codable, Hashable, Sendable {
    public var key: String
    public var equals: [SettingValue]

    public init(key: String, equals: [SettingValue]) {
        self.key = key
        self.equals = equals
    }

    public func isSatisfied(by settings: ModuleSettings) -> Bool {
        equals.contains(settings[key])
    }
}

public struct SettingField: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case toggle
        case text
        case multilineText
        case integer
        case number
        /// Single choice from `options`; stored as `.string`.
        case choice
        /// Any subset of `options`; stored as an array of strings in option order.
        case multiChoice
        /// File, folder or application chosen with an open panel; stored as a path string.
        case path
        /// Free-form list of strings.
        case stringList
        /// List of objects whose fields are described by `itemFields`.
        case objectList
    }

    public enum PathKind: String, Codable, Sendable {
        case file, folder, application
    }

    public var key: String
    public var title: LocalizedText
    public var help: LocalizedText?
    public var kind: Kind
    public var defaultValue: SettingValue
    public var options: [SettingOption]
    public var minimum: Double?
    public var maximum: Double?
    public var step: Double?
    public var placeholder: LocalizedText?
    public var pathKind: PathKind?
    public var itemFields: [SettingField]
    /// For `objectList`: the item field whose value is shown as each row's title.
    public var itemTitleKey: String?
    public var visibleWhen: SettingCondition?

    public var id: String { key }

    public init(
        key: String,
        title: LocalizedText,
        help: LocalizedText? = nil,
        kind: Kind,
        defaultValue: SettingValue,
        options: [SettingOption] = [],
        minimum: Double? = nil,
        maximum: Double? = nil,
        step: Double? = nil,
        placeholder: LocalizedText? = nil,
        pathKind: PathKind? = nil,
        itemFields: [SettingField] = [],
        itemTitleKey: String? = nil,
        visibleWhen: SettingCondition? = nil
    ) {
        self.key = key
        self.title = title
        self.help = help
        self.kind = kind
        self.defaultValue = defaultValue
        self.options = options
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.placeholder = placeholder
        self.pathKind = pathKind
        self.itemFields = itemFields
        self.itemTitleKey = itemTitleKey
        self.visibleWhen = visibleWhen
    }

    enum CodingKeys: String, CodingKey {
        case key, title, help, kind, defaultValue = "default", options, minimum, maximum, step
        case placeholder, pathKind, itemFields, itemTitleKey, visibleWhen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(LocalizedText.self, forKey: .title, default: LocalizedText(stringLiteral: key))
        help = try container.decodeIfPresent(LocalizedText.self, forKey: .help)
        kind = try container.decode(Kind.self, forKey: .kind, default: .text)
        defaultValue = try container.decode(SettingValue.self, forKey: .defaultValue, default: Self.implicitDefault(for: kind))
        options = try container.decode([SettingOption].self, forKey: .options, default: [])
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        step = try container.decodeIfPresent(Double.self, forKey: .step)
        placeholder = try container.decodeIfPresent(LocalizedText.self, forKey: .placeholder)
        pathKind = try container.decodeIfPresent(PathKind.self, forKey: .pathKind)
        itemFields = try container.decode([SettingField].self, forKey: .itemFields, default: [])
        itemTitleKey = try container.decodeIfPresent(String.self, forKey: .itemTitleKey)
        visibleWhen = try container.decodeIfPresent(SettingCondition.self, forKey: .visibleWhen)
    }

    static func implicitDefault(for kind: Kind) -> SettingValue {
        switch kind {
        case .toggle: return false
        case .integer: return 0
        case .number: return 0.0
        case .text, .multilineText, .choice, .path: return ""
        case .multiChoice, .stringList, .objectList: return []
        }
    }
}

// MARK: - Convenience constructors for native modules

extension SettingField {
    public static func toggle(_ key: String, _ title: LocalizedText, default value: Bool, help: LocalizedText? = nil,
                              visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .toggle, defaultValue: .bool(value), visibleWhen: visibleWhen)
    }

    public static func text(_ key: String, _ title: LocalizedText, default value: String = "", placeholder: LocalizedText? = nil,
                            help: LocalizedText? = nil, visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .text, defaultValue: .string(value),
                     placeholder: placeholder, visibleWhen: visibleWhen)
    }

    public static func integer(_ key: String, _ title: LocalizedText, default value: Int, range: ClosedRange<Int>,
                               step: Int = 1, help: LocalizedText? = nil, visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .integer, defaultValue: .int(value),
                     minimum: Double(range.lowerBound), maximum: Double(range.upperBound), step: Double(step),
                     visibleWhen: visibleWhen)
    }

    public static func number(_ key: String, _ title: LocalizedText, default value: Double, range: ClosedRange<Double>,
                              step: Double, help: LocalizedText? = nil, visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .number, defaultValue: .double(value),
                     minimum: range.lowerBound, maximum: range.upperBound, step: step, visibleWhen: visibleWhen)
    }

    public static func choice(_ key: String, _ title: LocalizedText, options: [SettingOption], default value: String,
                              help: LocalizedText? = nil, visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .choice, defaultValue: .string(value), options: options,
                     visibleWhen: visibleWhen)
    }

    public static func multiChoice(_ key: String, _ title: LocalizedText, options: [SettingOption], default values: [String],
                                   help: LocalizedText? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .multiChoice, defaultValue: .strings(values), options: options)
    }

    public static func path(_ key: String, _ title: LocalizedText, kind pathKind: PathKind, default value: String = "",
                            placeholder: LocalizedText? = nil, help: LocalizedText? = nil,
                            visibleWhen: SettingCondition? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .path, defaultValue: .string(value),
                     placeholder: placeholder, pathKind: pathKind, visibleWhen: visibleWhen)
    }

    public static func stringList(_ key: String, _ title: LocalizedText, default values: [String] = [],
                                  placeholder: LocalizedText? = nil, help: LocalizedText? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .stringList, defaultValue: .strings(values), placeholder: placeholder)
    }

    public static func objectList(_ key: String, _ title: LocalizedText, itemFields: [SettingField], titleKey: String,
                                  default values: [SettingValue] = [], help: LocalizedText? = nil) -> SettingField {
        SettingField(key: key, title: title, help: help, kind: .objectList, defaultValue: .array(values),
                     itemFields: itemFields, itemTitleKey: titleKey)
    }
}
