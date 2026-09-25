# 集中单次认证尝试的参数与候选权威

- **状态**：Active / implemented
- **日期**：2026-09-25
- **范围**：LinkUp Android 客户端的单次 Srun 认证流程

## Problem

旧认证流程由 Widget 同时编排网络检测、ACID/Enc 探测、Challenge、Portal 登录和在线状态发布。认证客户端通过静态可变实例共享，Srun 登录又绕过实例 HTTP client；同一轮请求可能从不同来源读取 ACID、Enc 和网络参数。候选 ACID 还会在登录前写入配置，导致错误的根目录探测值或 Reality 捕获值污染持久化配置。

## Decision

`AuthenticationCoordinator` 是单次认证尝试的唯一编排入口，并依赖可替换的配置、协议、网络世代和持久化边界。UI、自动监控和手动刷新只调用协调器；`SrunClient`、`SrunLogin` 和 `AcidDetector` 通过实例注入，不再依赖静态认证客户端。

每轮尝试创建不可变 `AuthParameters`。它携带认证服务器、最终用户名、IP、ACID、`n`、`type`、callback 和受支持的 Enc；密码与 Challenge 作为瞬时秘密传递，不进入可观察参数。Info、Chkstr、checksum、Portal 的认证相关字段和协议前缀均从该对象生成。当前唯一传播的 Enc 是 `srun_bx1`，其他探测值只能作为脱敏诊断信息。

自动模式的 ACID 选择顺序固定为 Reality 捕获、已保存值、认证服务器根目录探测；手动模式只使用已保存值。候选携带来源和网络世代。登录失败、异常、取消、已经在线、网络世代变化或 `rad_user_info` 未确认在线时，候选失效且不写入配置。只有 Portal 成功后再次确认在线，协调器才通过带世代条件的局部 `ConfigUpdate(acid: ...)` 保存本轮实际使用的 ACID；条件在配置仓库真正写入前再次检查。

## Alternatives considered

- **继续由 Widget 编排并共享静态 Srun 客户端**：改动表面较小，但无法隔离并发尝试、HTTP transport 和参数来源，无法可靠阻止旧候选落盘，因此不采用。
- **在 Reality 或根目录探测成功后立即保存 ACID**：可以减少后续探测，但会把未经验证的值当作事实；Portal 假成功或登录失败时会污染用户配置，因此不采用。
- **直接传播页面声明的任意 Enc**：能够适配未知部署，但当前协议只验证了 `srun_bx1`，会让 Info、Chkstr 和协议前缀不一致，因此不采用。
- **把密码和 Challenge 放入可观察认证状态**：便于调试，但会扩大秘密暴露面，违反既有秘密存储和日志约束，因此不采用。

## Consequences / Risks

- 协调器状态流和单飞 Future 是认证运行时的事实来源；监控调度、退避和资源生命周期由 [ADR-0003](0003--coordinator-owns-monitoring-schedule.md) 拥有，Android 后台服务可以复用该边界而不必复制协议流程。
- 当前 `ConfigRepository` 仍把运行时 ACID 归一化为默认值 `1`，但通过 `hasExplicitAcid` 保留空值不可用状态；协调器据此决定是否进入根目录探测。
- `connectivity_plus` 的连接类型事件不能区分所有同类型 Wi-Fi 网络；当前世代保证依赖平台事件实际发出，后续若需要同类型网络切换级别的失效，应扩展网络身份来源。
- 协调器在配置确认后进行 ACID 局部更新；秘密存储或文件写入失败不会回滚已确认的在线状态，但会报告可恢复的持久化错误。
- 协议回归使用 fake 协议和注入的 `http.Client`，不连接真实校园网；真实网络行为仍需 Android 设备手工验证。

## Reintroduction conditions

只有在重新评估认证服务器身份、ACID 候选可信度、网络世代来源和 `srun_bx1` 协议向量后，才可以替换协调器边界或重新传播其他 Enc。替换实现必须保留不可变参数、JSONP/Latin-1 链、二次在线确认、候选失效和确认后局部持久化约束。
