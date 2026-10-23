import AppKit
import FinderPlusCore
import UniformTypeIdentifiers

/// What to put on a folder.
public struct FolderIconSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// System folder tinted with `color`, with an optional SF Symbol emblem.
        case generated
        /// An image file (PNG, ICNS, JPEG, …) used as-is.
        case image
    }

    public var kind: Kind
    public var symbol: String?
    /// Hex RGB (`#3478F6`) or `default` to keep the system folder color.
    public var color: String
    public var imagePath: String?

    public init(kind: Kind = .generated, symbol: String? = nil, color: String = "default", imagePath: String? = nil) {
        self.kind = kind
        self.symbol = symbol
        self.color = color
        self.imagePath = imagePath
    }

    public var displayName: String {
        switch kind {
        case .image: return URL(fileURLWithPath: imagePath ?? "").lastPathComponent
        case .generated: return [symbol, color == "default" ? nil : color].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// Built-in palette and emblem catalog. Icon packs add more images on disk.
public enum FolderIconCatalog {
    public struct Swatch: Hashable, Identifiable, Sendable {
        public var id: String { hex }
        public var hex: String
        public var name: LocalizedText
    }

    public static let swatches: [Swatch] = [
        Swatch(hex: "default", name: LocalizedText(en: "Default", zhHans: "默认", ko: "기본")),
        Swatch(hex: "#FF3B30", name: LocalizedText(en: "Red", zhHans: "红色", ko: "빨강")),
        Swatch(hex: "#FF9500", name: LocalizedText(en: "Orange", zhHans: "橙色", ko: "주황")),
        Swatch(hex: "#FFCC00", name: LocalizedText(en: "Yellow", zhHans: "黄色", ko: "노랑")),
        Swatch(hex: "#34C759", name: LocalizedText(en: "Green", zhHans: "绿色", ko: "초록")),
        Swatch(hex: "#00C7BE", name: LocalizedText(en: "Mint", zhHans: "薄荷", ko: "민트")),
        Swatch(hex: "#30B0C7", name: LocalizedText(en: "Teal", zhHans: "青色", ko: "청록")),
        Swatch(hex: "#5856D6", name: LocalizedText(en: "Indigo", zhHans: "靛蓝", ko: "남색")),
        Swatch(hex: "#AF52DE", name: LocalizedText(en: "Purple", zhHans: "紫色", ko: "보라")),
        Swatch(hex: "#FF2D55", name: LocalizedText(en: "Pink", zhHans: "粉色", ko: "분홍")),
        Swatch(hex: "#A2845E", name: LocalizedText(en: "Brown", zhHans: "棕色", ko: "갈색")),
        Swatch(hex: "#8E8E93", name: LocalizedText(en: "Gray", zhHans: "灰色", ko: "회색")),
        Swatch(hex: "#3A3A3C", name: LocalizedText(en: "Graphite", zhHans: "石墨", ko: "그래파이트")),
    ]

    public static let symbols: [String] = [
        "doc.text", "doc.richtext", "book", "books.vertical", "graduationcap", "text.book.closed",
        "chevron.left.forwardslash.chevron.right", "terminal", "hammer", "wrench.and.screwdriver", "gearshape", "cpu",
        "photo", "camera", "film", "music.note", "mic", "paintbrush", "paintpalette", "pencil.and.ruler",
        "briefcase", "chart.bar", "chart.pie", "dollarsign.circle", "cart", "creditcard", "building.2",
        "person", "person.2", "heart", "star", "flag", "bookmark", "tag", "bell",
        "cloud", "icloud.and.arrow.down", "arrow.down.circle", "tray.full", "archivebox", "shippingbox", "externaldrive",
        "globe", "airplane", "car", "house", "leaf", "flame", "drop", "bolt", "sun.max", "moon",
        "lock", "key", "shield", "exclamationmark.triangle", "checkmark.seal", "gamecontroller", "puzzlepiece",
        "atom", "function", "testtube.2", "cross.case", "pills", "brain",
    ]
}

/// Draws generated folder icons and applies icons to folders with the public NSWorkspace API.
@MainActor
public enum FolderIconRenderer {
    public static func image(for spec: FolderIconSpec, size: CGFloat = 512) -> NSImage? {
        switch spec.kind {
        case .image:
            guard let path = spec.imagePath else { return nil }
            return NSImage(contentsOf: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
        case .generated:
            return generated(symbol: spec.symbol, color: color(from: spec.color), size: size)
        }
    }

    static func generated(symbol: String?, color: NSColor?, size: CGFloat) -> NSImage {
        let base = NSWorkspace.shared.icon(for: .folder)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect)
            if let color, let context = NSGraphicsContext.current?.cgContext {
                // Take hue/saturation from the tint and luminance from the folder, then clip to its shape.
                context.saveGState()
                context.setBlendMode(.color)
                context.setFillColor(color.cgColor)
                context.fill(rect)
                context.restoreGState()
                base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            }
            if let symbol {
                let emblemColor = (color ?? NSColor(srgbRed: 0.18, green: 0.47, blue: 0.85, alpha: 1))
                    .blended(withFraction: 0.45, of: .black) ?? .black
                let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.28, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [emblemColor.withAlphaComponent(0.85)]))
                if let emblem = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration) {
                    let emblemSize = emblem.size
                    let origin = NSPoint(x: rect.midX - emblemSize.width / 2, y: rect.height * 0.40 - emblemSize.height / 2)
                    emblem.draw(in: NSRect(origin: origin, size: emblemSize))
                }
            }
            return true
        }
    }

    public static func color(from hex: String) -> NSColor? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        guard value != "default", !value.isEmpty else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255,
                       blue: CGFloat(number & 0xFF) / 255, alpha: 1)
    }

    /// Whether the folder currently has a custom icon (an `Icon\r` file inside it).
    public static func hasCustomIcon(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path)
    }

    public static func apply(_ image: NSImage?, to folder: URL) -> Bool {
        NSWorkspace.shared.setIcon(image, forFile: folder.path, options: [])
    }

    public static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
