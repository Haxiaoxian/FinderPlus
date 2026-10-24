# 架构说明

```
┌──────────────────────────── Finder ────────────────────────────┐
│  右键 ─► FinderSync 扩展（沙盒）                                 │
│          1. 读取 menu-snapshot.json（App Group）                 │
│          2. MenuResolver 按选中对象过滤 → NSMenu                  │
│          3. 点击：写 Inbox/<uuid>.json，打开 finderplus://dispatch │
└──────────────────────────────┬─────────────────────────────────┘
                               │  App Group 容器（共享）
┌──────────────────────────────▼─────────────────────────────────┐
│  FinderPlus 主程序（非沙盒，Hardened Runtime）                    │
│   AppModel ── ConfigurationStore（configuration.json）          │
│      │     └─ MenuSnapshotBuilder → menu-snapshot.json           │
│      ▼                                                           │
│   ExecutionEngine ── 校验（启用/信任/action 存在/hostOnly）        │
│      │              ── 需要时确认 ── interactive → 模块窗口         │
│      ▼              ── Task.detached 执行，错误隔离，任务中心记录    │
│   ModuleRegistry: 原生模块（编译期） + 脚本功能包（运行时）          │
└────────────────────────────────────────────────────────────────┘
```

## 四个层级

### 1. 宿主程序（`App/`）
窗口完全由 `AppDelegate` 管理：正常启动显示主窗口；被 Finder 通过 URL 唤醒时以 `.accessory` 模式在后台运行（无 Dock 图标）。关闭最后一个窗口后保持后台运行（可在通用设置关闭），以便右键操作即时响应。

后台常驻时尽量不占资源：
- 窗口关闭后连同 SwiftUI 视图一起释放，再次打开时重建。
- 主程序不链接 WebKit。Markdown 转 PDF 由 `Contents/MacOS/FinderPlusPDFRenderer` 辅助进程完成，导出结束即退出，WebKit 占用的内存随之归还（CI 用 `otool -L` 检查）。
- 不轮询：通过文件系统事件监视 `FinderPlus.app` 是否被替换为新版本，空闲时自动切换到新版本。
- 任务记录有上限：快捷操作只保留最近 30 条，较早任务只保留日志末尾 20 行。

页面：总览、模块中心、右键菜单管理（含实时预览）、模块设置（由 Schema 自动生成 + 模块自定义视图）、模板管理、图标管理、依赖管理、任务中心、通用设置。模板与图标页面不包含业务代码：它们展示实现了 `ModuleLibraryProviding` 的模块提供的视图。

### 2. 模块接口与注册中心（`FinderPlusCore`）

| 概念 | 类型 |
|---|---|
| 模块协议 | `FinderPlusModule`（`manifest`、`menuActions(settings:)`、`perform`、`dependencyStatuses`） |
| 模块清单 | `ModuleManifest`：ID、名称、版本、作者、图标、类别、稳定性、能力、支持类型、动作、设置 Schema、依赖、权限 |
| 菜单动作 | `ActionDescriptor`：标题/短标题、图标、分组、顺序、`MenuRule`、执行方式（immediate / task / interactive）、是否需确认、参数 |
| 显示条件 | `MenuRule`：上下文（选中项/空白处）、数量范围、项目类型、扩展名、UTType |
| 设置 | `SettingsSchema` → 主程序生成表单；值以 `SettingValue`（JSON 形态）保存在 `HostConfiguration` |
| 依赖 | `DependencyDescriptor`（可执行文件/应用/自定义）→ `DependencyStatus`（可带“一键修复”动作） |

模块之间不互相 import；需要的系统能力通过 `ModuleContext`（`SystemServices`、`ProcessRunner`、`TaskReporter`、数据目录）获得。

### 3. Finder 集成与执行引擎
- **菜单快照**：主程序在配置变化时把“已启用模块 × 当前设置 × 用户菜单自定义”编译为 `MenuSnapshot`。扩展只做纯数据匹配，不运行任何模块代码，因此新增模块不需要改动扩展。
- **请求交接**：URL 只携带 UUID；真正的请求文件位于 App Group 容器中，其他应用无法通过 URL Scheme 注入任务。请求有效期 120 秒。主程序启动时也会扫描收件箱，URL 事件丢失也不会丢请求。
- **执行**：每个请求在独立的 detached Task 中运行；模块抛出的错误只影响自身任务；长任务可取消并显示进度/日志/输出文件。

> **执行服务（后续）**：当前是进程内隔离（错误隔离）。若要隔离原生代码崩溃，可把 `ExecutionEngine.run` 迁移到 XPC Service——`ModuleContext`/`ActionInvocation` 均为值类型，已为跨进程传递做好准备。

### 4. 功能模块（`Sources/Modules/*`）
每个模块一个 SPM target，拥有自己的逻辑、设置定义、资源与测试。实验性模块（侧边栏）额外做到：默认关闭、运行时 `dlsym` 解析 API（API 被移除时报告不可用而不是编译失败或崩溃）、写入后回读校验、写入前自动备份。

## 两种扩展方式

| | 原生模块 | 脚本功能包 |
|---|---|---|
| 适用 | 需要 Swift/AppKit、系统权限、复杂 UI | 轻量自动化：Shell/Python 脚本 |
| 接入 | 新建 SPM target + 在 `BuiltinModules` 加一行，重新编译 | 导入含 `finderplus-package.json` 的文件夹，无需编译 |
| UI | Schema 表单 + 可选自定义 SwiftUI 视图/窗口 | Schema 表单 |
| 安全 | 随应用签名发布 | 导入时审核，按内容哈希信任；不能声明为原生、不能默认启用 |

macOS 不允许（也不应该）运行时加载任意第三方原生代码，因此“动态加载”只针对脚本功能包。

## 数据位置

| 位置 | 内容 |
|---|---|
| App Group 容器 `…/Group Containers/<TeamID>.io.github.finderplus/FinderPlus/` | `configuration.json`、`menu-snapshot.json`、`Inbox/` |
| `~/Library/Application Support/FinderPlus/` | `Templates/`、`IconPacks/`、`Packages/`、`Runtimes/`、`ModuleData/`、`Backups/`、`task-history.json` |

配置有 `schemaVersion`，`ConfigurationStore.migrate` 负责升级；迁移和导入前自动备份旧文件，无法解析的文件会备份后回退到默认值，不会丢失。

## 已知限制
- Finder Sync 只能向 Finder 右键菜单添加项目，不能修改系统菜单项。
- 监控根目录 `/` 与 `/Volumes`；部分系统位置（如 iCloud Drive 的某些视图）Finder 可能不调用扩展。
- “创建后进入重命名”通过辅助功能模拟回车，需要用户授权；未授权时退化为选中文件。
- Terminal.app 不支持“仅输入不执行”，此模式下命令会复制到剪贴板。
