# 将认证运行时所在进程绑定到校园 Wi-Fi

- **状态**：Active / implemented
- **日期**：2026-09-26
- **范围**：Android 校园 Wi-Fi 已连接但尚未成为系统默认网络时的认证请求

## Problem

校园 Wi-Fi 未认证时，Android 可以继续把移动数据作为默认网络。`connectivity_plus` 的 Android `checkConnectivity()` 查询 `ConnectivityManager.getActiveNetwork()`，因此它可能报告移动网络或无网络，尽管设备仍连接校园 Wi-Fi。若协调器据此进入离线状态，认证请求不会发出；即使跳过该检查，普通 HTTP socket 也可能走默认移动网络，访问不到校园网内的认证服务器。

[ADR-0005](0005--event-driven-network-and-boot-recovery.md) 已选择按 `TRANSPORT_WIFI` 监听网络，不依赖默认网络。该事件源必须同时承担认证时的 Wi-Fi 可用性事实来源和请求路由选择，才能覆盖未认证的 captive portal 阶段。

## Decision

协调器收到原生 `networkChanged` 后，以该事件中的 Wi-Fi 可用性为准；启动时尚无事件才使用现有 `NetworkUtil.isWifiConnected()` 快照。停止监控时清除事件快照。网络监听器在 `onAvailable` 时通过 `ConnectivityManager.bindProcessToNetwork(network)` 将进程后续 socket 绑定到 Wi-Fi，并在 `onLost` 时切换到仍可用的 Wi-Fi 或清除绑定。监听器停止时也清除绑定。绑定与事件下发在 Android 主线程顺序执行，确保认证检查启动前已有对应路由。即使 Wi-Fi 可用性持续为 true，所选 Wi-Fi 网络变化也会下发事件。每次事件使协调器通过协议工厂释放并重建生产协议实例，新的认证请求不会复用旧路由上的 HTTP 连接。

绑定需要 `CHANGE_NETWORK_STATE` 权限。权限或绑定失败时写入不含网络标识与认证参数的日志，继续报告 Wi-Fi 事件，让协调器尝试认证并按现有错误处理与退避逻辑呈现失败。

## Alternatives considered

- **只信任 `connectivity_plus` 的 `checkConnectivity()`**：它观察默认网络，无法证明非默认校园 Wi-Fi 是否仍连接。
- **仅跳过 Dart 的 Wi-Fi 判断**：认证请求仍可能从默认移动网络发出，无法到达校内认证服务器。
- **为每个 HTTP socket 单独绑定 `Network`**：Android 推荐单独绑定 socket，但现有认证协议使用 Dart `http` 与 `HttpClient`，没有可直接注入 Android `Network.getSocketFactory()` 的接口。引入原生代理或重写协议传输层会扩大实现范围并增加另一份路由所有权。

## Consequences / Risks

- 进程绑定是全局的：监控期间同一进程中新建的更新检查、下载等 socket 也走校园 Wi-Fi。未认证时这些请求可能失败；认证后继续使用该 Wi-Fi。停止监控或 Wi-Fi 断开后恢复系统默认路由。
- 已创建的 socket 不会因绑定自动迁移；网络变化时旧协议实例被关闭，下一轮检查使用新 HTTP 连接。正在进行的请求可能因关闭连接而短暂报告失败；网络世代检查阻止旧 ACID 落盘，新的 Wi-Fi 事件会触发补跑。断开事件会让协调器保持离线，不进入失败退避。
- Android 平台回调与进程路由的实际效果需要有移动数据同时开启、校园 Wi-Fi 尚未认证的真机环境验证。仓库的 Dart 回归测试覆盖事件优先级，跨语言契约测试覆盖绑定、清理和主线程下发，APK 构建只验证原生代码可编译。

## Reintroduction conditions

如果认证传输层以后支持按 socket 指定 Android `Network`，可以重新评估进程级绑定，但必须保留非默认校园 Wi-Fi 的识别、认证请求定向路由以及断开后的清理语义。
