import FinderPlusCore
import FPAppearance
import FPFileCreator
import FPFolderIcon
import FPImageCompressor
import FPMarkdownPDF
import FPMarkItDown
import FPPathTools
import FPQuickOpen
import FPSidebar

/// Native modules compiled into FinderPlus.
///
/// Adding a native module = create `Sources/Modules/<Name>`, add `module("<Name>")` and the name
/// to `builtinModules` in Package.swift, and append one line here. Nothing else in the host or the
/// Finder extension changes.
public enum BuiltinModules {
    public static func make() -> [FinderPlusModule] {
        [
            FileCreatorModule(),
            PathToolsModule(),
            QuickOpenModule(),
            ImageCompressorModule(),
            MarkdownPDFModule(),
            MarkItDownModule(),
            FolderIconModule(),
            SidebarModule(),
            AppearanceModule(),
        ]
    }
}
