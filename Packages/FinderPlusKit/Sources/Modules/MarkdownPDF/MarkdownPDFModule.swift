import AppKit
import FinderPlusCore
import Foundation

/// Block 04.2 — export Markdown to paginated PDF (GFM tables, code highlighting, KaTeX math, CJK fonts).
public final class MarkdownPDFModule: FinderPlusModule {
    public static let id = "io.github.finderplus.markdown-pdf"

    enum Key {
        static let theme = "theme"
        static let fontFamily = "fontFamily"
        static let codeFontFamily = "codeFontFamily"
        static let fontSize = "fontSize"
        static let pageSize = "pageSize"
        static let margin = "margin"
        static let enableMath = "enableMath"
        static let enableHighlight = "enableHighlight"
        static let outputLocation = "outputLocation"
        static let outputFolder = "outputFolder"
        static let fileNamePattern = "fileNamePattern"
        static let openAfterExport = "openAfterExport"
        static let extraCSS = "extraCSS"
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx"]

    public init() {}

    public let manifest = ModuleManifest(
        id: MarkdownPDFModule.id,
        name: LocalizedText(en: "Markdown to PDF", zhHans: "Markdown 转 PDF", ko: "Markdown을 PDF로"),
        summary: LocalizedText(en: "Export Markdown to PDF with themes, CJK fonts, tables, code highlighting and math.",
                               zhHans: "将 Markdown 导出为 PDF，支持主题、中文字体、表格、代码高亮与数学公式。",
                               ko: "테마, CJK 글꼴, 표, 코드 강조, 수식을 지원하여 Markdown을 PDF로 내보냅니다."),
        version: "1.0.0",
        icon: "doc.richtext",
        category: .convert,
        supportedTypes: Array(MarkdownPDFModule.markdownExtensions),
        settings: SettingsSchema(sections: [
            SettingsSection(id: "style", title: LocalizedText(en: "Style", zhHans: "样式", ko: "스타일"), fields: [
                .choice(Key.theme, LocalizedText(en: "Theme", zhHans: "主题", ko: "테마"), options: [
                    SettingOption("github", "GitHub"),
                    SettingOption("academic", LocalizedText(en: "Academic (serif)", zhHans: "学术（衬线）", ko: "학술(세리프)")),
                    SettingOption("minimal", LocalizedText(en: "Minimal", zhHans: "简洁", ko: "미니멀")),
                ], default: "github"),
                .text(Key.fontFamily, LocalizedText(en: "Body font", zhHans: "正文字体", ko: "본문 글꼴"),
                      placeholder: LocalizedText(en: "System (PingFang SC for Chinese)", zhHans: "系统默认（中文使用苹方）", ko: "시스템 기본")),
                .text(Key.codeFontFamily, LocalizedText(en: "Code font", zhHans: "代码字体", ko: "코드 글꼴"),
                      placeholder: LocalizedText(stringLiteral: "SF Mono, Menlo")),
                .integer(Key.fontSize, LocalizedText(en: "Font size (pt)", zhHans: "字号（pt）", ko: "글꼴 크기(pt)"), default: 11, range: 8...24),
                .toggle(Key.enableHighlight, LocalizedText(en: "Highlight code", zhHans: "代码高亮", ko: "코드 강조"), default: true),
                .toggle(Key.enableMath, LocalizedText(en: "Render math ($…$, $$…$$)", zhHans: "渲染数学公式（$…$、$$…$$）", ko: "수식 렌더링($…$, $$…$$)"),
                        default: true),
                SettingField(key: Key.extraCSS, title: LocalizedText(en: "Additional CSS", zhHans: "附加 CSS", ko: "추가 CSS"),
                             kind: .multilineText, defaultValue: ""),
            ]),
            SettingsSection(id: "page", title: LocalizedText(en: "Page", zhHans: "页面", ko: "페이지"), fields: [
                .choice(Key.pageSize, LocalizedText(en: "Paper size", zhHans: "纸张大小", ko: "용지 크기"), options: [
                    SettingOption("a4", "A4"), SettingOption("letter", "US Letter"), SettingOption("legal", "US Legal"),
                    SettingOption("a5", "A5"), SettingOption("a3", "A3"),
                ], default: "a4"),
                .integer(Key.margin, LocalizedText(en: "Margins (mm)", zhHans: "页边距（毫米）", ko: "여백(mm)"), default: 18, range: 0...50),
            ]),
            SettingsSection(id: "output", title: LocalizedText(en: "Output", zhHans: "输出", ko: "출력"), fields: [
                .text(Key.fileNamePattern, LocalizedText(en: "File name", zhHans: "文件名", ko: "파일 이름"), default: "{name}.pdf",
                      help: LocalizedText(en: "{name} = Markdown file name, {date} = today", zhHans: "{name} 为原文件名，{date} 为当天日期",
                                          ko: "{name} = Markdown 파일 이름, {date} = 오늘 날짜")),
                .choice(Key.outputLocation, LocalizedText(en: "Save to", zhHans: "保存位置", ko: "저장 위치"), options: [
                    SettingOption("same", LocalizedText(en: "Same folder as the Markdown file", zhHans: "与 Markdown 文件相同的文件夹", ko: "Markdown 파일과 같은 폴더")),
                    SettingOption("custom", LocalizedText(en: "A specific folder", zhHans: "指定文件夹", ko: "지정한 폴더")),
                ], default: "same"),
                .path(Key.outputFolder, LocalizedText(en: "Folder", zhHans: "文件夹", ko: "폴더"), kind: .folder,
                      visibleWhen: SettingCondition(key: Key.outputLocation, equals: ["custom"])),
                .toggle(Key.openAfterExport, LocalizedText(en: "Open the PDF after exporting", zhHans: "导出后打开 PDF", ko: "내보낸 후 PDF 열기"),
                        default: false),
            ]),
        ]),
        permissions: [.readSelection, .writeFiles]
    )

    public func menuActions(settings: ModuleSettings) -> [ActionDescriptor] {
        [ActionDescriptor(id: "export", title: LocalizedText(en: "Export as PDF", zhHans: "导出 PDF", ko: "PDF로 내보내기"),
                          icon: "doc.richtext", group: .convert, order: 10,
                          rule: .files(Self.markdownExtensions), execution: .task)]
    }

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let settings = invocation.settings
        let files = invocation.selection.files.map(\.url)
        guard !files.isEmpty else { throw ModuleError.invalidSelection("No Markdown file selected.") }

        var options = MarkdownHTMLRenderer.Options()
        options.theme = settings.string(Key.theme)
        options.fontFamily = settings.string(Key.fontFamily)
        options.codeFontFamily = settings.string(Key.codeFontFamily)
        options.fontSize = max(settings.int(Key.fontSize), 6)
        options.enableMath = settings.bool(Key.enableMath)
        options.enableHighlight = settings.bool(Key.enableHighlight)
        options.extraCSS = settings.string(Key.extraCSS)
        let resources = Bundle.module.url(forResource: "web", withExtension: nil)
        let page = PDFRenderer.PageSetup(paperSize: PDFRenderer.pageSize(named: settings.string(Key.pageSize)),
                                         marginPoints: CGFloat(settings.int(Key.margin)) * 72 / 25.4)

        var outputs: [URL] = []
        for (index, file) in files.enumerated() {
            try context.checkCancellation()
            context.reporter.progress(completed: index, of: files.count, message: file.lastPathComponent)
            let markdown = try String(contentsOf: file, encoding: .utf8)
            options.title = file.deletingPathExtension().lastPathComponent
            let html = MarkdownHTMLRenderer.document(from: markdown, options: options, resources: resources,
                                                     baseURL: file.deletingLastPathComponent())
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("finderplus-md-\(UUID().uuidString).html")
            try html.write(to: scratch, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let output = outputURL(for: file, settings: settings)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let renderer = await PDFRenderer()
            try await renderer.render(htmlFile: scratch, to: output, page: page)
            context.reporter.log("\(file.lastPathComponent) → \(output.path)")
            outputs.append(output)
        }
        context.reporter.progress(1, message: nil)
        if settings.bool(Key.openAfterExport) {
            try? await context.system.open(outputs, withApplicationAt: nil)
        }
        return ActionOutcome(
            message: LocalizedText(en: "Exported \(outputs.count) PDF(s).", zhHans: "已导出 \(outputs.count) 个 PDF。",
                                   ko: "PDF \(outputs.count)개를 내보냈습니다.").localized,
            outputs: outputs,
            revealOutputs: !settings.bool(Key.openAfterExport)
        )
    }

    func outputURL(for file: URL, settings: ModuleSettings) -> URL {
        var pattern = settings.nonEmptyString(Key.fileNamePattern) ?? "{name}.pdf"
        if !pattern.lowercased().hasSuffix(".pdf") { pattern += ".pdf" }
        let name = UniqueFileNamer.sanitizedFileName(UniqueFileNamer.expand(pattern: pattern, sourceURL: file))
        var folder = file.deletingLastPathComponent()
        if settings.string(Key.outputLocation) == "custom", let custom = settings.nonEmptyString(Key.outputFolder) {
            folder = URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath, isDirectory: true)
        }
        return UniqueFileNamer.availableURL(in: folder, fileName: name)
    }
}
