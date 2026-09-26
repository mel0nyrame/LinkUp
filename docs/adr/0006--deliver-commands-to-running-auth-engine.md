# 通过 MethodChannel 向运行中的认证 Engine 发送命令

- **状态**：Active / implemented
- **日期**：2026-09-26
- **范围**：Android 前台服务与后台 Dart 认证运行时之间的命令传输
- **替代**：[ADR-0004](0004--foreground-service-owns-auth-runtime.md) 中的 callback dispatcher 命令传输方案；前台服务持有唯一认证运行时的决策继续有效

## Problem

`AuthRuntimeService` 已用 `DartEntrypoint` 启动后台 `FlutterEngine`。原命令桥又在同一个 Engine 上调用 `DartExecutor.executeDartCallback`。Flutter Android embedding 对正在运行的 `DartExecutor` 直接记录警告并返回，回调函数不会执行，UI 的启动命令也不会进入协调器。原桥构造的命令参数列表没有交给 `executeDartCallback`，即使在空闲 Engine 上启动回调也无法传递命令。结果是后台运行时停在初始状态，在线检查和自动重连均无法开始。

## Decision

后台入口仅启动一次。在 Dart 侧注册 `com.mel0ny.linkup/authRuntime` 的命令处理器后，向 Android 桥发送 `ready`；Android 桥在此之前排队命令，收到 `ready` 后按顺序通过同一 MethodChannel 调用 `command`。命令名和参数作为 Map 传递，Dart 处理器调用唯一的 `AuthRuntimeController`，并通过 MethodChannel 调用结果把返回值交还给原生侧。服务销毁时桥使待处理的 UI 请求失败。

后台入口仍使用 `@pragma('vm:entry-point')` 并由主 APK 的 Dart bundle 引用；Activity 的 Engine 仍不创建协调器。状态与常驻通知继续通过原有脱敏快照发布。

## Alternatives considered

- **在运行中的 Engine 上重复调用 `executeDartCallback`**：Flutter embedding 不会再次执行入口，命令被忽略，因此不可用。
- **每条命令新建一个 FlutterEngine**：每个 Engine 都会有独立 isolate，破坏认证运行时单一所有者，并增加启动成本。
- **在 Dart 命令处理器注册前直接发送 MethodChannel 命令**：处理器尚未就绪时命令可能丢失；保留 `ready` 握手与队列。

## Consequences / Risks

- 原生与 Dart 两侧必须保持通道名、`ready`、`command`、`name`、`args` 和返回值语义一致；跨语言契约测试直接检查这些接线。
- `ready` 只在 Dart 命令处理器注册后发布。若后台入口未打入 AOT 快照或启动失败，命令不会出队；release 构建与真机服务启动检查仍是必要验证。
- 命令执行期间服务销毁时，桥会结束待处理的 UI 请求；后到的运行时回包不能恢复已销毁的服务。

## Reintroduction conditions

只有新的 Flutter embedding API 明确支持向已有 isolate 再次执行带参数的回调，并且该方案保留单一协调器、启动握手、排队命令与请求完成语义时，才重新考虑 callback dispatcher。
