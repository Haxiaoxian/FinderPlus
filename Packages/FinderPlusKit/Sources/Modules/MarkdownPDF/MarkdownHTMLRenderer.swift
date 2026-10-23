import Foundation
import Markdown

/// Markdown (GFM) → standalone HTML document with theme CSS, KaTeX math and highlight.js.
public enum MarkdownHTMLRenderer {
    public struct Options: Sendable {
        public var theme: String = "github"
        public var fontFamily: String = ""
        public var codeFontFamily: String = ""
        public var fontSize: Int = 12
        public var enableMath = true
        public var enableHighlight = true
        public var extraCSS = ""
        public var title = ""

        public init() {}
    }

    /// Converts Markdown to an HTML fragment. Math is protected from the Markdown parser so that
    /// `_` and `*` inside formulas are not treated as emphasis.
    public static func fragment(from markdown: String, protectMath: Bool = true) -> String {
        let (text, math) = protectMath ? MathProtector.protect(markdown) : (markdown, [])
        var html = HTMLFormatter.format(Document(parsing: text))
        for (index, formula) in math.enumerated() {
            html = html.replacingOccurrences(of: MathProtector.token(index), with: escapeHTML(formula))
        }
        return html
    }

    /// Full HTML document. `resources` is the folder containing `katex/` and `highlight/`;
    /// `baseURL` resolves relative image links (normally the Markdown file's folder).
    public static func document(from markdown: String, options: Options, resources: URL?, baseURL: URL?) -> String {
        let body = fragment(from: markdown, protectMath: options.enableMath)
        var head = ""
        if let baseURL {
            head += "<base href=\"\(escapeHTML(baseURL.absoluteString))\">\n"
        }
        head += "<style>\n\(Themes.css(for: options))\n</style>\n"
        var scripts = ""
        if let resources {
            if options.enableMath {
                head += stylesheet(resources.appendingPathComponent("katex/katex.min.css"))
                scripts += script(resources.appendingPathComponent("katex/katex.min.js"))
                scripts += script(resources.appendingPathComponent("katex/auto-render.min.js"))
                scripts += """
                <script>renderMathInElement(document.body, {delimiters: [
                  {left: "$$", right: "$$", display: true}, {left: "$", right: "$", display: false},
                  {left: "\\\\[", right: "\\\\]", display: true}, {left: "\\\\(", right: "\\\\)", display: false}
                ], ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"], throwOnError: false});</script>

                """
            }
            if options.enableHighlight {
                head += stylesheet(resources.appendingPathComponent("highlight/github.min.css"))
                scripts += script(resources.appendingPathComponent("highlight/highlight.min.js"))
                scripts += "<script>hljs.highlightAll();</script>\n"
            }
        }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <title>\(escapeHTML(options.title))</title>
        \(head)</head>
        <body><article class="markdown-body">
        \(body)
        </article>
        \(scripts)</body></html>
        """
    }

    static func stylesheet(_ url: URL) -> String {
        "<link rel=\"stylesheet\" href=\"\(escapeHTML(url.absoluteString))\">\n"
    }

    static func script(_ url: URL) -> String {
        "<script src=\"\(escapeHTML(url.absoluteString))\"></script>\n"
    }

    static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Replaces `$…$` and `$$…$$` outside code with private-use placeholders before parsing.
enum MathProtector {
    static func token(_ index: Int) -> String { "\u{E000}\(index)\u{E001}" }

    static func protect(_ source: String) -> (String, [String]) {
        let chars = Array(source)
        var output = ""
        var math: [String] = []
        var index = 0
        var atLineStart = true
        var fence: String?

        func copyLine() {
            while index < chars.count, chars[index] != "\n" {
                output.append(chars[index])
                index += 1
            }
            if index < chars.count {
                output.append("\n")
                index += 1
            }
        }

        while index < chars.count {
            if atLineStart {
                var probe = index
                while probe < chars.count, chars[probe] == " ", probe - index < 4 { probe += 1 }
                let marker = String(chars[probe..<min(probe + 3, chars.count)])
                if marker == "```" || marker == "~~~" {
                    if fence == nil { fence = marker } else if fence == marker { fence = nil }
                    copyLine()
                    continue
                }
                if fence != nil {
                    copyLine()
                    continue
                }
                atLineStart = false
            }

            let character = chars[index]
            switch character {
            case "\n":
                output.append(character)
                index += 1
                atLineStart = true
                continue
            case "\\":
                output.append(character)
                if index + 1 < chars.count {
                    output.append(chars[index + 1])
                    if chars[index + 1] == "\n" { atLineStart = true }
                }
                index += 2
                continue
            case "`":
                var end = index
                while end < chars.count, chars[end] == "`" { end += 1 }
                let run = end - index
                var scan = end
                var closing: Int?
                while scan < chars.count, chars[scan] != "\n" {
                    if chars[scan] == "`" {
                        var stop = scan
                        while stop < chars.count, chars[stop] == "`" { stop += 1 }
                        if stop - scan == run { closing = scan; break }
                        scan = stop
                    } else {
                        scan += 1
                    }
                }
                let stop = closing.map { $0 + run } ?? end
                output.append(contentsOf: String(chars[index..<stop]))
                index = stop
                continue
            case "$":
                if index + 1 < chars.count, chars[index + 1] == "$" {
                    var scan = index + 2
                    while scan + 1 < chars.count, !(chars[scan] == "$" && chars[scan + 1] == "$") { scan += 1 }
                    if scan + 1 < chars.count {
                        math.append(String(chars[index...(scan + 1)]))
                        output.append(token(math.count - 1))
                        index = scan + 2
                        continue
                    }
                } else if index + 1 < chars.count, !chars[index + 1].isWhitespace {
                    var scan = index + 1
                    while scan < chars.count, chars[scan] != "\n", chars[scan] != "$" {
                        scan += chars[scan] == "\\" ? 2 : 1
                    }
                    if scan < chars.count, chars[scan] == "$", !chars[scan - 1].isWhitespace,
                       !(scan + 1 < chars.count && chars[scan + 1].isNumber) {
                        math.append(String(chars[index...scan]))
                        output.append(token(math.count - 1))
                        index = scan + 1
                        continue
                    }
                }
            default:
                break
            }
            output.append(character)
            index += 1
        }
        return (output, math)
    }
}

enum Themes {
    static let defaultSans = "-apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", \"Apple SD Gothic Neo\", \"Helvetica Neue\", sans-serif"
    static let defaultSerif = "\"Songti SC\", \"STSong\", \"AppleMyungjo\", \"Times New Roman\", Georgia, serif"
    static let defaultMono = "\"SF Mono\", Menlo, Monaco, \"PingFang SC\", monospace"

    static func css(for options: MarkdownHTMLRenderer.Options) -> String {
        let body = options.fontFamily.isEmpty ? (options.theme == "academic" ? defaultSerif : defaultSans) : options.fontFamily
        let mono = options.codeFontFamily.isEmpty ? defaultMono : options.codeFontFamily
        let base = """
        :root { color-scheme: light; }
        html, body { margin: 0; padding: 0; background: #fff; }
        body { font-family: \(body); font-size: \(options.fontSize)pt; line-height: 1.6; color: #1f2328;
               -webkit-print-color-adjust: exact; }
        .markdown-body { max-width: 100%; word-wrap: break-word; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.6em; page-break-after: avoid; break-after: avoid; }
        p, ul, ol, blockquote, table, pre { margin: 0 0 1em; }
        img { max-width: 100%; page-break-inside: avoid; }
        code, pre { font-family: \(mono); font-size: 0.88em; }
        pre { padding: 0.9em 1em; overflow-x: auto; border-radius: 6px; background: #f6f8fa; white-space: pre-wrap;
              page-break-inside: avoid; break-inside: avoid; }
        pre code { background: none; padding: 0; }
        pre code.hljs { padding: 0; background: transparent; }
        :not(pre) > code { padding: 0.15em 0.35em; border-radius: 4px; background: rgba(175, 184, 193, 0.2); }
        table { border-collapse: collapse; width: auto; page-break-inside: avoid; }
        th, td { border: 1px solid #d0d7de; padding: 0.35em 0.8em; }
        th { background: #f6f8fa; font-weight: 600; }
        blockquote { padding: 0 1em; color: #59636e; border-left: 0.25em solid #d0d7de; }
        hr { border: 0; border-top: 1px solid #d0d7de; margin: 1.5em 0; }
        li > input[type=checkbox] { margin-right: 0.4em; }
        .katex-display { overflow-x: auto; overflow-y: hidden; }
        """
        let theme: String
        switch options.theme {
        case "academic":
            theme = """
            body { color: #111; text-align: justify; }
            h1 { font-size: 1.8em; text-align: center; border: 0; }
            h2 { font-size: 1.35em; border-bottom: 1px solid #999; padding-bottom: 0.2em; }
            h3 { font-size: 1.15em; }
            th, td { border: 0; border-bottom: 1px solid #999; }
            thead th { border-top: 1.5px solid #111; border-bottom: 1px solid #111; background: none; }
            tbody tr:last-child td { border-bottom: 1.5px solid #111; }
            """
        case "minimal":
            theme = """
            body { color: #222; }
            h1, h2 { font-weight: 600; }
            pre { background: #fafafa; border: 1px solid #eee; }
            th { background: none; }
            """
        default:
            theme = """
            h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
            h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid #d1d9e0; }
            h3 { font-size: 1.25em; }
            a { color: #0969da; text-decoration: none; }
            """
        }
        return base + "\n" + theme + "\n" + options.extraCSS
    }
}
