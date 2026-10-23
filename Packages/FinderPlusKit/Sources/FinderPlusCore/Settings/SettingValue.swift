import Foundation

/// A JSON-shaped value stored for a module setting.
///
/// Settings are persisted by the host on behalf of modules, so the storage format has to be generic.
/// Modules read them through the typed accessors on ``ModuleSettings`` or decode a whole structure
/// with ``SettingValue/decode(_:)``.
public enum SettingValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([SettingValue])
    case object([String: SettingValue])

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    public var arrayValue: [SettingValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: SettingValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var stringArray: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public static func strings(_ values: [String]) -> SettingValue {
        .array(values.map(SettingValue.string))
    }

    /// Converts this value into any `Decodable` type by round-tripping through JSON.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }

    /// Builds a value from any `Encodable` by round-tripping through JSON.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(SettingValue.self, from: data)
    }
}

extension SettingValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SettingValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SettingValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension SettingValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: SettingValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, SettingValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
