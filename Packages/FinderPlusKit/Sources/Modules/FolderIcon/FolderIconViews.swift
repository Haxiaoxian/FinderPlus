import AppKit
import FinderPlusCore
import FinderPlusUI
import SwiftUI
import UniformTypeIdentifiers

struct FolderIconPickerView: View {
    enum Source: String, CaseIterable, Identifiable {
        case library, packs, image
        var id: String { rawValue }
        var title: String {
            switch self {
            case .library: return LocalizedText(en: "Colors & Emblems", zhHans: "颜色与徽标", ko: "색상 및 엠블럼").localized
            case .packs: return LocalizedText(en: "Icon Packs", zhHans: "图标包", ko: "아이콘 팩").localized
            case .image: return LocalizedText(en: "Image File", zhHans: "图片文件", ko: "이미지 파일").localized
            }
        }
    }

    let module: FolderIconModule
    let context: ModuleUIContext

    @State private var source: Source = .library
    @State private var color = "default"
    @State private var symbol: String?
    @State private var imagePath: String?
    @State private var search = ""
    @State private var errorMessage: String?

    private var folders: [URL] { context.selection.folders.map(\.url) }

    private var spec: FolderIconSpec {
        switch source {
        case .library: return FolderIconSpec(kind: .generated, symbol: symbol, color: color)
        case .packs, .image: return FolderIconSpec(kind: .image, imagePath: imagePath)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                Group {
                    if let image = FolderIconRenderer.image(for: spec, size: 256) {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "folder").resizable().foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
                Text(folders.count == 1 ? folders[0].lastPathComponent
                     : LocalizedText(en: "\(folders.count) folders", zhHans: "\(folders.count) 个文件夹", ko: "폴더 \(folders.count)개").localized)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(width: 180)

            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch source {
                case .library: libraryPicker
                case .packs: packPicker
                case .image: imagePicker
                }

                HStack {
                    Spacer()
                    Button(LocalizedText(en: "Cancel", zhHans: "取消", ko: "취소").localized) { context.dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(LocalizedText(en: "Apply", zhHans: "应用", ko: "적용").localized) { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(source != .library && imagePath == nil)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
    }

    private var libraryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 13), spacing: 8) {
                ForEach(FolderIconCatalog.swatches) { swatch in
                    Button { color = swatch.hex } label: {
                        Circle()
                            .fill(FolderIconRenderer.color(from: swatch.hex).map { Color(nsColor: $0) } ?? Color(nsColor: .systemBlue).opacity(0.5))
                            .overlay(Circle().stroke(color == swatch.hex ? Color.accentColor : .clear, lineWidth: 3))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name.localized)
                }
            }
            TextField(LocalizedText(en: "Search symbols", zhHans: "搜索符号", ko: "기호 검색").localized, text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], spacing: 6) {
                    symbolButton(nil)
                    ForEach(filteredSymbols, id: \.self) { symbolButton($0) }
                }
            }
            .frame(minHeight: 200)
        }
    }

    private var filteredSymbols: [String] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let symbols = FolderIconCatalog.symbols
        guard !query.isEmpty else { return symbols }
        var result = symbols.filter { $0.contains(query) }
        // Allow any SF Symbol name typed exactly.
        if NSImage(systemSymbolName: query, accessibilityDescription: nil) != nil, !result.contains(query) {
            result.insert(query, at: 0)
        }
        return result
    }

    private func symbolButton(_ name: String?) -> some View {
        Button { symbol = name } label: {
            Group {
                if let name { Image(systemName: name) } else { Image(systemName: "nosign").foregroundStyle(.secondary) }
            }
            .font(.system(size: 18))
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(symbol == name ? Color.accentColor.opacity(0.25) : Color.clear))
        }
        .buttonStyle(.plain)
        .help(name ?? LocalizedText(en: "No emblem", zhHans: "无徽标", ko: "엠블럼 없음").localized)
    }

    private var packPicker: some View {
        let images = module.iconPackImages()
        return VStack(alignment: .leading) {
            if images.isEmpty {
                Text(LocalizedText(en: "No icon packs yet. Put image files into a subfolder of the icon packs folder.",
                                   zhHans: "还没有图标包。将图片放入图标包文件夹的子文件夹即可。",
                                   ko: "아이콘 팩이 없습니다. 아이콘 팩 폴더의 하위 폴더에 이미지를 넣으세요.").localized)
                    .foregroundStyle(.secondary)
                Button(LocalizedText(en: "Open Icon Packs Folder", zhHans: "打开图标包文件夹", ko: "아이콘 팩 폴더 열기").localized) {
                    let folder = FinderPlusPaths.ensureDirectory(module.iconPacksDirectory)
                    NSWorkspace.shared.open(folder)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                        ForEach(images, id: \.self) { item in
                            Button { imagePath = item.url.path } label: {
                                Image(nsImage: NSImage(contentsOf: item.url) ?? NSImage())
                                    .resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(imagePath == item.url.path ? Color.accentColor.opacity(0.25) : Color.clear))
                            }
                            .buttonStyle(.plain)
                            .help("\(item.pack) / \(item.url.lastPathComponent)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
    }

    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedText(en: "PNG, ICNS, JPEG or HEIC. Square images with transparency look best.",
                               zhHans: "支持 PNG、ICNS、JPEG、HEIC，推荐使用带透明背景的方形图片。",
                               ko: "PNG, ICNS, JPEG, HEIC 지원. 투명 배경의 정사각형 이미지를 권장합니다.").localized)
                .foregroundStyle(.secondary)
            Button(LocalizedText(en: "Choose Image…", zhHans: "选择图片…", ko: "이미지 선택…").localized) {
                if let url = OpenPanel.choose(.file, allowedContentTypes: [UTTypeReference(.image), UTTypeReference(.icns)]) {
                    imagePath = url.path
                }
            }
            if let imagePath { Text(imagePath).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
    }

    private func apply() {
        do {
            let history = FolderIconHistory(directory: FinderPlusPaths.ensureDirectory(context.dataDirectory))
            try FolderIconModule.apply(spec, to: folders, history: history)
            var settings = context.settings.wrappedValue
            FolderIconModule.remember(spec, in: &settings)
            context.settings.wrappedValue = settings
            context.dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// "Icons" page in the host: history with restore, and icon pack management.
struct FolderIconLibraryView: View {
    let module: FolderIconModule
    let context: ModuleUIContext
    @State private var entries: [FolderIconHistoryEntry] = []
    @State private var errorMessage: String?

    private var history: FolderIconHistory { FolderIconHistory(directory: context.dataDirectory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizedText(en: "Folder icon history", zhHans: "文件夹图标历史", ko: "폴더 아이콘 기록").localized).font(.headline)
                Spacer()
                Button(LocalizedText(en: "Open Icon Packs Folder", zhHans: "打开图标包文件夹", ko: "아이콘 팩 폴더 열기").localized) {
                    NSWorkspace.shared.open(FinderPlusPaths.ensureDirectory(module.iconPacksDirectory))
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            if entries.isEmpty {
                Text(LocalizedText(en: "No changes yet.", zhHans: "暂无修改记录。", ko: "아직 변경 사항이 없습니다.").localized)
                    .foregroundStyle(.secondary)
            }
            List(entries) { entry in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.folderPath)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading) {
                        Text(URL(fileURLWithPath: entry.folderPath).lastPathComponent)
                        Text("\(entry.folderPath) · \(entry.appliedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if entry.restored {
                        Text(LocalizedText(en: "Restored", zhHans: "已恢复", ko: "복원됨").localized).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(LocalizedText(en: "Restore Previous", zhHans: "恢复之前", ko: "이전으로 복원").localized) { restore(entry) }
                    }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.folderPath)]) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 240)
        }
        .onAppear { entries = history.load() }
    }

    private func restore(_ entry: FolderIconHistoryEntry) {
        do {
            try history.restore(entry)
            entries = history.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
