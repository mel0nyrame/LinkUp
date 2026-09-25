# 用前台服务承载唯一的后台认证运行时

- **状态**：Active / implemented
- **日期**：2026-09-25
- **范围**：LinkUp Android 客户端的后台认证生命周期

## Problem

`AuthenticationCoordinator` 已经是认证状态和监控调度的唯一 owner，但它由 Flutter UI isolate 持有：`MainNavigator` 在 `initState` 里创建协调器并 `start()`，`dispose()` 时释放。Activity 一旦销毁，监控调度、协议会话和 ACID 世代全部随之消失，“保留后台运行”只靠 `wakelock_plus` 保持屏幕常亮来假装保活。系统回收进程后没有任何东西能重建认证，“开机自启动”广播接收器反而拉起 Activity。

后台认证需要一个独立于 UI 的运行时所有者，并且在没有 Activity 的情况下仍能被系统重建。

## Decision

Android 用一个非导出的 Foreground Service 承载后台认证运行时。服务在 `onCreate` 中创建独立 `FlutterEngine`，用 `DartExecutor.DartEntrypoint` 以无参形式启动 `linkupAuthRuntimeDispatcher`，再用 `GeneratedPluginRegistrant` 显式注册插件——`flutter_secure_storage` 必须在该 engine 中注册，Keystore 秘密存储才能在后台运行时可用。

Dart 入口用 `@pragma('vm:entry-point')` 保留在 AOT 快照中。它在启动后通过 MethodChannel 上报自己的 `CallbackHandle`，宿主此后用 `DartExecutor.executeDartCallback` 这个 callback dispatcher 下发启动、停止、手动检查、注销、踢设备和配置变化命令。句柄尚未上报时命令会被排队并在就绪后按序补发，因此启动时序不需要和 Dart 入口竞争。宿主→Dart 的命令结果通过同一个通道以请求标识回传，UI 侧的 `invokeMethod` 因此仍是一个可 await 的 Future。

服务类型使用 `specialUse` 并声明 `FOREGROUND_SERVICE_SPECIAL_USE` 与 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`。不使用 `dataSync`：它受 Android 15+ 每 24 小时 6 小时限制，并且禁止从 `BOOT_COMPLETED` 启动。前台服务只在服务被 `startForegroundService` 启动时进入前台；Activity 可见时的绑定不会创建常驻通知。

桥只搬运命令和状态。协调器、Srun 协议、退避策略仍只有一份 Dart 实现，Kotlin 不复制任何认证规则。常驻通知文本由 `notificationContentFor(AuthRuntimeState)` 在 Dart 侧从状态枚举和重试间隔派生，不读取用户信息、ACID 或状态 message，因此通知在结构上不可能出现账号、密码、Challenge、HMD5 或签名。

Activity 通过 `bindService` 绑定这一个运行时，用 `com.mel0ny.linkup/authUi` 通道订阅状态并发送命令。Activity 的 FlutterEngine 不创建协调器也不创建认证周期 Timer；`attach` 返回最近一次发布的状态，因此 UI 重建后立即恢复最新视图。`MainNavigator` 在首个 post-frame 回调请求一次 `start`，保留“打开应用立即检查”的既有行为。

关闭“保留后台运行”时宿主下发 `stop`，协调器取消调度并释放 HTTP client 与 Portal 缓存，服务退出前台并 `stopSelf`；仍被 Activity 绑定时服务存活到解绑，`onDestroy` 销毁 `FlutterEngine`，后台 isolate 随之终止。开启时服务以 `START_STICKY` 运行，系统回收后可重建。`wakelock_plus` 只用于保活，因此连同“屏幕常亮”文案一起移除。

## Alternatives considered

- **继续由 Activity 持有协调器并用屏幕常亮保活**：屏幕常亮只在用户注视屏幕时有效，切后台和锁屏后仍会被系统回收，无法兑现“保留后台运行”，因此不采用。
- **在 Kotlin 中实现认证逻辑**：会产生第二份 Srun 协议实现，两处都必须跟随协议变更，且难以与 [ADR-0002](0002--centralize-authentication-attempt-authority.md) 的参数权威保持一致，因此不采用。
- **Activity engine 与后台 engine 各自运行协调器**：会并发执行 Reality、`rad_user_info` 和登录，共享可变 Portal 缓存并互相覆盖 ACID 候选，因此不采用。
- **把认证直接放进 Activity 的 FlutterEngine**：Activity 销毁后运行时一并消失，无法满足后台重连，因此不采用。
- **宿主用 MethodChannel handler 直接接收命令**：MethodChannel 的处理器注册与 Dart 入口启动存在时序竞争，先到的命令会被静默丢弃；callback dispatcher 由 `CallbackHandle` 定位入口函数，不依赖注册时序，因此采用。
- **使用 `dataSync` 服务类型**：`dataSync` 受 6 小时上限约束且禁止开机启动，不适合长期校园网保活，因此不采用。
- **使用 WorkManager、精确闹钟或后台 Activity 规避后台限制**：这些只是绕过系统策略，不会让认证真正持续，且引入额外调度来源，因此不采用。
- **通知内容直接在 Kotlin 侧从状态映射拼装**：状态包含用户信息和认证参数，映射一旦写错就可能泄漏敏感数据；在 Dart 侧从脱敏快照派生可以结构性避免，因此不采用。

## Consequences / Risks

- 同一进程内存在两个 Dart isolate：Activity 的 UI isolate 和服务的认证 isolate。跨 isolate 状态通过宿主转发，代价是状态更新多一跳。
- `AuthRuntimeBridge` 是进程级单例，其生命周期由服务拥有。服务销毁时必须 `detachEngine()` 并让在途命令失败，否则 UI 的 `invokeMethod` 会悬挂。
- `linkupAuthRuntimeDispatcher` 依赖 `@pragma('vm:entry-point')` 才能在 AOT 中保留。移除该注解会让 release 构建静默失去后台入口，因此 release 构建是必要验证项。
- `BackgroundRuntimeSettings` 直接读取 `FlutterSharedPreferences` 的 `flutter.` 前缀键。该约定由 `shared_preferences` 插件决定，插件升级改变前缀或桶名时原生读取会静默失效。
- 开机自启广播接收器仍然拉起 Activity。两个开关同时开启时才启动服务的语义属于 issue #7，本决策不覆盖该行为。
- 平台契约测试通过 Dart 侧的窄 seam 覆盖服务启动、通知状态、UI 命令路由、Activity 销毁后继续运行和关闭后资源释放。Android 服务的实际生命周期、厂商 ROM 限制和开机场景由 issue #8 在真机上验收。

## Reintroduction conditions

只有在重新评估 Android 前台服务类型政策、后台执行限制、Flutter 多 isolate 成本和通知可见性要求后，才可以更换服务类型或运行时宿主方式。替换实现必须保留单一协调器所有者、callback dispatcher 命令通道、状态脱敏边界、sticky 重建语义和 force-stop 不承诺恢复的约束。
