import Foundation

/// `major.minor.patch` version used by modules and script packages.
public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "v" })
        let core = trimmed.split(separator: "-", maxSplits: 1).first ?? ""
        let numbers = core.split(separator: ".").map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        major = numbers[0]!
        minor = numbers.count > 1 ? numbers[1]! : 0
        patch = numbers.count > 2 ? numbers[2]! : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

extension SemanticVersion: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let version = SemanticVersion(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid version '\(string)'")
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension SemanticVersion: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = SemanticVersion(value) ?? SemanticVersion(0)
    }
}
