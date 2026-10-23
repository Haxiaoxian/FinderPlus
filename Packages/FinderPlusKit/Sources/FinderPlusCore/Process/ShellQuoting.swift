import Foundation

/// POSIX shell quoting. Every path or user value that ends up in a command line *must* pass
/// through here; FinderPlus never builds shell commands by raw string interpolation.
public enum ShellQuoting {
    private static let safeCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")

    /// Single-quotes `value` unless it consists only of characters that are never special.
    /// `it's` → `'it'\''s'`.
    public static func quote(_ value: String) -> String {
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Backslash-escapes special characters (the style Terminal uses for dropped files).
    public static func backslashEscape(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            if !safeCharacters.contains(scalar) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Double-quotes `value`, escaping `"`, `\`, `$` and `` ` ``.
    public static func doubleQuote(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if "\"\\$`".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return "\"" + escaped + "\""
    }

    public static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}

/// Splits a user-entered argument string the way a POSIX shell would, without evaluating anything
/// (no variables, globbing or command substitution).
public enum ShellWords {
    public enum ParseError: Error, Equatable {
        case unterminatedQuote
        case danglingEscape
    }

    public static func split(_ input: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false

        for character in input {
            if escaping {
                current.append(character)
                escaping = false
                inWord = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" && activeQuote == "\"" {
                    escaping = true
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "\\":
                escaping = true
            case "'", "\"":
                quote = character
                inWord = true
            case " ", "\t", "\n":
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            default:
                current.append(character)
                inWord = true
            }
        }
        if escaping { throw ParseError.danglingEscape }
        if quote != nil { throw ParseError.unterminatedQuote }
        if inWord { words.append(current) }
        return words
    }
}

public enum AppleScriptString {
    /// A double-quoted AppleScript string literal containing `value` verbatim.
    public static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
