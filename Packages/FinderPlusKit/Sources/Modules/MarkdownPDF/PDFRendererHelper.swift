import FinderPlusCore
import Foundation

/// Runs the `FinderPlusPDFRenderer` helper executable. WebKit is only ever loaded there, so the
/// FinderPlus host stays small while idle and gets all of WebKit's memory back after each export.
enum PDFRendererHelper {
    struct PageSetup {
        var paperSize: CGSize
        var marginPoints: CGFloat
    }

    static let executableName = "FinderPlusPDFRenderer"
    /// Generous: a long document with math waits for fonts and lays out every page.
    static let timeout: TimeInterval = 300

    static func pageSize(named name: String) -> CGSize {
        switch name {
        case "letter": return CGSize(width: 612, height: 792)
        case "legal": return CGSize(width: 612, height: 1008)
        case "a5": return CGSize(width: 419.53, height: 595.28)
        case "a3": return CGSize(width: 841.89, height: 1190.55)
        default: return CGSize(width: 595.28, height: 841.89)
        }
    }

    static func locate() -> URL? {
        // Inside FinderPlus.app the helper sits next to the main executable (Contents/MacOS).
        if let url = Bundle.main.url(forAuxiliaryExecutable: executableName) { return url }
        // SwiftPM builds (tests): the products directory that also holds this module's resources.
        let sibling = Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent(executableName)
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    static func render(htmlFile: URL, to output: URL, page: PageSetup, processes: ProcessRunner) async throws {
        guard let helper = locate() else {
            throw ModuleError.dependencyMissing(LocalizedText(
                en: "The PDF renderer is missing from FinderPlus.app. Please reinstall FinderPlus.",
                zhHans: "FinderPlus.app 中缺少 PDF 渲染组件，请重新安装 FinderPlus。",
                ko: "FinderPlus.app에 PDF 렌더러가 없습니다. FinderPlus를 다시 설치하세요.").localized)
        }
        let arguments = [htmlFile.path, output.path,
                         "\(Double(page.paperSize.width))", "\(Double(page.paperSize.height))", "\(Double(page.marginPoints))"]
        // Cancelling the task terminates the helper (see ProcessRunner).
        let result = try await processes.run(helper, arguments: arguments, timeout: timeout)
        if Task.isCancelled { throw ModuleError.cancelled }
        guard result.succeeded, FileManager.default.fileExists(atPath: output.path) else {
            let detail = result.diagnosticTail.isEmpty ? "exit code \(result.exitCode)" : result.diagnosticTail
            throw ModuleError.failed(LocalizedText(en: "PDF rendering failed: \(detail)", zhHans: "PDF 渲染失败：\(detail)",
                                                   ko: "PDF 렌더링 실패: \(detail)").localized)
        }
    }
}
