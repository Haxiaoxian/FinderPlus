# 脚本功能包

脚本功能包让你无需重新编译 FinderPlus 就能添加功能。一个功能包就是一个文件夹：

```
my-package/
  finderplus-package.json
  scripts/run.sh
  （其他资源）
```

在“模块中心 › 导入脚本功能包…”中选择该文件夹。FinderPlus 会显示来源、文件数、内容哈希、权限以及每个动作将执行的完整命令；确认“信任并安装”后，文件夹被复制到 `~/Library/Application Support/FinderPlus/Packages/`。

## 安全模型

- 功能包始终是 `scriptPackage` 类型，不能声明为原生，也不能默认启用。
- 信任绑定到全部文件的 SHA-256。任何文件被修改后，功能包会从菜单消失，直到重新审核。
- 脚本路径必须位于包内（禁止 `..` 越界）。
- 参数以数组形式直接传给进程，不经过 Shell 解析；选中的路径作为独立参数传入。
- 脚本以当前用户权限运行，**只安装可信来源的功能包**。

## `finderplus-package.json`

模块清单字段与原生模块相同（见 `ModuleManifest`），每个动作额外带一个 `run`：

```json
{
  "formatVersion": 1,
  "id": "com.example.hello",
  "name": { "en": "Hello", "zh-Hans": "你好" },
  "summary": "Says hello",
  "version": "1.0.0",
  "author": "You",
  "icon": "hand.wave",
  "category": "utility",
  "permissions": ["readSelection", "runProcesses"],
  "settings": {
    "sections": [{
      "id": "main", "title": "Main",
      "fields": [{ "key": "greeting", "kind": "text", "title": "Greeting", "default": "Hello" }]
    }]
  },
  "actions": [{
    "id": "greet",
    "title": { "en": "Say Hello", "zh-Hans": "打招呼" },
    "icon": "hand.wave",
    "group": "other",
    "rule": { "contexts": ["items"], "extensions": ["txt", "md"], "maxSelection": 20 },
    "run": {
      "interpreter": "/bin/sh",
      "script": "scripts/run.sh",
      "arguments": ["--greeting={setting:greeting}", "{files}"],
      "workingDirectory": "container",
      "output": "notification",
      "timeout": 60
    }
  }]
}
```

### `run` 字段

| 字段 | 说明 |
|---|---|
| `interpreter` | 绝对路径或命令名（`python3`、`zsh`），在 PATH 及 Homebrew/Conda 等常见位置查找；省略则直接执行脚本（需可执行权限） |
| `script` | 包内相对路径 |
| `arguments` | 参数数组，支持占位符（见下） |
| `workingDirectory` | `container`（当前文件夹）或 `package`（包目录） |
| `output` | `none`、`notification`（标准输出最后一行作为结果消息）、`clipboard`（复制标准输出） |
| `timeout` | 秒，默认 300 |

### 占位符

| 占位符 | 展开为 |
|---|---|
| `{files}` | 所有选中项路径，每个一个参数（必须单独作为一个参数） |
| `{file}` | 第一个选中项 |
| `{folder}` | 当前文件夹 |
| `{package}` | 功能包目录 |
| `{setting:key}` | 设置值 |

### 环境变量

`FINDERPLUS_SELECTION`（换行分隔）、`FINDERPLUS_CONTAINER`、`FINDERPLUS_CONTEXT`（`items`/`container`）、`FINDERPLUS_PACKAGE_DIR`，以及每个设置 `FINDERPLUS_SETTING_<KEY>`。

### 菜单规则 `rule`

`contexts`（`items`、`container`）、`minSelection`、`maxSelection`、`itemKinds`（`file`、`folder`、`package`）、`extensions`、`typeIdentifiers`（UTType，如 `public.image`）、`requireAllItemsMatch`。扩展名与类型过滤只作用于文件；`itemKinds` 包含 `folder` 时文件夹总是匹配。

### 分组 `group`

`create`、`template`、`run`、`open`、`convert`、`compress`、`folder`、`sidebar`、`path`、`other`，或自定义分组名。用户可在“右键菜单管理”中重命名、移动、排序或隐藏。

## 示例

`Examples/ScriptPackages/` 中有两个可直接导入的示例：`checksum`（复制 SHA-256/MD5）与 `word-count`（统计字数，支持中日韩文字）。
