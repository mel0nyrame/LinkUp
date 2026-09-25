<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="LinkUp：自动完成深澜校园网认证、断网重连与在线状态监控">
</p>

<p align="center">
  <a href="https://github.com/mel0nyrame/LinkUp/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/mel0nyrame/LinkUp?style=flat-square&color=247cff"></a>
  <img alt="Platform: Android" src="https://img.shields.io/badge/platform-Android-34C759?style=flat-square">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-6f7f8f?style=flat-square"></a>
</p>

LinkUp 是一个面向 **深澜（Srun）校园网**的 Android 自动认证客户端。配置一次账号后，它会检测网络状态、自动探测 ACID、完成登录，并在断网时尝试重新连接。

> [!NOTE]
> LinkUp 是基于公开协议实现的第三方客户端，与深澜官方无关。

## 界面预览

<p align="center">
  <a href="./assets/main_screen.jpg"><img src="./assets/main_screen.jpg" width="31%" alt="LinkUp 概况页，展示网络状态、在线设备和网络信息"></a>&nbsp;
  <a href="./assets/setting_screen.jpg"><img src="./assets/setting_screen.jpg" width="31%" alt="LinkUp 设置页，展示账号信息和后台运行选项"></a>&nbsp;
  <a href="./assets/setting_screen_2.jpg"><img src="./assets/setting_screen_2.jpg" width="31%" alt="LinkUp 网络配置页，展示 ACID 自动探测和认证服务器设置"></a>
</p>

<p align="center"><sub>概况与网络状态 · 账号与系统选项 · ACID 与认证服务器配置</sub></p>

## 它解决什么

- **自动认证** — 连接校园 Wi‑Fi 后自动完成深澜登录流程。
- **断网重连** — 由常驻通知的前台服务周期检测网络状态，离线时自动尝试恢复连接。
- **自动探测 ACID** — 从 Portal 重定向链和登录页面识别接入点，无需逐个试值。
- **状态一目了然** — 查看 IP、流量、在线时长和在线设备。
- **适合后台运行** — 支持前台服务保活、开机自启与错误日志，便于长期使用和排障。

<p align="center">
  <img src="./assets/readme/workflow.svg" width="100%" alt="LinkUp 从检测 Wi-Fi、探测 ACID、获取 Challenge、加密认证到持续监控和重连的流程">
</p>

## 开始使用

### 安装 APK

1. 前往 [Releases](https://github.com/mel0nyrame/LinkUp/releases) 下载最新 APK。
2. 在 Android 设备上允许安装来自此来源的应用并完成安装。
3. 首次启动时填写学号或工号、密码；ACID 建议保持“自动获取”。

进入概况页后，LinkUp 会自动检测并认证。下拉页面可立即触发一次手动刷新。

### 从源码构建

需要 Flutter `3.47.5`（stable，内置 Dart `3.13.4`）、JDK 21 和 Android SDK 36。具体版本以 `pubspec.yaml` 与 `android/` 为准。

```bash
git clone https://github.com/mel0nyrame/LinkUp.git
cd LinkUp
flutter pub get
flutter build apk --release
```

构建产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 工作原理

<p align="center">
  <img src="./assets/readme/auth-loop.svg" width="100%" alt="LinkUp 深澜认证闭环：检测 Wi-Fi 和在线状态，离线时探测 ACID、获取 Challenge、生成加密参数并登录，二次确认在线后持续监控，断线则重新尝试">
</p>

1. **登录前判断**：检测 Wi‑Fi、读取配置，并通过 `rad_user_info` 查询当前状态；已经在线则直接进入监控。
2. **离线时认证**：自动探测 ACID、获取 Challenge，在本地通过 HMAC-MD5、XXTEA、自定义 Base64 与 SHA-1 生成认证参数，再提交登录。
3. **登录后确认**：再次查询 `rad_user_info`，而不是仅依赖 Portal 的成功响应；监控发现断线后重新进入认证流程。

## 平台与限制

| 平台 | 支持情况 | 说明 |
| --- | --- | --- |
| Android | ✅ 主要支持平台 | 包含前台服务保活与开机自启 |
| iOS | ⚠️ 尚未适配 | 暂不提供可用版本 |
| Windows / macOS / Linux | ⚠️ 尚未适配 | 暂不提供可用版本 |
| Web | ❌ 不支持 | 浏览器网络权限不满足认证需求 |

## 后台运行

“保留后台运行”由一个 Android 前台服务承载。该服务创建独立的运行时执行认证流程，并发布一条低重要性的常驻通知说明当前认证状态。

- 开启后，关闭应用界面、锁屏或切到其他应用都不会中断自动重连；常驻通知会显示“正在认证”“已连接校园网”“WiFi 未连接”等状态。
- 关闭后，服务停止、认证调度取消、网络监听注销、运行时资源释放，LinkUp 只在应用打开时认证。
- 校园 Wi-Fi 断开时服务保持运行并显示“WiFi 未连接”，同时作废当前网络的 ACID；Wi-Fi 恢复后立即重新认证，不需要等待下一个检查周期。
- Android 13 及更高版本在首次开启时会申请通知权限。拒绝权限不会导致崩溃，但系统将不再展示常驻通知，也无法在通知栏看到认证状态。
- 服务被系统正常回收后会按 sticky 语义重建。但如果你在系统应用信息中对 LinkUp 执行**强行停止**，撤销了通知或自启授权，或厂商 ROM 强制禁用了后台活动，Android 不会为它恢复服务；这些情况需要你重新打开 LinkUp 并确认系统授权，LinkUp 不会自动绕开它们。

“开机自启”是“保留后台运行”的下游开关。只有已保存账号配置，并且“保留后台运行”和“开机自启”同时开启时，设备重启后才会自动恢复认证；任一条件不满足都不会启动，LinkUp 也不会为了开机认证而拉起界面。开机时通常还没有网络，服务会等待第一个可用网络后再认证。

若自动重连没有按预期工作，请确认：

1. 在 LinkUp 的“系统设置”中开启保留后台运行；
2. 允许 LinkUp 发送通知；
3. 将 LinkUp 加入系统电池优化白名单；
4. 在系统设置中允许自启动（部分小米、华为、OPPO、vivo 设备需要额外授权）。

## 常见问题

<details>
<summary><strong>提示“WiFi 未开启”</strong></summary>

请确认设备已连接需要认证的校园 Wi‑Fi。LinkUp 不会通过移动数据执行校园网认证。
</details>

<details>
<summary><strong>登录失败并提示 ACID 错误</strong></summary>

优先将 ACID 模式切换为“自动获取”。若当前网络无法完成自动探测，再向学校网络中心确认接入点 ID 后手动填写。
</details>

<details>
<summary><strong>应用切到后台后不再自动重连</strong></summary>

确认已开启“保留后台运行”并允许通知权限，再检查系统的电池优化、自启动和后台活动权限。不同厂商的限制策略可能不同；如果之前对 LinkUp 执行过强行停止，需要重新打开应用。
</details>

<details>
<summary><strong>如何查看错误日志</strong></summary>

可在应用的日志卡片中查看。Android 上日志文件位于应用私有目录 `app_flutter/error.log`，通常无法由普通文件管理器直接访问。
</details>

## 开发

```bash
flutter analyze --no-fatal-infos  # 静态分析
flutter test                      # 运行测试
```

当 `RadUserInfo` 的 JSON 模型发生变化时，重新生成序列化代码：

```bash
dart run build_runner build
```

协议字段、加密链路、JSONP、ACID 探测与错误码说明见 [深澜认证协议技术文档](./docs/深澜认证协议技术文档.md)。

## 致谢

LinkUp 使用 [Flutter](https://flutter.dev/) 构建，并参考了以下开源项目对深澜协议的实现：

- [1328411791/GDOUYJ_Internet_Client](https://github.com/1328411791/GDOUYJ_Internet_Client)
- [CyLzzh/srun_client](https://github.com/CyLzzh/srun_client)
- [Mmx233/BitSrunLoginGo](https://github.com/Mmx233/BitSrunLoginGo)

## 许可与免责声明

本项目采用 [MIT License](LICENSE) 开源，仅供学习和个人使用。请遵守所在学校的网络管理规定；使用本工具产生的后果由使用者自行承担。
