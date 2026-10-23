import Foundation

/// The effective settings of one module: stored values layered over the schema defaults.
public struct ModuleSettings: Hashable, Sendable {
    public var values: [String: SettingValue]
    public var defaults: [String: SettingValue]

    public init(values: [String: SettingValue] = [:], defaults: [String: SettingValue] = [:]) {
        self.values = values
        self.defaults = defaults
    }

    public init(values: [String: SettingValue] = [:], schema: SettingsSchema) {
        self.init(values: values, defaults: schema.defaultValues())
    }

    public subscript(key: String) -> SettingValue {
        get {
            if let value = values[key], !value.isNull { return value }
            return defaults[key] ?? .null
        }
        set { values[key] = newValue }
    }

    public func bool(_ key: String) -> Bool { self[key].boolValue ?? false }
    public func int(_ key: String) -> Int { self[key].intValue ?? 0 }
    public func double(_ key: String) -> Double { self[key].doubleValue ?? 0 }
    public func string(_ key: String) -> String { self[key].stringValue ?? "" }
    public func strings(_ key: String) -> [String] { self[key].stringArray ?? [] }
    public func objects(_ key: String) -> [[String: SettingValue]] { self[key].arrayValue?.compactMap(\.objectValue) ?? [] }

    /// Non-empty trimmed string, or `nil`.
    public func nonEmptyString(_ key: String) -> String? {
        let value = string(key).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        try? self[key].decode(type)
    }
}
