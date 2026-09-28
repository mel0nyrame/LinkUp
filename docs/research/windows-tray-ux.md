# LinkUp Windows 托盘交互研究

调查日期：2026-09-28。范围是 Windows 端的托盘入口、状态、常用操作、设置与错误提示。只使用 Windows 官方设计文档及产品自己的文档、源码仓库或发布说明；未安装这些产品逐一实测，因此没有第一手证据的点击细节不作推断。

## 已确定的 LinkUp 需求

首版只支持 Wi-Fi，不支持有线网络，也不按 SSID 建白名单；关闭主窗口后继续在托盘运行；登录 Windows 后自启为可选项；功能尽量接近 Android，包括认证配置、自动重连、状态、网络信息、在线设备和日志。现有 Android 功能见项目 [README](../../README.md)。Windows 端采用“左键状态浮层、右键简短菜单、详细功能独立窗口”的交互方向。下面关于 LinkUp 的具体布局和文案仍是**建议**，不是对竞品现状的描述。

## 已确认的视觉方向

浮层以 [Windows 托盘视觉稿](windows-tray-ui-comparison.png) 的 **A 方案状态区加 B 方案简短信息行**为基准，采用简洁的 Windows 桌面风格并保留 LinkUp 蓝色。视觉稿中的英文、示例 Wi-Fi 名称、日期和图标仅用于比较信息层级，不是正式文案或资产。

## 第一手资料中的实际做法

| 来源 | 可核实的交互 | 对 LinkUp 的启发 |
| --- | --- | --- |
| [Tailscale Windows 安装说明](https://tailscale.com/docs/install/windows) | 安装后出现托盘图标；官方明确写右键图标可看到配置选项和状态消息，菜单中的登录项会打开浏览器。其 [MSI 安装说明](https://tailscale.com/docs/install/windows/msi) 则写“选择”图标查看配置和状态，没有明确鼠标键位。 | 状态和配置可直接放在托盘入口；不能根据这些文字断言它的左键行为。 |
| [Cloudflare WARP Windows 说明](https://developers.cloudflare.com/warp-client/get-started/windows/) | 启动后出现图标；启用连接用界面开关；选择图标后可经齿轮进入模式选择和 Preferences。文档明确把 GUI 与负责连接的 Windows service 分开。其 [Windows 更新说明](https://developers.cloudflare.com/changelog/post/2025-11-11-warp-windows-ga/) 记录了 GUI 中增加“不稳定连接”状态消息。 | 轻量控制面板适合承载一眼可读的状态和一个主要动作，详细设置另开页面；网络问题应有文字解释。文档没有明说图标点击弹出的是何种窗口，也没有说明右键菜单。 |
| [ZeroTier 入门说明](https://docs.zerotier.com/start/) 与 [离网说明](https://docs.zerotier.com/network-leave/) | Windows 有托盘应用；可从菜单加入网络，点击菜单中已勾选的网络可断开，也可进入 Network Details 修改。其 [1.10.0 发布说明](https://github.com/zerotier/ZeroTierOne/blob/dev/RELEASE-NOTES.md#2022-06-07----version-1100) 说明曾移除桌面 WebView，将功能放入托盘下拉菜单，少量输入使用小对话框。 | “菜单为主”确实能支撑较完整的网络工具，但 LinkUp 有账号、ACID、设备与日志等信息，全部塞入原生菜单会使层级和输入复杂。资料未明确 Windows 上左键和右键分别怎样响应。 |

这些产品解决的是 VPN、虚拟网络或 DNS 连接，不是深澜 Portal 认证。它们展示了入口形态，不能直接复制连接开关的语义：LinkUp 的日常行为是检测校园 Wi-Fi 并自动认证，用户通常只需要检查和排障。

## Windows 平台约定

[Microsoft 通知区域指南](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification)建议：悬停提示显示程序名与简短状态；左键单击必须有可见响应，适合打开状态浮层；右键打开上下文菜单；小窗口靠近图标，失焦后关闭；浮层可按“摘要、常用操作、相关链接”组织。状态图标可用警告、错误、断开等变化表达高层状态，但不应频繁闪烁或持续动画。同一指南说明托盘上下文菜单可提供打开、暂停或启用、选项和退出等命令。

这份指南注明它写于 Windows 7，未按新版 Windows 更新。它还建议单实例程序用“最小化”而不是窗口“关闭”进入托盘；LinkUp 则选择关闭窗口后继续运行。因此首次关闭时应提示程序仍在托盘运行，并保持菜单中有显眼的“退出 LinkUp”，避免让用户误以为关闭后程序已经停止。这是 LinkUp 的产品取舍，不代表微软推荐关闭到托盘。[Microsoft 通知区域指南](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification)

系统可能将新托盘图标放进折叠区域，应用不能替用户强制固定到可见区域；Tailscale 的安装说明也提醒从上箭头查找图标。[Microsoft 通知区域技术文档](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area)；[Tailscale Windows 安装说明](https://tailscale.com/docs/install/windows)。

[Microsoft 通知设计指南](https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/toast-ux-guidance)要求通知有明确用途并避免频繁打断。对自动重连工具，这支持只对需要用户处理或持续失败的情况发系统通知，普通重试与成功恢复主要更新图标、提示和浮层；通知点击应进入对应问题页面。这里的“何时通知”是 LinkUp 的产品建议，并非微软为校园网认证规定的规则。

## 方案比较与建议

| 方案 | 优点 | 局限 | 取舍 |
| --- | --- | --- | --- |
| 左右键都开同一菜单 | 实现与操作都简单；接近 ZeroTier 的菜单型工具。 | 账号输入、在线设备、日志和错误解释难在菜单中呈现。 | 不作为首选。 |
| 左键打开完整主窗口，右键菜单 | 可直接复用较多 Android 页面结构。 | 高频“看一眼状态”需打开较大窗口，与“托盘为主”目标不符。 | 作为实现浮层受阻时的备选。 |
| **左键状态小浮层，右键简短菜单，设置另开窗口** | 左键快速看状态、处理常见问题；复杂功能留给可正常输入和滚动的窗口；符合微软的左键浮层与右键菜单约定，也接近 WARP 的图标入口加设置分层。 | 需要维护浮层和设置窗口两个表面，注意状态一致性。 | **建议采用。** |

建议的左键浮层只显示：当前 Wi-Fi 名称（若可读取）；“已在线 / 正在检查 / 正在认证 / 等待 Wi-Fi / 认证失败”等明确状态；一句原因或下一步；“立即检查”操作；进入“详细信息与设置”的入口。已在线时可显示 IP、流量、在线时长的简短摘要；在线设备、完整网络信息、账号与 ACID、系统开关和日志放入独立窗口。此布局是依据 Android 当前功能和微软浮层“摘要、常用操作、相关链接”结构所做的设计建议。[项目 README](../../README.md)；[Microsoft 通知区域指南](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification)

建议的右键菜单顺序是“打开 LinkUp / 立即检查 / 设置 / 查看日志 / 退出 LinkUp”。菜单首项也可直接写当前状态摘要，但不要把“已在线”做成可点击操作。悬停提示保持如“LinkUp · 已连接校园网”或“LinkUp · 等待校园 Wi-Fi”的简短文本；图标只表达在线、处理中、等待网络、需处理错误几类稳定状态，不表示每一次重试。[Microsoft 通知区域指南](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification)

设置窗口承载尽量接近 Android 的功能，但排版按桌面场景重做：账号及认证配置、自动认证/监控、登录自启、在线设备、详细状态和日志。自动认证不宜被一个含糊的“连接/断开”总开关替代；若提供暂停自动认证，名称和效果应明确。退出 LinkUp 只结束当前进程，不修改登录自启设置；若自启仍开启，下次登录 Windows 时会重新运行。[项目 README](../../README.md)；[Microsoft 通知区域指南](https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification)

## 资料边界

- 没有可靠的第一手资料能证明三款产品的所有左键、右键、双击和“关闭窗口”行为；上文仅写官方资料明确表达的部分。
- 微软通知区域设计指南是旧版 Windows 的规范参考，需在 Windows 10/11 实机检查浮层位置、任务栏折叠、高 DPI 和焦点行为。
- 本文回答交互设计，不验证 Flutter 托盘插件、Windows Wi-Fi 识别和认证运行时的技术可行性。
