import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value if the key is present, otherwise returns `defaultValue`.
    ///
    /// Manifests and configuration files are written by hand and by older/newer app versions, so
    /// almost every field is optional on disk. Keeping the defaults next to the decode call keeps
    /// forward and backward compatibility explicit.
    public func decode<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(type, forKey: key) ?? defaultValue()
    }
}

public enum FinderPlusJSON {
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writes JSON atomically so a reader (e.g. the Finder extension) never sees a half-written file.
    public static func write<T: Encodable>(_ value: T, to url: URL, pretty: Bool = true) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder(pretty: pretty).encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder().decode(type, from: Data(contentsOf: url))
    }
}
