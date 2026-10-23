# FinderPlus

模块化的 macOS Finder 增强平台：免费、开源、无需账户、默认本地处理。

FinderPlus 由 **宿主程序 + 功能模块 + Finder 集成层 + 统一执行引擎** 组成。所有功能（新建文件、复制路径、快捷打开、格式转换、文件夹图标、侧边栏……）都是独立模块，通过统一接口声明自己的菜单、设置、依赖和权限；主程序负责发现、配置、执行和展示。

- 最低系统：macOS 14 Sonoma
- 架构：**第一阶段 Apple Silicon（arm64）**；第二阶段加入 Intel（Universal Binary，构建开关已就绪）
- 语言：简体中文 / English / 한국어（跟随系统，可手动切换）

## 当前状态

> ⚠️ 本仓库代码在 Linux 环境中编写，**尚未在 Mac 上编译和运行过**。CI（GitHub Actions，Apple Silicon 运行器）会执行编译与单元测试；第一次在 Mac 上构建时请预期需要修正少量编译错误。需要真机验证的部分在下表中标注。

| 模块 | 功能 | 状态 |
|---|---|---|
| 文件创建 `FileCreator` | md/txt/docx/xlsx/pptx/pdf/csv/json/py/R + 自定义类型；生成**有效**的 Office/PDF；重名编号；创建后重命名/打开；模板 | 已实现 |
| 路径操作 `PathTools` | 复制绝对路径；批量分隔符；Shell 转义；自定义菜单名 | 已实现 |
| 快捷打开与运行 `QuickOpen` | VS Code / CotEditor / 任意应用（按扩展名规则）；Terminal / iTerm2；运行 Python（venv/Conda/自定义解释器/参数/工作目录/执行模式/结束行为）；Rscript | 已实现，终端集成需真机验证 |
| 图片压缩 `ImageCompressor` | JPEG/PNG/HEIC；质量、尺寸、预设；批量；大小对比；不覆盖原图 | 已实现 |
| Markdown 转 PDF `MarkdownPDF` | GFM 表格、代码高亮（highlight.js）、数学公式（KaTeX）、中文字体、主题、纸张与页边距 | 已实现，分页输出需真机验证 |
| MarkItDown `MarkItDown` | PDF/Word/PPT/Excel/HTML → Markdown；FinderPlus 管理独立 venv；批量；日志 | 已实现 |
| 文件夹图标 `FolderIcon` | 颜色 + SF Symbols 徽标、图标包、自定义图片、批量、预览、历史与恢复 | 已实现 |
| Finder 侧边栏 `Sidebar` | 收藏项添加/移除/排序、自动备份与恢复 | **实验性**（未公开 API，默认关闭）；自定义侧边栏图标暂未实现 |
| 个性化与外观 `Appearance` | 语言、主题、菜单名称/布局/图标/命名方式 | 已实现 |
| 脚本功能包 | 无需重新编译即可导入的 Shell/Python 功能；导入时审核并按内容哈希信任 | 已实现 |

## 快速开始（Apple Silicon Mac）

需要 Xcode 16+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
make bootstrap   # 安装 XcodeGen，创建 Config/Local.xcconfig（填写 Team ID）
make run         # 生成工程、Debug 构建（arm64）并启动
make test        # 运行 FinderPlusKit 单元测试
```

然后在“系统设置”中启用 FinderPlus 的 Finder 扩展（macOS 14：隐私与安全性 › 扩展；macOS 15+：通用 › 登录项与扩展），在 Finder 中右键即可看到 **FinderPlus** 菜单。

签名说明：Finder 扩展与主程序通过 App Group 共享数据，App Group 必须以 Team ID 开头，因此需要在 `Config/Local.xcconfig` 中设置 `DEVELOPMENT_TEAM`（免费的 Personal Team 也可以）。未签名构建可以运行主程序，但 Finder 菜单无法工作。

### Intel（第二阶段）

```sh
make universal   # ARCHS="arm64 x86_64"，输出 Universal 应用并用 lipo 打印架构
```

或在 `Config/Architecture.xcconfig` 中把 `FP_ARCHS` 改为 `arm64 x86_64`。所有代码均不依赖特定架构；Intel 需要单独验证的点见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 目录结构

```
App/                      宿主程序（SwiftUI + AppKit 窗口管理）
FinderSyncExtension/      Finder Sync 扩展（只读菜单快照，点击后把请求交给主程序）
Packages/FinderPlusKit/   Swift Package
  Sources/FinderPlusCore      模块协议、清单、设置 Schema、菜单规则/快照、共享路径（扩展也链接）
  Sources/FinderPlusEngine    执行引擎、任务中心、依赖检测、脚本功能包、AppKit 系统服务
  Sources/FinderPlusUI        自动生成设置表单、模块自定义视图协议
  Sources/Modules/*           每个功能模块一个 target，互不依赖
  Sources/FinderPlusBuiltinModules  内置模块列表（新增模块只需在此加一行）
  Tests/                      单元测试
Examples/ScriptPackages/  脚本功能包示例（校验和、字数统计）
Config/                   xcconfig（签名、架构）
docs/                     架构、模块开发、功能包格式、路线图、发布
```

## 文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发原生模块](docs/MODULE_DEVELOPMENT.md)
- [脚本功能包格式](docs/SCRIPT_PACKAGES.md)
- [路线图（含 Intel 计划）](docs/ROADMAP.md)
- [发布与公证](docs/RELEASING.md)

## 隐私与安全

- 所有处理默认在本机完成，不上传文件，不收集数据，无需账户。
- Finder 扩展运行在沙盒中，只读取菜单快照、写入请求，不接触用户文件。
- 外部命令一律以参数数组执行（不经过 Shell）；需要在终端中运行时，所有路径与参数都经过 POSIX 转义。
- 脚本功能包导入时显示来源、权限与完整命令，用户确认后按内容 SHA-256 信任；文件被修改后自动失去信任。
- 修改系统数据的操作（侧边栏）默认关闭、需要确认，并在每次修改前自动备份。

## 许可证

计划以 MIT 许可证发布（见 [LICENSE](LICENSE)）。内置的 KaTeX 与 highlight.js 分别遵循各自的 MIT / BSD-3-Clause 许可证（见 `Packages/FinderPlusKit/Sources/Modules/MarkdownPDF/Resources/web/*/LICENSE`）。
