# 安装 FinderPlus

适用于 Apple Silicon（M 系列芯片）Mac，macOS 14 或更新版本。

1. 打开 `FinderPlus-x.y.z-arm64.dmg`，把 **FinderPlus** 拖到 **应用程序（Applications）**。
2. 第一次打开：这个版本没有 Apple 开发者签名，macOS 会提示“无法验证开发者”。
   - 先双击打开一次，出现提示后点“完成”；
   - 打开 **系统设置 › 隐私与安全性**，在页面底部点击 **仍要打开**，再确认一次。
   - 或在“终端”中执行：`xattr -dr com.apple.quarantine /Applications/FinderPlus.app`
3. 启用 Finder 扩展：
   - macOS 15 及以后：**系统设置 › 通用 › 登录项与扩展**，在“扩展”里找到 FinderPlus 并打开；
   - macOS 14：**系统设置 › 隐私与安全性 › 扩展 › 已添加的扩展**，勾选 FinderPlus。
   - 也可以在 FinderPlus 主窗口点“打开扩展设置”。
4. 在 Finder 中右键文件、文件夹或空白处，选择 **FinderPlus** 菜单。

可选权限（用到时系统会询问）：
- **自动化**：在 Terminal / iTerm2 中运行 Python、R 脚本；
- **辅助功能**：新建文件后自动进入重命名；
- **通知**：后台任务完成提醒。

卸载：退出 FinderPlus，把它从“应用程序”移到废纸篓；数据位于 `~/Library/Application Support/FinderPlus`。

---

# Installing FinderPlus

For Apple Silicon Macs running macOS 14 or later.

1. Open the DMG and drag **FinderPlus** to **Applications**.
2. This build is not notarized. On first launch macOS blocks it: open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/FinderPlus.app`).
3. Enable the Finder extension: **System Settings › General › Login Items & Extensions** (macOS 15+) or **Privacy & Security › Extensions › Added Extensions** (macOS 14).
4. Right-click in Finder and choose **FinderPlus**.
