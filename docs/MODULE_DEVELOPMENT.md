# 开发原生模块

新增一个原生模块只涉及模块自身的文件，外加两处登记：

1. 新建 `Packages/FinderPlusKit/Sources/Modules/<Name>/`；
2. 在 `Package.swift` 的 `builtinModules` 数组中加入 `"<Name>"`（target 名为 `FP<Name>`）；
3. 在 `Sources/FinderPlusBuiltinModules/BuiltinModules.swift` 中 `import FP<Name>` 并加入 `<Name>Module()`。

主程序界面、Finder 扩展、其他模块都无需修改。

## 最小示例

```swift
import FinderPlusCore
import Foundation

public final class HelloModule: FinderPlusModule {
    public init() {}

    public let manifest = ModuleManifest(
        id: "com.example.hello",
        name: LocalizedText(en: "Hello", zhHans: "你好"),
        summary: LocalizedText(en: "Greets the selected files."),
        version: "1.0.0",
        author: "You",
        icon: "hand.wave",
        category: .utility,
        actions: [
            ActionDescriptor(id: "greet", title: LocalizedText(en: "Say Hello", zhHans: "打招呼"),
                             icon: "hand.wave", group: .other, rule: .anyItems)
        ],
        settings: SettingsSchema(sections: [
            SettingsSection(id: "main", title: "Hello", fields: [
                .text("greeting", LocalizedText(en: "Greeting", zhHans: "问候语"), default: "Hello")
            ])
        ])
    )

    public func perform(_ invocation: ActionInvocation, context: ModuleContext) async throws -> ActionOutcome {
        let names = invocation.selection.targetURLs.map(\.lastPathComponent).joined(separator: ", ")
        return .message("\(invocation.settings.string("greeting")), \(names)!")
    }
}
```

## 关键约定

- **ID**：反向域名，全局唯一，发布后不要修改（配置、菜单自定义都以它为键）。
- **动作 ID**：模块内唯一；根据设置生成的动作在 ID 中编码变体（如 `new.md`），并通过 `parameters` 传参。
- **动态菜单**：重写 `menuActions(settings:)`。它在主程序生成快照时调用，必须快速且无副作用。
- **执行方式**：
  - `.immediate` 快速操作（复制、打开），仅失败时出现在任务中心；
  - `.task` 可能耗时，显示进度、日志、输出，可取消（循环中调用 `context.checkCancellation()`）；
  - `.interactive(route:)` 打开模块提供的窗口（实现 `ModuleInteractiveUIProviding`）。
  - `presentation: .hostOnly` 的动作不会出现在 Finder 菜单，可作为依赖页的“一键修复”（`DependencyStatus.fixActionID`）。
- **危险操作**：设置 `requiresConfirmation` 与 `confirmationMessage`；修改用户数据前自行备份。
- **系统交互**：通过 `context.system`（剪贴板、打开、终端、提示、通知），便于测试时注入 mock。
- **外部命令**：使用 `context.processes.run(executable, arguments:)`；需要在终端里显示的命令用 `ShellQuoting` 构造。
- **错误**：抛出 `ModuleError` 或任意 `LocalizedError`，消息会显示在任务中心与通知中。
- **本地化**：所有用户可见文字使用 `LocalizedText(en:zhHans:ko:)`。
- **自定义 UI**：依赖 `FinderPlusUI`，实现 `ModuleSettingsViewProviding`（设置页附加/替换视图）、`ModuleInteractiveUIProviding`（交互窗口）或 `ModuleLibraryProviding`（出现在“模板管理/图标管理”页）。
- **私有 API**：设置 `stability: .experimental`；用 `dlsym` 等方式在运行时解析，做兼容性检测、写后校验与备份，且不要被其他模块依赖。

## 设置 Schema 字段类型

`toggle`、`text`、`multilineText`、`integer`、`number`、`choice`、`multiChoice`、`path`（file/folder/application）、`stringList`、`objectList`（每项由 `itemFields` 描述）。`visibleWhen` 可按其他字段的值显示/隐藏。

## 测试

在 `Tests/FinderPlusModuleTests` 中添加测试；`TestSupport.swift` 提供 `MockSystemServices` 与 `makeContext`。运行 `make test`。
