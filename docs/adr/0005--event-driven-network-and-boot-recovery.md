# 用平台网络事件与开机广播恢复认证

- **状态**：Active / implemented
- **日期**：2026-09-26
- **范围**：LinkUp Android 客户端从网络变化和设备启动事件恢复认证

## Problem

[ADR-0003](0003--coordinator-owns-monitoring-schedule.md) 让协调器独占调度，退避上限 60 秒、在线周期 30 秒。这意味着校园 Wi-Fi 断开又恢复时，用户最多要等一个退避周期才重新认证：网络已经可用，LinkUp 还在睡。用户视角这是“网好了但没连上”。

`BootReceiver` 当时直接 `startActivity` 拉起界面，且只看 `auto_start` 一个偏好。这既让“开机自启”绕过“保留后台运行”这个总开关，也让开机认证依赖 Activity 存在，与 [ADR-0004](0004--foreground-service-owns-auth-runtime.md) 的前台服务所有权冲突。

开机时通常还没有网络，服务起来后只能靠退避重试，既费电又刷满失败日志。

## Decision

服务存活期间注册 `ConnectivityManager.registerNetworkCallback`，只跟踪 `TRANSPORT_WIFI`。不跟踪默认网络：未认证的校园网不会成为系统默认网络，跟默认网络会漏掉“Portal 可达但尚未认证”这段最需要自动认证的窗口。回调只维护一个 `reported` 状态，可用性没变就不下发事件。服务在 `ensureMonitoring()` 中注册，在 `stopRuntime()` 和 `onDestroy()` 中注销。

平台回调只发一条 `networkChanged` 命令，负载是 `connected` 布尔值。Srun 协议、网络世代判定和是否立即检查全部由协调器决定：事件使当前网络世代失效并 `protocol.reset()`，断网时直接进入离线状态，恢复时取消待执行的退避并立即通过 `check()` 的单飞入口检查，不新建 Reality 或登录流程。因此同一次网络抖动只会合并成一次补跑。

协调器的离线结果不再进入退避循环。定时轮询无法区分“网络断了”和“网络通着但认证失败”，让离线也退避会让服务在无网络时反复失败重试；现在离线保持静默，等首个有效网络事件唤醒。

`BootReceiver` 只在三个条件同时成立时调用 `AuthRuntimeService.start`：已保存账号配置、“保留后台运行”、“开机自启”。它不创建也不拉起 Activity，因此开机自启是“保留后台运行”的下游开关，关掉总开关后即使 `auto_start` 仍为 true 也不会启动服务。开机时没有网络，服务进入离线状态等待，不产生失败循环。

“配置存在”这份跨语言事实由 Dart 写入 plain 偏好 `account_configured`，`ConfigUtil` 在保存配置、删除配置和每次启动的 `configExists()` 检查时同步。默认值 false，读取失败按无配置处理，即不开服务。

## Alternatives considered

- **跟踪默认网络（`NetworkRequest` 不限定传输类型）**：未认证的校园网不会成为系统默认网络，最需要自动认证的阶段收不到事件，因此不采用。
- **在 Dart 侧用 `connectivity_plus` 的 `onConnectivityChanged` 驱动**：协调器检查时本来就会读 `NetworkUtil.isWifiConnected()`，但后台认证 isolate 里的事件流与协调器调度不在同一个线程上下文，且 `connectivity_plus` 无法区分同类型 Wi-Fi 之间的切换。把事件源放在原生侧可以让注册与注销跟随服务生命周期，不需要为后台 isolate 补一层事件转发。
- **让协调器继续对离线退避重试**：开机无网络时会持续失败重试并刷日志，而重试成功率完全取决于网络何时回来，后者已经有事件可等，因此不采用。
- **在 Kotlin 里解析配置文件判断“配置存在”**：配置文件在 `path_provider` 的应用文档目录，插件 2.3.1 起是纯 Dart FFI 实现，Kotlin 无法在不复制实现细节的前提下定位该目录；复制会让插件升级静默失效，因此改用 Dart 写入的派生标记。
- **开机时若配置未知就启动服务**：开机发生在用户可能从未打开过应用的设备上，无配置启动只会产生必然失败的认证流量，因此默认不启动。
- **用 WorkManager、精确闹钟或后台 Activity 兜底**：只是绕过系统策略，不会让认证真正持续，并引入额外调度来源，与 [ADR-0004](0004--foreground-service-owns-auth-runtime.md) 的取舍一致，因此不采用。

## Consequences / Risks

- 后台认证从“最多等一个退避周期”变成“网络可用即检查”，退避只承担认证失败与网络不稳定的混合情形。
- 离线结果不再进入退避重试，这推翻了父规格中“离线或失败状态从 3 秒开始指数退避，最大 60 秒”的后半句：开机无网络时的重试成功率完全取决于网络何时回来，保留 60 秒空转只换取日志噪音。代价是离线状态的恢复完全依赖原生事件：只跟踪 `TRANSPORT_WIFI`，走蜂窝或以太网时既不会认证也不会重试（这两种链路 LinkUp 本就无法认证）；`registerNetworkCallback` 若抛 `SecurityException`，事件通道缺失，认证只靠开机那一次检查，之后依赖用户重新打开应用。
- 网络事件与手动检查、配置变化共用单飞入口，三者并发时只保留最新网络世代的结果能更新状态或持久化 ACID。
- `account_configured` 是派生副本。标记写入失败时开机自启可能不启动服务；它由保存、删除和启动检查三条路径同步，升级后用户打开一次应用即恢复一致。
- 派生标记读取依赖 `shared_preferences` 的 `flutter.` 前缀约定，该风险与 ADR-0004 记录的一致。
- Android 不承诺在用户强行停止、撤销系统权限或厂商 ROM 强制终止后自动恢复；这些边界由 README 说明，不在代码中尝试绕过。
- 网络回调的生命周期断言是跨语言契约的一部分：`test/android_runtime_contract_test.dart` 断言服务注册与注销路径、回调只上报可用性不接触协议、开机三条件门和不拉起 Activity。Kotlin 侧的运行时行为需要 `Context`，仓库不引入 Robolectric，真机场景由 issue #8 验收。

## Reintroduction conditions

只有在 Android 提供可替代的常驻网络事件通道，或 `connectivity_plus` 能区分同类型 Wi-Fi 之间的切换时才重新评估事件源。替换实现必须保留原生只发命令、单飞入口唯一、网络世代隔离、离线不循环重试和开机三条件门这些约束。
