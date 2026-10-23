import AppKit
import FinderPlusCore
import FinderPlusUI
import SwiftUI

extension FileCreatorModule: ModuleLibraryProviding {
    public var librarySection: ModuleLibrarySection { .templates }

    @MainActor
    public func makeLibraryView(context: ModuleUIContext) -> AnyView {
        AnyView(TemplatesLibraryView(module: self, context: context))
    }
}

/// Manage files in the templates folder: menu templates and `default.<ext>` content overrides.
struct TemplatesLibraryView: View {
    let module: FileCreatorModule
    let context: ModuleUIContext
    @State private var files: [URL] = []
    @State private var errorMessage: String?

    private var directory: URL { module.templatesDirectory }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedText(
                en: "Files here appear under “New from Template”. A file named default.<ext> (e.g. default.md, default.docx) replaces the built-in content of that type.",
                zhHans: "此处的文件会出现在“从模板创建”中。命名为 default.<扩展名> 的文件（如 default.md、default.docx）会替换该类型的内置初始内容。",
                ko: "여기의 파일은 “템플릿에서 만들기”에 표시됩니다. default.<확장자> 파일(예: default.md, default.docx)은 해당 형식의 기본 내용을 대체합니다."
            ).localized)
            .font(.callout).foregroundStyle(.secondary)

            if files.isEmpty {
                Text(LocalizedText(en: "No templates yet.", zhHans: "还没有模板。", ko: "아직 템플릿이 없습니다.").localized)
                    .foregroundStyle(.secondary)
            }
            ForEach(files, id: \.self) { file in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 22, height: 22)
                    Text(file.lastPathComponent)
                    if file.deletingPathExtension().lastPathComponent.lowercased() == "default" {
                        Text(LocalizedText(en: "default content", zhHans: "默认内容", ko: "기본 내용").localized)
                            .font(.caption).foregroundStyle(.blue)
                    }
                    Spacer()
                    Button(LocalizedText(en: "Edit", zhHans: "编辑", ko: "편집").localized) { NSWorkspace.shared.open(file) }
                    Button { trash(file) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(LocalizedText(en: "Add Template…", zhHans: "添加模板…", ko: "템플릿 추가…").localized) { add() }
                Button(LocalizedText(en: "Open Templates Folder", zhHans: "打开模板文件夹", ko: "템플릿 폴더 열기").localized) {
                    NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(directory))
                }
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        // Template files feed the Finder menu, so refresh the published snapshot.
        context.settings.wrappedValue = context.settings.wrappedValue
    }

    private func add() {
        guard let source = OpenPanel.choose(.file) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: UniqueFileNamer.availableURL(in: directory, fileName: source.lastPathComponent))
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trash(_ file: URL) {
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
