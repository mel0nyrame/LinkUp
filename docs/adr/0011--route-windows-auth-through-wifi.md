# 将 Windows 认证连接定向到当前 Wi-Fi

- **状态**：Active / implemented
- **日期**：2026-09-28
- **范围**：Windows 认证运行时的 Wi-Fi 事件与 IPv4 TCP 出口

## Problem

Windows 上以太网或 VPN 可以是默认路由，已连接的校园 Wi-Fi 仍可能承载尚未认证的 Portal。只看默认网络会漏掉这条 Wi-Fi；只在 Dart socket 上绑定 Wi-Fi 本地地址也不能明确指定出口接口。同一无线网卡切换接入网络时，连接类型和本地地址还可能保持不变，旧认证结果与 HTTP 连接不能继续代表当前网络。

## Decision

Windows 宿主通过 WLAN ACM 连接、断开通知和 IPv4 单播地址变化通知读取网络快照。快照只选择 WLAN 报告为已连接且拥有 IPv4 地址的网卡；用接口 GUID 对应 IP 适配器，不读取 SSID，也不设白名单。无线关联事件增加世代标记，因此即使地址未变化，切换 Wi-Fi 仍会通知 Dart。相同快照去重后传给现有 `AuthenticationCoordinator.networkChanged`；协调器继续独占单飞、状态、调度与旧结果失效。

认证协议继续使用 Dart `http.Client`。Windows 原生层为每条认证 TCP 连接创建一次本地回环隧道：主机名通过指定 Wi-Fi 接口的 `DnsQueryEx` 解析；远端 socket 同时绑定所选 Wi-Fi 的 IPv4 地址，并设置 Windows `IP_UNICAST_IF` 指向该接口。回环端口使用 `SO_EXCLUSIVEADDRUSE`；Dart `HttpClient.connectionFactory` 连接该端口，并在传输 HTTP 数据前提交原生层生成的一次性随机令牌，避免其他本地进程抢占端口读取认证流量。Reality、ACID、Portal 与在线确认复用同一注入的客户端。网络变化时协调器释放旧客户端，下一轮重新建立隧道。没有可用 Wi-Fi IPv4 地址时不发起认证连接。此绑定只作用于认证流量，不改变其他应用流量或系统路由。

Windows 的 [`IP_UNICAST_IF`](https://learn.microsoft.com/en-us/windows/win32/winsock/ipproto-ip-socket-options) 明确指定 IPv4 socket 的出口接口，[`DNS_QUERY_REQUEST.InterfaceIndex`](https://learn.microsoft.com/en-us/windows/win32/api/windns/ns-windns-dns_query_request) 指定 DNS 查询接口；[`WlanRegisterNotification`](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/nf-wlanapi-wlanregisternotification) 提供无线关联事件；[`HttpClient.connectionFactory`](https://api.dart.dev/dart-io/HttpClient/connectionFactory.html) 允许复用 Dart HTTP 协议实现并替换底层连接。

## Alternatives considered

- **仅使用 `connectivity_plus`**：连接类型不能可靠区分同类型 Wi-Fi 切换，也不能给出要绑定的 WLAN 接口。
- **仅在 Dart `Socket.startConnect` 指定 `sourceAddress`**：绑定源地址不等于指定 Windows 出口接口；VPN 默认路由下无法保证请求走 Wi-Fi。
- **修改系统路由或全进程代理**：影响无关网络请求，并引入权限与恢复系统设置的问题。
- **在 Windows 原生层复制 Srun 请求**：会形成第二份协议与认证状态实现，破坏协调器所有权。

## Consequences / Risks

- 仅支持拥有 IPv4 地址的 Wi-Fi。当前 Srun 默认服务器与协议路径使用 IPv4；纯 IPv6 网络的适配需要单独设计接口选择和协议地址处理。
- 回环隧道每个 TCP 连接占用一个短期监听端口和工作线程。监听在未连接时十秒后过期；HTTP 客户端关闭连接时，隧道随 socket 结束。
- 主机名解析指定 Wi-Fi 接口，但校园网 DNS、VPN 路由与真实 Portal 的组合仍需在 Windows 10/11 实机验收。父规格 [#37](https://github.com/mel0nyrame/LinkUp/issues/37) 保留这项门槛。Dart 模拟测试只证明事件、世代与通道行为，不能证明物理出口。
- Windows 构建能检查原生 API 和链接，但不能证明以太网或 VPN 同时连接时的出口选择。

## Reintroduction conditions

若 Dart 提供能对每条 Windows socket 设置 `IP_UNICAST_IF` 的稳定接口，可以撤去回环隧道；替换实现必须保留无线关联事件、接口身份、无 Wi-Fi 时不发送请求，以及网络切换后释放旧连接和结果失效的语义。
