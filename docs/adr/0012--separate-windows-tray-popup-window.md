# 将 Windows 托盘状态浮层与详情窗口分离

- **状态**：Active / implemented
- **日期**：2026-09-29
- **范围**：Windows 托盘浮层、详情窗口与认证运行时的所有权

## Problem

Windows 托盘左键需要显示贴近图标的状态浮层，详情窗口则保留完整的窗口尺寸、任务栏入口和关闭到托盘行为。把同一个 HWND 临时改成弹出窗口并切换 Flutter 页面，会让两种窗口共享尺寸、焦点和关闭语义；[#59](https://github.com/mel0nyrame/LinkUp/issues/59) 记录了实机左键打开完整“网络概况”窗口的结果。认证尝试仍必须由进程内唯一的 `WindowsAuthRuntime` 管理。

## Decision

`FlutterWindow` 保持完整详情窗口和唯一认证运行时。托盘左键创建并显示一个独立的顶层工具窗口；该窗口用单独的 Flutter UI engine 运行 `popupMain`，不初始化配置、网络监听或认证协调器。主运行时只把状态标题、下一步、Wi-Fi、认证和监控的展示快照传给浮层，账号、凭据、协议参数和设备明细不进入这条通道。浮层的“立即检查”和“详细信息”命令交回主窗口，分别进入现有单飞认证入口和完整窗口。浮层再次左键或失焦时隐藏；完整窗口关闭时隐藏 UI，显式退出才释放运行时和两个窗口。

窗口位置继续由通知区域图标矩形、所在显示器工作区和 DPI 计算。托盘消息按照 `NOTIFYICON_VERSION_4` 的事件语义处理，并保留旧版本回退。自动测试覆盖状态投影、通道命令和原生接线；位置、焦点、折叠区域和高 DPI 仍以 Windows 10/11 实机验收为准。

## Alternatives considered

- **继续复用主 HWND 并切换 compact 页面**：不增加 engine，但主窗口和浮层无法拥有独立的窗口身份、尺寸与关闭行为，且已经出现 #59 记录的实机缺口。
- **使用 Flutter 桌面多窗口 API 共享一个 engine**：Flutter 官方将桌面窗口 API 标为[实验性且未面向生产](https://github.com/flutter/website/blob/main/sites/www/content/blog/whats-new-in-flutter-3-44/index.md)；仓库声明的 SDK 中相关 Dart API 仍位于 `package:flutter/src/`。不把这条不稳定接口作为 Windows 安装包的基础。
- **在 Win32 原生层绘制整个浮层**：可以避免第二个 Flutter engine，但状态布局、文字缩放和交互需要在 Dart 与 C++ 分别维护，容易使两种 UI 的状态语义漂移。

## Consequences / Risks

- 首次打开浮层会初始化一个只承载 UI 的 Flutter engine，此后复用直到退出；它增加进程内存，但不产生第二个认证周期。
- 浮层只依赖投影快照，不能直接读取配置或在线设备。新增浮层信息必须先检查是否属于可公开的状态展示数据。
- Dart/widget 测试和 MinGW 语法检查不能证明 Windows shell 的实际点击、焦点或安装包行为；#59 的实机截图验收仍是交付门槛。

## Reintroduction conditions

Flutter 为 Windows 提供稳定的同 engine 多窗口 API，并能与现有托盘宿主、焦点和 DPI 行为兼容时，可以替换浮层 UI engine；仍须保留两个独立窗口和唯一认证运行时。
