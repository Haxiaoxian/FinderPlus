import Foundation

/// A user-facing string with translations keyed by BCP-47 language code (`en`, `zh-Hans`, `ko`, …).
///
/// Module manifests carry their own translations so that a module — native or script package —
/// can be localized without touching the host's string catalog. In JSON it may be written either as a
/// plain string (treated as English) or as a `{ "en": "…", "zh-Hans": "…" }` object.
public struct LocalizedText: Hashable, Sendable {
    public var translations: [String: String]

    public init(_ translations: [String: String]) {
        self.translations = translations
    }

    public init(en: String, zhHans: String? = nil, ko: String? = nil) {
        var translations = ["en": en]
        if let zhHans { translations["zh-Hans"] = zhHans }
        if let ko { translations["ko"] = ko }
        self.translations = translations
    }

    /// Languages used for resolution, most preferred first. The host replaces this when the user
    /// overrides the system language in FinderPlus settings.
    public static var preferredLanguages: [String] = Locale.preferredLanguages

    /// The best translation for the current preferred languages.
    public var localized: String { resolved() }

    public func resolved(preferredLanguages: [String] = LocalizedText.preferredLanguages) -> String {
        for language in preferredLanguages {
            for candidate in Self.candidates(for: language) {
                if let value = translations[candidate] { return value }
            }
        }
        return translations["en"] ?? translations.sorted(by: { $0.key < $1.key }).first?.value ?? ""
    }

    public var isEmpty: Bool { translations.values.allSatisfy(\.isEmpty) }

    /// `zh-Hans-CN` → [`zh-Hans-CN`, `zh-Hans`, `zh`]; legacy `zh-CN` also maps to `zh-Hans`.
    static func candidates(for language: String) -> [String] {
        let parts = language.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return [] }
        var result: [String] = []
        for length in stride(from: parts.count, through: 1, by: -1) {
            result.append(parts.prefix(length).joined(separator: "-"))
        }
        if parts[0] == "zh", parts.count >= 2, !parts[1].hasPrefix("Han") {
            let region = parts[1].uppercased()
            result.insert(["TW", "HK", "MO"].contains(region) ? "zh-Hant" : "zh-Hans", at: 1)
        }
        return result
    }
}

extension LocalizedText: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            translations = ["en": plain]
        } else {
            translations = try container.decode([String: String].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(translations)
    }
}

extension LocalizedText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        translations = ["en": value]
    }
}

extension LocalizedText {
    /// Substitutes `{name}` placeholders in every translation.
    public func replacing(_ placeholder: String, with value: String) -> LocalizedText {
        LocalizedText(translations.mapValues { $0.replacingOccurrences(of: "{\(placeholder)}", with: value) })
    }
}
