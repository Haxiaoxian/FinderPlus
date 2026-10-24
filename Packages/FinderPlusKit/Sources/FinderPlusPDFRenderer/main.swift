import AppKit

// FinderPlusPDFRenderer — a short-lived helper that turns one HTML file into a paginated PDF.
//
// WebKit lives only in this process, so the FinderPlus host never loads it: the menu bar app stays
// small while idle, and everything WebKit allocates during an export is returned when this exits.
//
// Usage: FinderPlusPDFRenderer <input.html> <output.pdf> <paper width pt> <paper height pt> <margin pt>

let arguments = CommandLine.arguments
guard arguments.count == 6,
      let paperWidth = Double(arguments[3]), let paperHeight = Double(arguments[4]), let margin = Double(arguments[5]) else {
    FileHandle.standardError.write(Data("usage: FinderPlusPDFRenderer <input.html> <output.pdf> <width> <height> <margin>\n".utf8))
    exit(64)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let page = PDFRenderer.PageSetup(paperSize: NSSize(width: paperWidth, height: paperHeight), marginPoints: margin)

let application = NSApplication.shared
// Printing needs a window server connection, but this helper must never show up in the Dock.
application.setActivationPolicy(.accessory)
Task { @MainActor in
    do {
        try await PDFRenderer().render(htmlFile: input, to: output, page: page)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
application.run()
