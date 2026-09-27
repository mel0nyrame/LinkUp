# 集中单次认证尝试的参数与候选权威

- **状态**：Active / implemented
- **日期**：2026-09-25
- **范围**：LinkUp Android 客户端的单次 Srun 认证流程

## Problem

旧认证流程由 Widget 同时编排网络检测、ACID/Enc 探测、Challenge、Portal 登录和在线状态发布。认证客户端通过静态可变实例共享，Srun 登录又绕过实例 HTTP client；同一轮请求可能从不同来源读取 ACID、Enc 和网络参数。候选 ACID 还会在登录前写入配置，导致错误的根目录探测值或 Reality 捕获值污染持久化配置。

## Decision

`AuthenticationCoordinator` 是认证尝试的唯一入口，独占单飞、网络世代和调度；一轮内部的 Reality、用户信息、Challenge、Portal 登录与二次在线确认由可替换的 `AuthenticationAttempt` 执行。UI、自动监控和手动刷新只调用协调器；`SrunClient`、`SrunLogin` 和 `AcidDetector` 通过实例注入，不依赖静态认证客户端。

每轮尝试创建不可变 `AuthParameters`。它携带认证服务器、最终用户名、IP、ACID、`n`、`type`、callback 和受支持的 Enc；密码与 Challenge 作为瞬时秘密传递，不进入可观察参数。Info、Chkstr、checksum、Portal 的认证相关字段和协议前缀均从该对象生成。Chkstr 在 `n` 后使用 `type`，Enc 进入 Info 的 `enc_ver`。当前唯一传播的 Enc 是 `srun_bx1`；单轮实现不额外探测其他 Enc，避免无消费者的网络请求。

自动模式的 ACID 选择顺序固定为 Reality 捕获、已保存值、认证服务器根目录探测；手动模式只使用已保存值。候选携带来源和网络世代。登录失败、异常、取消、已经在线、网络世代变化或 `rad_user_info` 未确认在线时，候选失效且不写入配置。只有 Portal 成功后再次确认在线，单轮实现才通过带世代条件的局部 `ConfigUpdate(acid: ...)` 保存本轮实际使用的 ACID；条件在配置仓库真正写入前再次检查。

## Alternatives considered

- **继续由 Widget 编排并共享静态 Srun 客户端**：改动表面较小，但无法隔离并发尝试、HTTP transport 和参数来源，无法可靠阻止旧候选落盘，因此不采用。
- **在 Reality 或根目录探测成功后立即保存 ACID**：可以减少后续探测，但会把未经验证的值当作事实；Portal 假成功或登录失败时会污染用户配置，因此不采用。
- **直接传播页面声明的任意 Enc**：能够适配未知部署，但当前协议只验证了 `srun_bx1`，会让 Info 与协议前缀不一致，因此不采用。
- **把密码和 Challenge 放入可观察认证状态**：便于调试，但会扩大秘密暴露面，违反既有秘密存储和日志约束，因此不采用。
- **让协调器逐步调用协议接口**：步骤与网络世代守卫分散在调度代码里，替换一次尝试需要修改调度器，因此把步骤收进单轮接口。

## Consequences / Risks

- 协调器状态流和单飞 Future 是认证运行时的事实来源；监控调度、退避和资源生命周期由 [ADR-0003](0003--coordinator-owns-monitoring-schedule.md) 拥有。单轮实现把异步协议步骤后的取消与网络世代检查集中在同一守卫，测试可直接替换单轮接口而无需实现全部协议方法。
- 当前 `ConfigRepository` 把运行时 ACID 归一化为默认值 `143`，但通过 `hasExplicitAcid` 保留空值不可用状态；协调器据此决定是否进入根目录探测。
- `connectivity_plus` 的连接类型事件不能区分同类型 Wi-Fi 网络；Android 前台服务改由原生回调跟踪所选 `Network`，切换 Wi-Fi 时通知协调器失效旧世代。路由绑定及其风险由 [ADR-0007](0007--bind-auth-runtime-to-campus-wifi.md) 记录。
- 单轮实现在线确认后进行 ACID 局部更新；秘密存储或文件写入失败不会回滚已确认的在线状态，但会报告可恢复的持久化错误。
- 协议回归使用 fake 协议和注入的 `http.Client`，不连接真实校园网；真实网络行为仍需 Android 设备手工验证。

## Reintroduction conditions

只有在重新评估认证服务器身份、ACID 候选可信度、网络世代来源和 `srun_bx1` 协议向量后，才可以替换协调器边界或重新传播其他 Enc。替换实现必须保留不可变参数、JSONP/Latin-1 链、二次在线确认、候选失效和确认后局部持久化约束。
