import FinderPlusCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Block 04.1 — compress and resize images with ImageIO. Originals are never modified.
public final class ImageCompressorModule: FinderPlusModule {
    public static let id = "io.github.finderplus.image-compressor"

    enum Key {
        static let presets = "presets"
        static let defaultPreset = "defaultPreset"
        static let outputMode = "outputMode"
        static let suffix = "suffix"
        static let folderName = "folderName"
        static let keepMetadata = "keepMetadata"
        static let skipLarger = "skipLarger"
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"]

    public struct Preset: Codable, Hashable, Sendable {
        public var name: String
        /// `same`, `jpeg`, `heic` or `png`.
        public var format: String
        /// 0…1, used by lossy formats.
        public var quality: Double
        /// Longest edge in pixels; 0 keeps the original size.
        public var maxDimension: Int

        public init(name: String, format: String = "same", quality: Double = 0.75, maxDimension: Int = 0) {
            self.name = name
            self.format = format
            self.quality = quality
            self.maxDimension = maxDimension
        }

        enum CodingKeys: String, CodingKey { case name, format, quality, maxDimension }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name, default: "Preset")
            format = try container.decode(String.self, forKey: .format, default: "same")
            quality = try container.decode(Double.self, forKey: .quality, default: 0.75)
            maxDimension = try container.decode(Int.self, forKey: .maxDimension, default: 0)
        }
    }

    static func presetValue(_ preset: Preset) -> SettingValue {
        (try? SettingValue(encoding: preset)) ?? .null
    }

    public init() {}

    public let manifest = ModuleManifest(
        id: ImageCompressorModule.id,
        name: LocalizedText(en: "Image Compression", zhHans: "图片压缩", ko: "이미지 압축"),
        summary: LocalizedText(en: "Compress and resize JPEG, PNG and HEIC images in batches with reusable presets.",
                               zhHans: "使用可复用的预设批量压缩、缩放 JPEG、PNG 和 HEIC 图片。",
                               ko: "재사용 가능한 프리셋으로 JPEG, PNG, HEIC 이미지를 일괄 압축하고 크기를 조정합니다."),
        version: "1.0.0",
        icon: "photo.stack",
        category: .convert,
        supportedTypes: ["public.image"],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "presets", title: LocalizedText(en: "Presets", zhHans: "压缩预设", ko: "프리셋"), fields: [
                .objectList(Key.presets, LocalizedText(en: "Presets", zhHans: "预设", ko: "프리셋"), itemFields: [
                    .text("name", LocalizedText(en: "Name", zhHans: "名称", ko: "이름")),
                    .choice("format", LocalizedText(en: "Output format", zhHans: "输出格式", ko: "출력 형식"), options: [
                        SettingOption("same", LocalizedText(en: "Same as original", zhHans: "与原图相同", ko: "원본과 동일")),
                        SettingOption("jpeg", "JPEG"), SettingOption("heic", "HEIC"), SettingOption("png", "PNG"),
                    ], default: "same"),
                    .number("quality", LocalizedText(en: "Quality", zhHans: "质量", ko: "품질"), default: 0.75, range: 0.1...1, step: 0.05),
                    .integer("maxDimension", LocalizedText(en: "Max long edge (px, 0 = keep)", zhHans: "最长边（像素，0 为不缩放）",
                                                           ko: "최대 긴 변(px, 0 = 유지)"), default: 0, range: 0...20000, step: 100),
                ], titleKey: "name", default: [
                    ImageCompressorModule.presetValue(Preset(name: "Balanced", quality: 0.75)),
                    ImageCompressorModule.presetValue(Preset(name: "Web 1920", format: "jpeg", quality: 0.7, maxDimension: 1920)),
                    ImageCompressorModule.presetValue(Preset(name: "Small 1280", format: "jpeg", quality: 0.6, maxDimension: 1280)),
                    ImageCompressorModule.presetValue(Preset(name: "HEIC", format: "heic", quality: 0.65)),
                ]),
                .text(Key.defaultPreset, LocalizedText(en: "Preset used by “Quick Compress”", zhHans: "“快速压缩”使用的预设", ko: "“빠른 압축”에 사용할 프리셋"),
                      default: "Balanced"),
            ]),
            SettingsSection(id: "output", title: LocalizedText(en: "Output", zhHans: "输出", ko: "출력"), fields: [
                .choice(Key.outputMode, LocalizedText(en: "Save compressed images", zhHans: "压缩后保存到", ko: "압축 이미지 저장"), options: [
                    SettingOption("suffix", LocalizedText(en: "Next to the original, with a suffix", zhHans: "原图旁边（追加后缀）", ko: "원본 옆(접미사 추가)")),
                    SettingOption("folder", LocalizedText(en: "In a subfolder", zhHans: "子文件夹中", ko: "하위 폴더")),
                ], default: "suffix"),
                .text(Key.suffix, LocalizedText(en: "Suffix", zhHans: "后缀", ko: "접미사"), default: "-compressed",
                      visibleWhen: SettingCondition(key: Key.outputMode, equals: ["suffix"])),
                .text(Key.folderName, LocalizedText(en: "Subfolder name", zhHans: "子文件夹名", ko: "하위 폴더 이름"), default: "Compressed",
                      visibleWhen: SettingCondition(key: Key.outputMode, equals: ["folder"])),
                .toggle(Key.keepMetadata, LocalizedText(en: "Keep metadata (EXIF, GPS)", zhHans: "保留元数据（EXIF、GPS）", ko: "메타데이터 유지(EXIF, GPS)"),
                        default: false),
                .toggle(Key.skipLarger, LocalizedText(en: "Discard results larger than the original", zhHans: "结果比原图大时丢弃", ko: "원본보다 크면 버리기"),
                        default: true),
            ]),
        ]),
        permissions: [.readSelection, .writeFiles]
    )

    public func presets(settings: ModuleSettings) -> [Preset] {
        let presets = settings[Key.presets].arrayValue?.compactMap { try? $0.decode(Preset.self) } ?? []
        return presets.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        let rule = MenuRule.files(Self.imageExtensions, typeIdentifiers: ["public.image"])
        var actions = [ActionDescriptor(
            id: "quick", title: LocalizedText(en: "Quick Compress", zhHans: "快速压缩", ko: "빠른 압축"),
            icon: "photo.badge.arrow.down", group: .convert, order: 30, rule: rule, execution: .task
        )]
        for (index, preset) in presets(settings: settings).enumerated() {
            actions.append(ActionDescriptor(
                id: "preset.\(index)", title: LocalizedText(stringLiteral: preset.name), icon: "slider.horizontal.3",
                group: .compress, order: index * 10, rule: rule, execution: .task, parameters: ["preset": preset.name]
            ))
        }
        return actions
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let settings = invocation.settings
        let all = presets(settings: settings)
        let wanted = invocation.parameters["preset"] ?? settings.string(Key.defaultPreset)
        let preset = all.first { $0.name == wanted } ?? all.first ?? Preset(name: "Balanced")

        let files = invocation.selection.files.map(\.url)
        guard !files.isEmpty else {
            throw ModuleError.invalidSelection(LocalizedText(en: "Select images to compress.", zhHans: "请选择要压缩的图片。", ko: "압축할 이미지를 선택하세요.").localized)
        }

        var outputs: [URL] = []
        var before: Int64 = 0
        var after: Int64 = 0
        var failures: [String] = []
        for (index, file) in files.enumerated() {
            try context.checkCancellation()
            context.reporter.progress(completed: index, of: files.count, message: file.lastPathComponent)
            do {
                if let result = try ImageCompressor.compress(file, preset: preset, settings: settings) {
                    outputs.append(result.output)
                    before += result.originalSize
                    after += result.compressedSize
                    context.reporter.log("\(file.lastPathComponent): \(ByteSize.format(result.originalSize)) → \(ByteSize.format(result.compressedSize))")
                } else {
                    context.reporter.log("\(file.lastPathComponent): " + LocalizedText(en: "already optimal, skipped", zhHans: "已是最优，跳过", ko: "이미 최적, 건너뜀").localized)
                }
            } catch {
                failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                context.reporter.log(failures.last!)
            }
        }
        context.reporter.progress(1, message: nil)
        if outputs.isEmpty, !failures.isEmpty {
            throw ModuleError.failed(failures.joined(separator: "\n"))
        }
        let saved = before - after
        let percent = before > 0 ? Int((Double(saved) / Double(before) * 100).rounded()) : 0
        let message = LocalizedText(
            en: "\(outputs.count) image(s): \(ByteSize.format(before)) → \(ByteSize.format(after)) (−\(percent)%)",
            zhHans: "\(outputs.count) 张图片：\(ByteSize.format(before)) → \(ByteSize.format(after))（−\(percent)%）",
            ko: "이미지 \(outputs.count)개: \(ByteSize.format(before)) → \(ByteSize.format(after)) (−\(percent)%)"
        ).localized + (failures.isEmpty ? "" : "\n" + failures.joined(separator: "\n"))
        return ActionOutcome(message: message, outputs: outputs, revealOutputs: true)
    }
}

enum ImageCompressionError: LocalizedError {
    case unreadable, encoderUnavailable(String), writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return LocalizedText(en: "Cannot read image.", zhHans: "无法读取图片。", ko: "이미지를 읽을 수 없습니다.").localized
        case .encoderUnavailable(let type): return "No encoder for \(type)."
        case .writeFailed: return LocalizedText(en: "Cannot write image.", zhHans: "无法写入图片。", ko: "이미지를 쓸 수 없습니다.").localized
        }
    }
}

enum ImageCompressor {
    struct Result {
        var output: URL
        var originalSize: Int64
        var compressedSize: Int64
    }

    static func compress(_ input: URL, preset: ImageCompressorModule.Preset, settings: ModuleSettings) throws -> Result? {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { throw ImageCompressionError.unreadable }

        let outputType = outputUTType(for: preset.format, sourceType: sourceType as String)
        let destinationURL = outputURL(for: input, type: outputType, settings: settings)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Thumbnail API decodes, applies EXIF orientation and downsamples in one memory-efficient pass.
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longEdge = max(width, height)
        options[kCGImageSourceThumbnailMaxPixelSize] = preset.maxDimension > 0 ? min(preset.maxDimension, max(longEdge, 1)) : max(longEdge, 1)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageCompressionError.unreadable
        }

        let temporary = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(destinationURL.pathExtension)")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, outputType.identifier as CFString, 1, nil) else {
            throw ImageCompressionError.encoderUnavailable(outputType.identifier)
        }
        var destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(preset.quality, 0.05), 1.0),
        ]
        if settings.bool(ImageCompressorModule.Key.keepMetadata) {
            for (key, value) in properties where key != kCGImagePropertyOrientation {
                destinationProperties[key] = value
            }
            // Pixels are already rotated by the thumbnail transform.
            destinationProperties[kCGImagePropertyOrientation] = 1
        }
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw ImageCompressionError.writeFailed
        }

        let originalSize = fileSize(input)
        let compressedSize = fileSize(temporary)
        let sameDimensions = preset.maxDimension == 0 || preset.maxDimension >= longEdge
        if settings.bool(ImageCompressorModule.Key.skipLarger), sameDimensions, compressedSize >= originalSize {
            try? FileManager.default.removeItem(at: temporary)
            return nil
        }
        try FileManager.default.moveItem(at: temporary, to: destinationURL)
        return Result(output: destinationURL, originalSize: originalSize, compressedSize: compressedSize)
    }

    static func outputUTType(for format: String, sourceType: String) -> UTType {
        switch format {
        case "jpeg": return .jpeg
        case "heic": return .heic
        case "png": return .png
        default:
            let type = UTType(sourceType) ?? .jpeg
            // Formats ImageIO cannot encode well (GIF animation, WebP, BMP) fall back to JPEG.
            if type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .heic) || type.conforms(to: .tiff) {
                return type
            }
            if type.identifier == "public.heif" { return .heic }
            return .jpeg
        }
    }

    static func outputURL(for input: URL, type: UTType, settings: ModuleSettings) -> URL {
        let ext = type.preferredFilenameExtension ?? input.pathExtension
        let base = input.deletingPathExtension().lastPathComponent
        let folder = input.deletingLastPathComponent()
        if settings.string(ImageCompressorModule.Key.outputMode) == "folder" {
            let name = settings.nonEmptyString(ImageCompressorModule.Key.folderName) ?? "Compressed"
            let directory = folder.appendingPathComponent(UniqueFileNamer.sanitizedFileName(name), isDirectory: true)
            return UniqueFileNamer.availableURL(in: directory, baseName: base, pathExtension: ext)
        }
        let suffix = settings.string(ImageCompressorModule.Key.suffix)
        return UniqueFileNamer.availableURL(in: folder, baseName: base + (suffix.isEmpty ? "-compressed" : suffix), pathExtension: ext)
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}

enum ByteSize {
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
