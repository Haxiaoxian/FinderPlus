# 路线图

## 阶段 1 — Apple Silicon（当前）

- [x] 宿主程序、模块协议、Schema 设置、菜单快照、请求收件箱、执行引擎、任务中心
- [x] 九个内置模块 + 脚本功能包
- [x] 中 / 英 / 韩三语
- [x] arm64 构建配置（`Config/Architecture.xcconfig`：`FP_ARCHS = arm64`）与 CI（`macos-15` Apple Silicon 运行器）
- [ ] **首次在 Mac 上编译并修正编译错误**（代码在 Linux 上编写，未经编译）
- [ ] 真机验证清单：
  - [ ] Finder 扩展在 `/` 与外置卷上出现，子菜单/图标/分隔符显示正常
  - [ ] 未运行时由 Finder 唤醒主程序（后台模式、无 Dock 图标）
  - [ ] App Group 在扩展与主程序间共享（需 Team ID 签名）
  - [ ] Terminal / iTerm2 自动化权限提示与命令执行；“仅输入”模式
  - [ ] Markdown → PDF 分页（`NSPrintOperation` + 离屏 `WKWebView`），KaTeX 字体加载
  - [ ] 生成的 docx/xlsx/pptx 能被 Office、Pages/Numbers/Keynote 打开
  - [ ] 新建后进入重命名（辅助功能权限）
  - [ ] 侧边栏 API 在 macOS 14 / 15 / 26 上的可用性
- [ ] 应用图标正式设计、发布签名与公证（`docs/RELEASING.md`）

## 阶段 2 — Intel

代码不包含架构相关实现，Intel 支持主要是构建与验证：

1. `make universal`（或 `FP_ARCHS = arm64 x86_64`）生成 Universal 应用，`lipo -archs` 确认包含两种架构。
2. CI 中启用 `app-universal` 作业（目前为手动触发、允许失败）。
3. Intel 特有验证点：
   - Homebrew 位于 `/usr/local`（`ExecutableLocator` 已包含该路径，顺序在 `/opt/homebrew` 之后）；
   - Python / Conda 默认位置（`/usr/local/bin/python3`、`~/miniconda3`）；
   - 在 Intel Mac 或 Rosetta 下运行单元测试：`arch -x86_64 swift test --package-path Packages/FinderPlusKit`；
   - MarkItDown 依赖（如 `onnxruntime`、`magika`）在 x86_64 上的 wheel 可用性。
4. 发布产物改为 `FinderPlus-<version>-universal.zip`（`scripts/package.sh universal`）。

## 之后

- XPC 执行服务：把原生模块执行移到独立进程，实现崩溃隔离。
- 模块仓库与在线更新（签名校验）。
- 更多模块：批量重命名、压缩/解压、视频转码、OCR、Git 状态等。
- 自定义侧边栏图标（实验性后端，需先找到安全可恢复的实现方式）。
- MarkItDown 联网模式（如 LLM 图片描述）需明确区分本地/联网并单独授权。
