import FinderPlusCore

/// Host UI strings. FinderPlus localizes with ``LocalizedText`` everywhere (host and modules alike)
/// so that the in-app language setting applies immediately and modules ship their own translations.
enum HostStrings {
    private static func t(_ en: String, _ zh: String, _ ko: String) -> LocalizedText {
        LocalizedText(en: en, zhHans: zh, ko: ko)
    }

    // App & navigation
    static let settingsMenu = t("Settings…", "设置…", "설정…")
    static let showMainWindow = t("FinderPlus Window", "FinderPlus 主窗口", "FinderPlus 창")
    static let overview = t("Overview", "总览", "개요")
    static let moduleCenter = t("Modules", "模块中心", "모듈")
    static let menuManager = t("Context Menu", "右键菜单管理", "컨텍스트 메뉴")
    static let templates = t("Templates", "模板管理", "템플릿")
    static let icons = t("Icons", "图标管理", "아이콘")
    static let dependencies = t("Dependencies", "依赖管理", "종속성")
    static let taskCenter = t("Tasks", "任务中心", "작업")
    static let general = t("General", "通用设置", "일반")
    static let moduleSettings = t("Module Settings", "模块设置", "모듈 설정")
    static let error = t("Something went wrong", "出现问题", "문제가 발생했습니다")
    static let ok = t("OK", "好", "확인")
    static let cancel = t("Cancel", "取消", "취소")
    static let moduleMissing = t("Module not found", "找不到模块", "모듈을 찾을 수 없음")

    // Overview
    static let tagline = t("A modular, local-first toolbox for Finder.", "模块化、本地优先的 Finder 增强平台。", "모듈식, 로컬 우선 Finder 도구 상자.")
    static let enabledModules = t("Enabled modules", "已启用模块", "활성 모듈")
    static let menuItems = t("Menu items", "菜单项", "메뉴 항목")
    static let runningTasks = t("Running tasks", "运行中的任务", "실행 중인 작업")
    static let recentTasks = t("Recent tasks", "最近任务", "최근 작업")
    static let showAll = t("Show all", "查看全部", "모두 보기")
    static let noTasksYet = t("No tasks yet. Right-click in Finder and choose FinderPlus.", "暂无任务。在 Finder 中右键并选择 FinderPlus 即可开始。",
                              "아직 작업이 없습니다. Finder에서 오른쪽 클릭 후 FinderPlus를 선택하세요.")
    static let extensionOn = t("Finder extension is enabled", "Finder 扩展已启用", "Finder 확장이 활성화됨")
    static let extensionOff = t("Finder extension is not enabled", "Finder 扩展未启用", "Finder 확장이 비활성화됨")
    static let extensionHelp = t("Turn on the FinderPlus Finder extension in System Settings: Privacy & Security › Extensions (macOS 14) or General › Login Items & Extensions (macOS 15 and later).",
                                 "请在“系统设置”中开启 FinderPlus 的 Finder 扩展：macOS 14 位于“隐私与安全性 › 扩展”，macOS 15 及以后位于“通用 › 登录项与扩展”。",
                                 "시스템 설정에서 FinderPlus Finder 확장을 켜세요: macOS 14는 개인정보 보호 및 보안 › 확장 프로그램, macOS 15 이상은 일반 › 로그인 항목 및 확장 프로그램.")
    static let openExtensionSettings = t("Open Extension Settings", "打开扩展设置", "확장 설정 열기")

    // Module center
    static let category = t("Category", "类别", "범주")
    static let all = t("All", "全部", "전체")
    static let loadProblems = t("Modules that could not be loaded", "无法加载的模块", "불러올 수 없는 모듈")
    static let importPackage = t("Import Script Package…", "导入脚本功能包…", "스크립트 패키지 가져오기…")
    static let importPackageHelp = t("Add a folder containing finderplus-package.json", "选择包含 finderplus-package.json 的文件夹",
                                     "finderplus-package.json이 있는 폴더 추가")
    static let openPackagesFolder = t("Packages Folder", "功能包文件夹", "패키지 폴더")
    static let scriptPackage = t("Script package", "脚本功能包", "스크립트 패키지")
    static let builtIn = t("Built-in", "内置", "내장")
    static let experimental = t("Experimental", "实验性", "실험적")
    static let untrusted = t("Needs review", "待审核", "검토 필요")
    static let missingDependency = t("Missing dependency", "缺少依赖", "종속성 없음")
    static let settings = t("Settings", "设置", "설정")
    static let review = t("Review…", "审核…", "검토…")
    static let update = t("Update…", "更新…", "업데이트…")
    static let uninstall = t("Uninstall…", "卸载…", "제거…")
    static let enable = t("Enable", "启用", "활성화")
    static let enableExperimentalTitle = t("Enable an experimental module?", "启用实验性模块？", "실험적 모듈을 활성화할까요?")
    static let enableExperimentalMessage = t(
        "This module relies on undocumented macOS behavior. FinderPlus backs up affected data and isolates the module, but it may stop working after a macOS update.",
        "该模块依赖未公开的 macOS 行为。FinderPlus 会备份相关数据并隔离该模块，但系统更新后它可能失效。",
        "이 모듈은 공개되지 않은 macOS 동작에 의존합니다. 데이터를 백업하고 모듈을 격리하지만 macOS 업데이트 후 작동하지 않을 수 있습니다.")
    static let uninstallTitle = t("Uninstall this package?", "卸载该功能包？", "이 패키지를 제거할까요?")
    static let uninstallKeepSettings = t("Uninstall, keep settings", "卸载并保留配置", "제거하고 설정 유지")
    static let uninstallRemoveAll = t("Uninstall and remove settings & data", "卸载并删除配置与数据", "제거하고 설정 및 데이터 삭제")
    static let reviewWarning = t("Only install packages from sources you trust. Scripts run with your user permissions when you choose their menu items.",
                                 "请只安装来源可信的功能包。选择其菜单项时，脚本将以你的用户权限运行。",
                                 "신뢰할 수 있는 출처의 패키지만 설치하세요. 메뉴 항목을 선택하면 스크립트가 사용자 권한으로 실행됩니다.")
    static let source = t("Source", "来源", "출처")
    static let folder = t("Folder", "文件夹", "폴더")
    static let files = t("Files", "文件数", "파일")
    static let permissions = t("Permissions", "权限", "권한")
    static let commands = t("Commands", "执行命令", "명령")
    static let enableAfterInstall = t("Enable after installing", "安装后启用", "설치 후 활성화")
    static let showFiles = t("Show Files", "显示文件", "파일 보기")
    static let trustAndInstall = t("Trust and Install", "信任并安装", "신뢰하고 설치")

    // Module settings
    static let enabled = t("Enabled", "已启用", "활성화됨")
    static let disabled = t("Disabled", "未启用", "비활성화됨")
    static let experimentalNotice = t("Experimental module — isolated from the rest of FinderPlus and backed up before every change.",
                                      "实验性模块——与 FinderPlus 其他部分隔离，每次修改前自动备份。",
                                      "실험적 모듈 — 다른 부분과 격리되며 변경 전마다 백업됩니다.")
    static let customizeInMenuManager = t("Rename, reorder or hide in Context Menu settings", "在“右键菜单管理”中重命名、排序或隐藏",
                                          "컨텍스트 메뉴 설정에서 이름 변경, 정렬, 숨기기")
    static let about = t("About", "关于", "정보")
    static let identifier = t("Identifier", "标识符", "식별자")
    static let version = t("Version", "版本", "버전")
    static let kind = t("Type", "类型", "유형")
    static let resetSettings = t("Reset to Defaults", "恢复默认设置", "기본값으로 재설정")

    // Menu manager
    static let resetMenu = t("Reset Menu", "重置菜单", "메뉴 재설정")
    static let menuManagerHelp = t("Rename items, change their group and order, or hide them. Changes reach Finder immediately.",
                                   "可重命名菜单项、调整分组与顺序或隐藏。修改会立即同步到 Finder。",
                                   "항목 이름 변경, 그룹 및 순서 변경, 숨기기가 가능합니다. 변경 사항은 즉시 Finder에 반영됩니다.")
    static let menuAppearanceSettings = t("Menu title, layout and icons…", "菜单名称、布局与图标…", "메뉴 이름, 레이아웃, 아이콘…")
    static let livePreview = t("Live preview", "实时预览", "실시간 미리 보기")
    static let selection = t("Selection", "选中对象", "선택 항목")
    static let inline = t("Inline", "平铺", "인라인")
    static let submenu = t("Submenu", "子菜单", "하위 메뉴")
    static let orderHelp = t("Lower numbers appear first", "数字越小越靠前", "숫자가 작을수록 먼저 표시")
    static let showGroup = t("Show this group", "显示该分组", "이 그룹 표시")
    static let previewEmpty = t("No FinderPlus items for this selection.", "该选中对象没有 FinderPlus 菜单项。", "이 선택 항목에는 FinderPlus 항목이 없습니다.")
    static let samplePython = t("Python file", "Python 文件", "Python 파일")
    static let sampleMarkdown = t("Markdown file", "Markdown 文件", "Markdown 파일")
    static let sampleImage = t("Image", "图片", "이미지")
    static let sampleDocument = t("Word document", "Word 文档", "Word 문서")
    static let sampleFolder = t("Folder", "文件夹", "폴더")
    static let sampleBackground = t("Folder background", "文件夹空白处", "폴더 배경")
    static let sampleMultiple = t("Several images", "多张图片", "여러 이미지")
    static let ruleBackground = t("folder background", "文件夹空白处", "폴더 배경")
    static let ruleFolders = t("folders", "文件夹", "폴더")
    static let ruleAnyItem = t("any item", "任意项目", "모든 항목")

    // Library, dependencies, tasks
    static let noLibraryProviders = t("No enabled module provides this library.", "没有已启用的模块提供此内容。", "이 라이브러리를 제공하는 활성 모듈이 없습니다.")
    static let systemIntegration = t("System integration", "系统集成", "시스템 통합")
    static let finderExtension = t("Finder extension", "Finder 扩展", "Finder 확장")
    static let openSettings = t("Open Settings", "打开设置", "설정 열기")
    static let accessibility = t("Accessibility (optional)", "辅助功能（可选）", "손쉬운 사용(선택)")
    static let accessibilityHelp = t("Only needed to start renaming automatically after creating a file.", "仅在新建文件后自动进入重命名时需要。",
                                     "파일을 만든 후 자동으로 이름 변경을 시작할 때만 필요합니다.")
    static let optional = t("Optional", "可选", "선택")
    static let install = t("Install", "安装", "설치")
    static let refresh = t("Refresh", "刷新", "새로 고침")
    static let showQuickActions = t("Show quick actions", "显示快速操作", "빠른 작업 표시")
    static let clearFinished = t("Clear Finished", "清除已完成", "완료 항목 지우기")
    static let showInFinder = t("Show in Finder", "在 Finder 中显示", "Finder에서 보기")
    static let log = t("Log", "日志", "로그")

    // General
    static let startup = t("Startup", "启动", "시작")
    static let launchAtLogin = t("Open FinderPlus at login", "登录时打开 FinderPlus", "로그인 시 FinderPlus 열기")
    static let keepRunning = t("Keep running in the background after closing the window", "关闭窗口后保持后台运行", "창을 닫은 후에도 백그라운드에서 실행")
    static let keepRunningHelp = t("Finder menu actions start faster when FinderPlus is already running. It uses no CPU while idle.",
                                   "FinderPlus 保持运行时右键操作响应更快，空闲时不占用 CPU。",
                                   "FinderPlus가 실행 중이면 메뉴 작업이 더 빨리 시작됩니다. 유휴 시 CPU를 사용하지 않습니다.")
    static let safety = t("Safety & notifications", "安全与通知", "안전 및 알림")
    static let confirmDangerous = t("Ask before actions that modify system data", "执行修改系统数据的操作前先确认", "시스템 데이터를 수정하기 전에 확인")
    static let notifyOnCompletion = t("Notify when background tasks finish", "后台任务完成时通知", "백그라운드 작업 완료 시 알림")
    static let taskHistoryLimit = t("Task history size", "任务记录数量", "작업 기록 크기")
    static let appearanceAndLanguage = t("Appearance & language", "外观与语言", "모양 및 언어")
    static let openAppearanceSettings = t("Language, theme and menu style…", "语言、主题与菜单样式…", "언어, 테마, 메뉴 스타일…")
    static let status = t("Status", "状态", "상태")
    static let backupAndMigration = t("Backup & migration", "备份与迁移", "백업 및 마이그레이션")
    static let exportConfiguration = t("Export Configuration…", "导出配置…", "설정 내보내기…")
    static let importConfiguration = t("Import Configuration…", "导入配置…", "설정 가져오기…")
    static let migrationHelp = t("Moves module settings, menu customizations and trusted packages to another Mac. Script package files are copied separately.",
                                 "可将模块设置、菜单自定义与已信任的功能包迁移到另一台 Mac。脚本功能包文件需单独复制。",
                                 "모듈 설정, 메뉴 사용자 지정, 신뢰한 패키지를 다른 Mac으로 옮깁니다. 패키지 파일은 별도로 복사하세요.")
    static let openDataFolder = t("Open Data Folder", "打开数据文件夹", "데이터 폴더 열기")
    static let openSharedFolder = t("Open Shared Folder", "打开共享文件夹", "공유 폴더 열기")
    static let architecture = t("Architecture", "架构", "아키텍처")
    static let aboutText = t("Free and open source. No account, no tracking, files are processed locally unless a module says otherwise.",
                             "免费开源，无需账户，不做追踪；除非模块特别说明，文件均在本地处理。",
                             "무료 오픈 소스. 계정과 추적이 없으며, 모듈이 별도로 밝히지 않는 한 파일은 로컬에서 처리됩니다.")
}
