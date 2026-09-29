# AGENTS.md

## 项目边界

LinkUp 是基于深澜 Srun 协议的 Android 校园网自动认证客户端，并包含 Windows 桌面客户端。除 Windows 外，其他平台目录是 Flutter 模板产物，当前没有适配承诺；除非任务明确要求，不修改或验证这些平台。

核心行为：检测 Wi-Fi 与在线状态、按需探测 ACID、完成认证、持续监控并断线重连。

## 变更路由

- **页面与组件**：入口在 `lib/main.dart`；导航状态由 `lib/navigation/MainNavigation.dart` 编排；页面和组件分别位于 `lib/page/`、`lib/components/`。
- **认证与协议**：认证周期由 `lib/utils/AuthenticationCoordinator.dart` 独占（单飞、调度、网络世代、状态流），改认证行为从它读起；协议实现在 `lib/utils/SrunClient.dart`、`SrunLogin.dart`、`SrunEncrypt.dart`、`AcidDetector.dart`。修改接口、加密、JSONP、ACID、重定向或错误码前，先读 `docs/深澜认证协议技术文档.md`；该文件是协议事实的唯一来源。决策背景见 `docs/adr/0002--centralize-authentication-attempt-authority.md` 与 `docs/adr/0003--coordinator-owns-monitoring-schedule.md`。
- **本地数据与更新**：`ConfigUtil.dart` 保存认证配置，`SystemSettingsUtil.dart` 保存系统开关，`LogUtil.dart` 管理日志，`UpdateUtil.dart` 检查和安装更新。
- **Android 原生**：入口与开机自启位于 `android/app/src/main/kotlin/com/mel0ny/linkup/`；Dart 与原生层通过 `com.mel0ny.linkup/system` 对应的 `MethodChannel` 方法通道通信。后台认证运行时由 `AuthRuntimeService` 承载，它用独立的 `FlutterEngine` 运行 `lib/authRuntimeMain.dart`，并通过 `com.mel0ny.linkup/authRuntime` 与 `com.mel0ny.linkup/authUi` 两个通道连接 Dart。命令名与通道名的唯一来源是同目录的 `AuthRuntimeBridge.kt`；后台开关与开机门读取 Dart 写入 `FlutterSharedPreferences` 的键（`shared_preferences` 加的 `flutter.` 前缀），由 `BackgroundRuntimeSettings.kt` 封装。
- **Windows 客户端与认证运行时**：入口在 `lib/main.dart`；主界面由 `lib/page/WindowsTrayApp.dart`、`lib/page/WindowsHome.dart` 编排，托盘浮层由 `windows/runner/tray_popup_window.cpp` 和 `lib/page/WindowsPopupApp.dart` 承载，共用 `WindowsTrayApp` 投影的状态；界面命令经 `lib/utils/WindowsAuthRuntime.dart`、`lib/utils/AuthRuntimeController.dart` 转交给 `lib/utils/AuthenticationCoordinator.dart`。修改 Windows 托盘、设备会话或认证操作时，沿这条调用链定位行为；窗口所有权见 `docs/adr/0012--separate-windows-tray-popup-window.md`。
- **Windows 登录自启与安装器**：开关在 `lib/page/WindowsHome.dart`、`lib/utils/WindowsAutoStart.dart`；`windows/runner/main.cpp` 解析 `--background`，`windows/runner/flutter_window.cpp` 负责 `windowsStartup`/HKCU `Run` 桥接与后台首帧策略；`windows/installer/LinkUp.iss` 清理卸载时的启动项。修改这条链路时查 `test/windows_installer_contract_test.dart`。
- **工具链与依赖**：以 `pubspec.yaml`、`pubspec.lock`、`android/` 和 `.github/workflows/` 为准；本文件不重复记录版本号。本机 SDK 可能与 `environment.flutter` 不一致，先做变更流程第 0 步。
- **用户文档**：`README.md` 面向使用者和贡献者；协议细节不要重新复制到 README。

## 不可破坏约束

- 深澜协议字符串和密码按 Latin-1 字节处理，不使用 UTF-8 替代。
- 认证门户响应通常是 JSONP；必须先可靠提取回调函数中的 JSON，再反序列化。
- `srun_portal` 返回 `error == "ok"` 不能单独证明在线；登录后必须再次调用 `rad_user_info` 确认。
- ACID 探测依赖手动跟随重定向并检查每一跳；恢复自动重定向会丢失门户 URL、表单或 ACID。
- 认证请求使用 `http`；`dio` 仅用于 APK 下载。保持这一职责边界。
- 用户名、密码、挑战值、完整认证参数和下载令牌不得写入日志、文档或测试夹具。
- Android 认证运行时只有一份 Dart 实现，由后台前台服务独占。Activity 的 `FlutterEngine` 不得创建协调器或认证周期定时器，Kotlin 不得复制 Srun 协议逻辑。详见 `docs/adr/0004--foreground-service-owns-auth-runtime.md`。
- `lib/utils/RadUserInfo.g.dart` 是生成文件；模型注解变化后用 `build_runner` 重新生成，不手改生成代码。
- Gradle 与 CI 使用 JDK 21；Android 源码和 Kotlin 字节码目标保持 Java 17，因为当前 Android API 级别只保证到 Java 17 语言特性。
- 玻璃表面统一走 `lightweight_liquid_glass` 的 `GlassSurface`（Git 依赖，固定在经审查的提交）：导航保留实时模糊，状态卡关闭模糊改用半透明渐变。除非任务明确要求，不替换该依赖或重做玻璃 UI。
- 保留现有大驼峰式文件名和分析器 `info` 级遗留问题；不做与任务无关的全仓重命名、格式化或静态检查清理。

## 变更流程

0. **工具链预检**：比对 `flutter --version` 与 `pubspec.yaml` 的 `environment.flutter`。不一致时用 `tool/flutter_sdk.sh` 取仓库声明的版本（命中缓存直接用，否则下载到缓存目录），后续所有 `flutter`/`dart` 命令都经它执行，保持共享 SDK 的 checkout 原样。完成标准：`tool/flutter_sdk.sh flutter pub get` 能成功。
1. **定位行为**：先沿上述入口读取相关实现和调用方，并记录必须保持的协议或 UI 行为。完成标准：每个行为改动都能指向明确调用链。
2. **实施最小修改**：沿用周边代码风格，只修改完成当前任务所需的文件。完成标准：差异中没有顺手重构、依赖漂移或无关格式变化。
3. **生成派生文件**：修改 JSON 模型或生成器依赖后运行 `dart run build_runner build`；修改 `pubspec.yaml`/`pubspec.lock` 后重跑 `flutter pub get` 并纳入生成的插件注册文件。完成标准：命令成功，生成文件已纳入差异且不含陈旧输出。
4. **验证 Dart**：格式化本次触及的 Dart 文件，再运行 `flutter analyze --no-fatal-infos` 和 `flutter test`。`ci.yml` 的格式门是全仓 `dart format --output=none --set-exit-if-changed .`，新引入的排版漂移会在 PR 上直接翻红；只把仓库自己的 `info` 债务算作非阻塞项。完成标准：没有错误或警告，测试全部通过。
5. **验证 Android**：涉及依赖、Gradle、插件、Manifest 或 Kotlin 时运行 `flutter build apk --debug`；涉及发布配置或原生行为时再运行 `flutter build apk --release`。完成标准：对应 APK 成功生成。构建只证明原生代码可编译，接线行为另有门槛，见交付文档中的评审门槛。
6. **交付**：提交边界、推送、PR 正文与评审门槛按 [delivery.md](docs/agents/delivery.md) 执行。完成标准：PR 正文五节齐全，该跑的检查已跑。

最终运行 `git diff --check`，并用 `rg` 确认文档和配置没有残留的旧命令、旧渠道或已删除文件引用。

## 智能体技能

### 问题跟踪

通过 `gh` 管理 GitHub 问题，约定见 `docs/agents/issue-tracker.md`。

### 分类标签

每个问题使用一个 `bug` 或 `enhancement` 分类标签，以及一个规范状态标签。约定见 `docs/agents/triage-labels.md`。

### 领域文档

本仓库按单一上下文维护领域文档，约定见 `docs/agents/domain.md`。

### 交付

PR 正文结构、评审门槛、问题关联，以及发布 tag 前手写中文 Release 说明的流程见 `docs/agents/delivery.md`。改动 `android/` 下的 Manifest、Kotlin 或方法通道接线时必读。
