import AppKit
import WebKit

/// Renders an HTML file to a paginated PDF with WebKit's print pipeline.
///
/// WKWebView only paginates through `NSPrintOperation`, and that operation needs the web view to
/// live in a window, so an invisible window hosts it for the duration of the export.
@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {
    struct PageSetup {
        var paperSize: NSSize
        var marginPoints: CGFloat
    }

    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var window: NSWindow?

    static func pageSize(named name: String) -> NSSize {
        switch name {
        case "letter": return NSSize(width: 612, height: 792)
        case "legal": return NSSize(width: 612, height: 1008)
        case "a5": return NSSize(width: 419.53, height: 595.28)
        case "a3": return NSSize(width: 841.89, height: 1190.55)
        default: return NSSize(width: 595.28, height: 841.89)
        }
    }

    func render(htmlFile: URL, to output: URL, page: PageSetup) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let contentWidth = page.paperSize.width - page.marginPoints * 2
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: page.paperSize.height), configuration: configuration)
        webView.navigationDelegate = self

        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        self.window = window
        defer {
            window.contentView = nil
            window.close()
            self.window = nil
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
        // Wait for web fonts (KaTeX) so formulas are measured with the right glyphs.
        _ = try? await webView.callAsyncJavaScript("await document.fonts.ready; return true;", arguments: [:],
                                                   in: nil, contentWorld: .page)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = page.paperSize
        printInfo.topMargin = page.marginPoints
        printInfo.bottomMargin = page.marginPoints
        printInfo.leftMargin = page.marginPoints
        printInfo.rightMargin = page.marginPoints
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds

        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            printContinuation = continuation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        if !succeeded || !FileManager.default.fileExists(atPath: output.path) {
            // Fallback: a single tall page is better than nothing.
            let data = try await webView.pdf(configuration: WKPDFConfiguration())
            try data.write(to: output, options: .atomic)
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printContinuation?.resume(returning: success)
        printContinuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}
