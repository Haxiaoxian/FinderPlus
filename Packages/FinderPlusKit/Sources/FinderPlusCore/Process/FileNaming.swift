import Foundation

/// Finder-style collision-free file names: `Untitled.md`, `Untitled 2.md`, `Untitled 3.md`, …
public enum UniqueFileNamer {
    public static func availableURL(
        in directory: URL,
        baseName: String,
        pathExtension: String,
        isDirectory: Bool = false,
        fileManager: FileManager = .default
    ) -> URL {
        let base = sanitizedFileName(baseName).isEmpty ? "Untitled" : sanitizedFileName(baseName)
        func candidate(_ index: Int) -> URL {
            let name = index == 1 ? base : "\(base) \(index)"
            let fileName = pathExtension.isEmpty ? name : "\(name).\(pathExtension)"
            return directory.appendingPathComponent(fileName, isDirectory: isDirectory)
        }
        var index = 1
        while fileManager.fileExists(atPath: candidate(index).path) {
            index += 1
        }
        return candidate(index)
    }

    /// Like ``availableURL(in:baseName:pathExtension:isDirectory:fileManager:)`` for a full file name.
    public static func availableURL(in directory: URL, fileName: String, fileManager: FileManager = .default) -> URL {
        let url = URL(fileURLWithPath: fileName)
        return availableURL(in: directory, baseName: url.deletingPathExtension().lastPathComponent,
                            pathExtension: url.pathExtension, fileManager: fileManager)
    }

    /// Removes characters Finder does not allow in names and trims whitespace.
    public static func sanitizedFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.hasPrefix(".") ? String(cleaned.drop(while: { $0 == "." })) : cleaned
    }

    /// Expands `{name}`, `{ext}` and `{date}` in an output file-name pattern.
    public static func expand(pattern: String, sourceURL: URL, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return pattern
            .replacingOccurrences(of: "{name}", with: sourceURL.deletingPathExtension().lastPathComponent)
            .replacingOccurrences(of: "{ext}", with: sourceURL.pathExtension)
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))
    }
}
