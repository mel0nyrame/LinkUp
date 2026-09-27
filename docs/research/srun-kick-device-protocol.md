# 深澜「踢设备」功能与 `rad_user_dm` 协议调查

调查日期：2026-09-27。范围：LinkUp 的踢设备（kick device）功能、它依据的深澜协议，以及用户报告的「点了踢设备但没有实际效果」这一故障。只读调查，未修改任何实现代码，未运行构建或测试。

本文结论按证据强度分三级标注：【一手·官方】来自深澜官方前端产物（未混淆的 `Portal.js` / `lang.js`）；【一手·源码】来自开源客户端的实际源码或作者注释；【二手】来自技术博客或论坛；【推测】是本调查的推断，没有直接证据。

## 结论摘要

1. **LinkUp 的协议方向是对的。** 踢设备不需要新端点，官方 Portal 内置的「在线设备管理」面板用的就是 LinkUp 已实现的 `/cgi-bin/rad_user_dm`，唯一区别是 `ip` 传目标设备的地址。签名公式与官方逐字一致。
2. **`error: "ok"` 不是「已断开」的证据，这是 LinkUp 判定逻辑最严重的问题。** 官方自己的前端**完全不信** `rad_user_dm` 的响应——它发出 DM 之后轮询 `rad_user_info?ip=`，直到该 IP 报不在线才宣布成功。LinkUp 只读 DM 响应就弹绿色 SnackBar。
3. **`username` 的取值与官方不同，是否就是原因待验证。** 官方把 `rad_user_info` 返回的裸 `user_name`（注释明确「不会携带域」）直接用作 DM 的 `username`，域单独存着不拼进去；11 个开源实现也这么做。LinkUp 用的是配置里拼好的 `账号@userType`。**目标部署要求哪一种，调查无法确定**，需实机抓包（§8 第 2 步）。本 PR 不改这个行为。
4. **成功值不唯一，LinkUp 只认 `ok`。** 跨三代部署，`rad_user_dm` 成功时可能返回 `ok`、`logout_ok`、`LogoutOK` 或裸文本 `logout_ok`。9 个开源实现要求 `logout_ok`，其中 1 个明确把 `ok` 判为失败。**这是多实现观察，不是目标部署的事实**；本 PR 不动这个判定。
5. **「踢设备」本身可能没有产品意义。** DM 只置离线、不封禁。目标设备下一次认证就回来了。若目标设备跑着自动认证客户端（LinkUp 自己就是），会立刻重连。
6. **用户侧踢设备是可选部署能力。** 官方码表里有 `E4104`「来自自服务（8800）的 DM 下线」，说明它被官方承认；但官方 2025 版自助服务平台的功能公告里没有这一项，各校还要受跨校区、网络位置限制。

## 1. LinkUp 现状

以下三小节记录的是**调查当时的代码**（`master` 基线），行号对应那个版本。本 PR 已改动的部分在 §7 的「本 PR 已处理」里逐条列出。

### 1.1 调用链

踢设备与注销自己共用同一条链路，协议层的区别只有一个 `ip` 参数的值。

```
OverViewPage._showKickConfirmDialog(OnlineDevice)                 lib/page/OverViewPage.dart:73
  └─ widget.onKickDevice!(device.ip ?? '')                         lib/page/OverViewPage.dart:107
     └─ MainNavigator._kickDevice(String) -> Future<bool>          lib/navigation/MainNavigation.dart:236
        └─ AuthRuntimeClient.kickDevice(String)                    lib/utils/AuthRuntimeClient.dart:67
           └─ MethodChannel "com.mel0ny.linkup/authUi" → AuthRuntimeBridge.dispatch
              └─ AuthRuntimeController.execute()                   lib/utils/AuthRuntimeController.dart:72
                 └─ AuthenticationCoordinator.kickDevice()          lib/utils/AuthenticationCoordinator.dart:450
                    └─ AuthenticationAttempt.kickDevice()           lib/utils/AuthenticationAttempt.dart:107
                       └─ AuthenticationProtocol.logout(ip: 目标IP)  lib/utils/SrunAuthenticationProtocol.dart:86
                          └─ SrunLogin.dmLogout()                   lib/utils/SrunLogin.dart:278
                             └─ SrunClient.dmLogout()               lib/utils/SrunClient.dart:235
```

跨语言契约常量在 `android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeBridge.kt:26`（`COMMAND_KICK_DEVICE`）和 `lib/utils/RuntimeContract.g.dart:11`。Kotlin 侧不区分 `kickDevice` 与 `logout`，两者都是通用分发，符合 `AGENTS.md` 的「Kotlin 不得复制 Srun 协议逻辑」约束。

### 1.2 实际请求

`lib/utils/SrunClient.dart:234-268`：

```dart
final time = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
const unbind = 1;
final sign = SrunEnrypt.Sha1('$time$username$ip$unbind$time');
final params = {
  'callback': 'jQueryCallback', 'ip': ip, 'username': username,
  'time': time.toString(), 'unbind': '1', 'sign': sign,
  '_': DateTime.now().millisecondsSinceEpoch.toString(),
};
final uri = Uri.parse('http://<host>/cgi-bin/rad_user_dm').replace(queryParameters: params);
final response = await _get(uri, {'User-Agent': userAgent});
final jsonData = jsonDecode(_extractJsonFromJsonp(response.body, 'jQueryCallback'));
return jsonData['error'] == 'ok';   // ← 唯一的成功判定
```

`username` 来自 `ConfigUtil.dart:70-71` 的 `authenticatedUsername`，即 `'$username@$userType'`。签名按 Latin-1 字节计算（`lib/utils/SrunEncrypt.dart:20-24`）。

### 1.3 踢出成功后 UI 不刷新

这不是协议问题，但是「看起来没效果」的直接放大器。

`git show 24d8ea3`（`feat(kick-device)` 源头提交）的 body 写明「成功：刷新 `_userInfo`」，原始实现确实在踢出后主动调 `getUserInfo` 并 `setState`。后台运行时重构（ADR-0004 / ADR-0006）之后，`_kickDevice` 只发命令、等返回值、弹 SnackBar，不再刷新。`lib/navigation/MainNavigation.dart:87-91` 的 `_userInfo` 只由认证状态流驱动，所以被踢的行要等下一次 `rad_user_info` 轮询才消失。

同一次重构还删掉了成功日志 `LogUtil.info('踢设备成功: $targetIp')`。现存的两条日志（`MainNavigation.dart:255` 的 `'踢设备异常'`、`SrunLogin.dart:281` 的 `'DM 注销结果: $result'`）都不带 IP，踢出和注销共用一条，**因此踢出失败时无法从日志定位是哪台设备**。不做这个改动是对的（`AGENTS.md` 禁止把认证参数写入日志），但结果是无法诊断。

### 1.4 测试覆盖

`test/srun_client_test.dart` 里没有任何 `rad_user_dm` 用例——URL、query、`unbind`、`sign` 一个都没断言。`test/overview_page_test.dart` 里 `kick` / `踢` / `device` 零匹配。`AuthenticationCoordinator.kickDevice` 只被 `test/auth_runtime_test.dart:87-109` 间接覆盖。**协议层的踢设备行为从来没有被测试验证过。**

## 2. 一手事实：深澜官方如何踢设备

### 2.1 官方 Portal 前端逐字实现

【一手·官方】`Portal.js` 是深澜 Portal 的前端产物，未混淆。多个学校部署的副本内容一致，作者署名为 `xr@srun.com`。以下代码来自一个**活的 2020 代部署实例** `http://139.155.140.234:4821/static/themes/pro/js/Portal.js`，以及 `hduhelp/hdu-cli/pkg/srun/Portal.js` 仓库副本。

端点常量（`_api` 对象）里：

```js
loginDM: '/cgi-bin/rad_user_dm',
info:    '/cgi-bin/rad_user_info',
getOnlineDevice: '/v1/srun_portal_online',
```

「在线设备管理」面板（`OnlineDeviceManager`）每行渲染一个按钮：

```js
'<button class="btn-logout" data-ip="' + item.ip + '">' + translate('Logout') + '</button>'
```

点击后调用 `_logoutDm({ip: <该行设备IP>})`：

```js
// Portal.js sendLogout()
var time = Date.parse(new Date()) / 1000;
var unbind = 1;                                                    // 官方注释原文「优先使用指定 IP」
var ip = obj.ip || (_this.portalInfo.doub && host ? '' : _this.userInfo.ip);
_this.ajax.jsonp({
  host: host,
  url: _api.loginDM,                                               // '/cgi-bin/rad_user_dm'
  params: {
    ip: ip,
    username: _this.userInfo.username,
    time: time,
    unbind: unbind,
    sign: sha1(time + _this.userInfo.username + ip + unbind + time)
  },
  success: function (res) { finishReq += 1; successMsg = _this.translate(res); },
  error:   function (res) { /* 失败弹窗 */ }
});
```

**与 LinkUp 的差异只有三处**，都不影响这个功能是否成立：

- 官方在双栈部署（`doub`）下会发两次请求，分别针对 IPv4 和 IPv6。LinkUp 不处理 IPv6。
- 官方的 `username` 是 `userInfo.username`，见 §3.3。
- 官方用 `confirm: getOnlineDevice` 在成功后刷新设备列表。LinkUp 丢了这个刷新（见 §1.3）。

面板的开关是 `CREATER.useOnlineDeviceMgr`，且在登录返回 `ecode === 'E2620'`（设备数超限）时自动弹出。该字段的实际取值未找到任何快照。

### 2.2 官方在 DM 之后自己会轮询复查在线表

**这是本次调查最重要的发现之一。**

【一手·官方】`_logoutDm` 的完整控制流（`Portal.js`，2020 代版本）：

```js
var checkNum = 3;          // 检查次数
var finishReq = 0;         // 已完成请求
var noPending = function () { return !doub && finishReq === 1 || doub && finishReq === 2; };
...
sendLogout(nowType === 'ipv4' ? ipv4 : ipv6);
if (doub) sendLogout(nowType === 'ipv4' ? ipv6 : ipv4);

var sendCheckOnline = function sendCheckOnline() {      // 查询在线表
  _this.ajax.jsonp({
    url: _api.info,                                     // '/cgi-bin/rad_user_info'
    params: { ip: _this.userInfo.ip },
    error: function (res) {                            // ← rad_user_info 报「不在线」才走这里
      logoutClose();
      if (obj.success) obj.success(successMsg);          // 宣布成功
      if (!obj.success) _this.toIndex();
    }
  });
};

_this.checkOnlineTimer = setInterval(function () {
  checkNum -= 1;
  if (noPending()) sendCheckOnline();                   // 轮询发起在线表复查
  if (checkNum === 0) { sendCheckOnline(); logoutClose(); }   // ← 无条件收尾，不看结果
}, 1000);
```

**DM 请求自己的响应只被用来显示一句提示文案（`successMsg`），从不参与成功判定。** 这直接说明 `rad_user_dm` 的 `error: "ok"` 在官方实现里**没有信息量**——它只说明「请求被受理」。

`matthewlu070111/smart-srun` 的注释把这一点说得更直白（【一手·源码】）：

> A gateway that says "ok" has said something about itself, not about whose session is now on the line.

> **这套复查方式不能照抄。**
>
> 上面的 `params: { ip: _this.userInfo.ip }` **传的是调用者自己的 IP**，所以它只证明「我自己下线了」，**证明不了别人被踢下线**。另外 `checkNum === 0` 那一支无条件关闭弹窗、不看复查结果，官方 UI 上的「注销完成」在复查没能确认时同样会显示。
>
> 是否有部署把复查改成「不带 `ip`、按请求来源 IP 判定」——见 §9，**未找到能引用的公开证据**。即便有，判定对象仍然是调用者自己。
>
> **判定「目标是否下线」要用能识别目标身份的判据**：账号自己的在线设备表。踢完再拉一次 `rad_user_info`，看目标地址还在不在里面。这不新增协议面，也让判定事实和 UI 上那一行是否消失变成同一个事实。

同一项目的 `core/internal/application/terminal.go:32-51` 实现了 `verifyLogout`：`MaxTerminalAttempts` × `TerminalIntervalSeconds` 的有界重试确认，失败时返回 `domain.CodeConflict, "网关接受了登出请求，但这条线路上仍有在线会话"`。

### 2.3 DM 下线是官方承认的合法能力

【一手·官方】官方 `lang.js` 错误码表里有一整段「下线来源」（E4xxx）：

| 错误码 | 官方文案 |
| --- | --- |
| E4101 | 来自radius模块的DM下线（挤出在线表） |
| E4102 | 来自系统设置（8081）的DM下线 |
| E4103 | 来自后台管理（8080）的DM下线 |
| **E4104** | **来自自服务（8800）的DM下线** |

`E4104` 说明用户自助 Portal 发起的 DM 是被官方归类为**合法下线来源**的，与系统设置、后台管理并列。端口号（8800）来自文案本身。

同时 `E6528`「您已经被服务器强制下线」是**被踢方**会看到的码，`E6504`「注销成功，请等1分钟后登录」是 DM 成功后的收敛期提示。

### 2.4 没有专用踢设备端点

【一手·官方 + 一手·源码】在 5 份不同学校的 Portal 前端快照和 25 个开源客户端源码里，以下候选端点名**零命中**：`portal_show_online`、`portal_user_device`、`user_device_list`、`portal_device_offline`、`portal_force_logout`、`portal_user_dm`、`portal_user_offline`。

深澜管理端（srun4k，`8080` 端口）有专门接口，但需要管理员凭据，用户端不可行（【一手·源码】`luguohuakai/srun` 的 `sdks/OnlineV2.php`）：

```php
onlineDrop($user_name, $drop_type, $rad_online_id)  => POST api/v2/base/online-drop
batchOnlineDrop($user_name)                         => POST api/v2/base/batch-online-drop
// 鉴权：POST api/v2/auth/get-access-token  body {appId, appSecret} => access_token
```

**注意机制差异：管理端按 `rad_online_id` 下线，用户端 `rad_user_dm` 按 `ip` 下线。** `rad_online_id` 虽然在 `rad_user_info` 的设备列表里，但没有任何用户端端点接受它。

## 3. 协议事实：`rad_user_dm`

### 3.1 端点与参数

【一手·官方】必需参数就是 5 个，官方 `_logoutDm` 的 `params` 对象和 `sign` 公式里的输入完全对应：

| 参数 | 值 | 备注 |
| --- | --- | --- |
| `ip` | 目标设备 IP | **可以不是调用者自己的 IP** |
| `username` | `rad_user_info` 的裸 `user_name` | 见 §3.3 |
| `time` | `Date.parse(new Date()) / 1000`，**秒** | 官方用秒 |
| `unbind` | `1` | 见 §3.4 |
| `sign` | 见 §3.2 | |
| `callback` | JSONP 回调名 | 2020 代由 jQuery 层追加；`adamanteye/tunet-bash` 用 POST + `--data-urlencode` 也工作 |
| `_` | 毫秒时间戳 | 缓存击穿，**不是协议字段** |

【一手·官方】**不需要 `mac` 参数。** 官方 `_logoutDm` 的 `params` 里没有 mac，老代官方 `dm()` 的文档注释 `params [@ip,@username,@time,@sign]` 也没有。

【一手·官方 + 一手·源码】**是匿名 CGI**，不需要 cookie、stoken 或会话。所有实现都是裸 GET。

### 3.2 签名公式

【一手·源码 ×14 + 一手·官方 ×2】跨 C / Go / Rust / Python / C# / C++ / Bash 与两代官方 Portal JS 共 16 份独立实现，公式**完全一致**：

```text
sign = lowercase_hex(SHA1(time + username + ip + unbind + time))
```

拼接特征：

- 无分隔符，首尾都是 `time`。
- `unbind` 以**字符串**参与（`"1"`），不是数字。
- hex **一律小写**。没有任何实现用大写。
- `time` 在 query 参数和签名串里是**同一个值**。`Mythologyli/zju-web-login` 独立取了三次钟、跨秒时不自洽——那是 bug，LinkUp 用单一变量是这批里最干净的写法。
- **没有任何实现在拼接前做 URL 编码或字符集转换。** LinkUp 的 Latin-1 编码在这一点上没有先例可循；但对 ASCII 用户名加 IPv4 地址，Latin-1 与 UTF-8 结果完全相同，因此不构成实际分歧。

`time` 单位在不同实现里分裂为秒（官方与多数实现）、毫秒（6 个实现）、十分之一秒（2 个实现）。**没有任何一份资料明确说明协议要求哪种单位。** 官方用秒，LinkUp 用秒，两者一致。

### 3.3 `username` 的取值：官方与多数实现用裸账号名

【一手·官方】2020 代 Portal 在处理 `rad_user_info` 响应时这样存字段（`Portal.js:2279-2285`，注释为官方原文）：

```js
_this3.userInfo.mac      = res.user_mac;                             // String 用户 Mac 地址
_this3.userInfo.username = res.user_name;                            // String 用户账号（不会携带域）
_this3.userInfo.realname = res.real_name;                            // String 真实姓名
_this3.userInfo.domain   = res.domain ? "@".concat(res.domain) : ''; // String 用户域 Ex: 域为账号 xingrong@cmcc 中的 @cmcc
```

**注释明确写着 `user_name`「不会携带域」，域被单独存进 `userInfo.domain` 字段。而 `_logoutDm` 用的 `username: _this.userInfo.username` 取的是裸名，没有拼 `domain`。**

【一手·源码】多个独立实现也用 Portal 返回的账号名：

- `matthewlu070111/smart-srun` `core/internal/auth/result.go` 的 `Identity.SessionUsername` 注释：*"is `user_name` exactly as reported (without synthesizing a separately returned realm). **The signed DM logout uses this name**"*
- `zhangui1/ubuntu-campus-net-autologin` `campus_net/client.py` 的 `logout()` 读 `rad_user_info` 的 `user_name`，注释：*"portal username differs from configured username: portal=%s configured=%s; logout will use portal username"*
- `JBNRZ/srun-login` `login.py:156`：`username = status.get("user_name") if status.get("user_name") else self.username`
- `spencerwooo/bitsrun-rs`、`so1ve/bitgateway`、`hduhelp/hdu-cli`、`LYCaikano/lzunet`、`wensssl/auto_gateway_bnu` 等共 11 个实现同样从 Portal 取

【一手·源码】`LYCaikano/lzunet.py:184-188` 的注释是最直接的表述：*"用户名用裸用户名（不带域后缀），与前端 `_logoutDm` 一致"*。

LinkUp 已经解析了这个字段但没有用：`lib/utils/RadUserInfo.dart:96` 有 `@JsonKey(name: 'user_name') final String? userName`，而 `lib/utils/AuthenticationAttempt.dart` 的 `logout` 与 `kickDevice` 传的都是 `config.authenticatedUsername`。**这是 LinkUp 与上述实现的做法不同，不等于目标部署一定要求裸名**——见 §7 的 D3。

服务端确实有独立的用户名错误通道：`user_name_error`（`PengweeWang/SRunAuth` 实测 token 表）和官方码 `E6501`「用户名输入错误」。

【推测】带域时 `sign` 仍然自洽（LinkUp 用同一字符串同时参与签名和 query），所以请求不会因签名不匹配被拒。可能的失败路径是服务端在用带域账号匹配在线表时走了另一个分支却仍返回 `ok`。**这一段是推测，没有直接证据。** 可验证的办法见 §8。

### 3.4 `unbind` 语义

【一手·官方】存在版本分歧：

- **老代官方**（2020 年前）：`unbind` 默认 `0`，仅当 `portal.MacAuth` 为真时置 `1`。
- **2020 代官方**：`var unbind = 1;` 硬编码，注释「优先使用指定 IP」。

【一手·源码】`LYCaikano/lzunet.py:10,181` 的逆向注释解释了 `unbind=1` 的真实作用：

> 注销（MacAuth 无感知环境下必须用此接口，unbind=1 解绑 MAC）
> 本校门户开启了 MacAuth 无感知认证（`CONFIG.portal.MacAuth=true`），前端此时走 DM 注销 `/cgi-bin/rad_user_dm`（unbind=1 同时解绑 MAC），**否则普通 `srun_portal?action=logout` 虽返回 ok，会话会被无感知认证立刻重建**

跨实现统计：`unbind=1` 被 18 个实现采用，`unbind=0` 被 6 个采用（`HofNature/SRunPy-GUI` 三兄弟、`CPT-KK/BitLogin`、`qhlai/hitsz_srun_autoconnect`、`wensssl/auto_gateway_bnu`）。**不存在 `unbind=2`。**

**没有任何一份资料说 `unbind=1` 会「只解绑而不真正踢掉」。** 两种取值都有正常工作的实现。LinkUp 选 `1` 与官方 2020 代一致，属主流。

【推测】踢别人时 `unbind=1` 会顺带解绑对方的 MAC 绑定，对被踢者有副作用；踢自己且本机依赖无感知认证时才需要 `1`。这是语义推断，不是资料结论。

### 3.5 成功响应不唯一

【一手·源码 ×9 + 一手·官方】`rad_user_dm` 的成功值跨三代部署不一致：

| 实现 | 成功判定 | 响应形态 |
| --- | --- | --- |
| 老代官方 `jquery.srun.portal.js:480-496`（UESTC / ZJU 两份） | `if (response.error == "logout_ok")` | JSONP `{error:"logout_ok"}` |
| `CPT-KK/BitLogin` `BitSrunUser.cpp:228` | `error == "logout_ok"` | JSONP，**把 `ok` 判为失败** |
| `wensssl/auto_gateway_bnu` `dm.py:59` | `if response == "logout_ok"` | **裸字符串**，无 JSONP 无 JSON |
| `HofNature/SRunPy-OpenWRT` `SRunLite.py:249` | `user_dm_res == 'logout_ok'` | **裸文本** |
| `Mythologyli/zju-web-login` `weblogin.py:271-289`（浙大实测） | `'logout_ok' in res.text` / `'not_online_error' in res.text` | 对**原始响应体做子串匹配** |
| 2020 代官方 `Portal.js` 通用 `_request` | `if (res.error === 'ok')` | JSONP `{error:"ok"}` |
| `PengweeWang/SRunAuth` `client.py:294-306` | 五个字段任一 ∈ `{ok, LogoutOK}`，或 `code==0` 且 `error ∈ {None,"",ok}` | JSONP，容错极宽 |
| `45gfg9/srun-c` `srun.c:704` | 接受 `ok` **或** `not_online_error` | JSONP |

【一手·官方】官方 `lang.js` 同时维护一批符号化 token，比 `E####` 更常出现在 `error` 字段里：`LogoutOK`（DM 下线成功）、`NotOnlineError`、`YouAreNotOnline`（该设备不在线）、`SignError`、`TimestampError`、`MissingRequiredParametersError`。

**LinkUp 只认 `ok`**，并且强制走 JSONP 提取（`_extractJsonFromJsonp`）。**本 PR 不改这个判定**（§7 的 D1）。在返回 `logout_ok` 或裸文本的部署上，它会把成功报成失败——而且因为裸文本无法通过 JSONP 提取，`_extractJsonFromJsonp` 抛异常后被 `catch (e)` 吞掉，返回 `false`。

**注意反证**：用户报告的现象是「App 弹了绿色『已踢』」，这说明用户所在部署返回的是 `ok`（2020 代语义）。所以这条不是当前故障的原因，但换部署会静默误判。

### 3.6 失败原因往往不在 `error` 字段里

【一手·官方 + 一手·源码】两个独立实现给出了同样的字段优先级：

- 官方 `Portal.js:3055-3097` `translate(res)`：`ploy_msg`（非 `E0000` 开头）→ `ecode === 'E2901'` 时用 `error_msg` → `ecode` → `error_msg` → `res.error`
- `PengweeWang/SRunAuth` `client.py:151-158` `response_message()`：`("error_msg", "suc_msg", "error", "res", "message")`

**`error_msg` / `ecode` 优先于 `error`。** 只读 `error` 会丢掉 `E6502`（注销时发生错误，或没有帐号在线）、`E6527`（当前设备不在线）、`E6501`（用户名输入错误）、`E6522`（客户端时间不正确）这些真正的原因码。**本 PR 已按这个优先级解析并把原因透传到 UI**（§7 的 D2），实现见 `lib/utils/SrunClient.dart` 的 `DmResult.reason`。

【一手·源码 ×9】所有实现都只用 HTTP 层的传输成功/失败两级区分，业务失败一律走 `200` + body。这是协议现实，LinkUp 用 `http` 包读 JSON 与之一致，**问题不是「读错了字段」，而是「读的字段不足以判断是否生效」。**

## 4. 失败模式：「返回 ok 但没真踢掉」逐条判定

| 候选原因 | 判定 | 依据 |
| --- | --- | --- |
| 服务端用请求源 IP 覆盖了 `ip` 参数 | **否定** | 官方 Portal 就是传目标设备的 IP 去的；无任何资料提到源 IP 覆盖 |
| 需要先建立 Portal 会话（cookie）才能踢 | **否定** | `rad_user_dm` 是匿名 CGI，9 个实现都是裸 GET |
| 需要 `mac` 参数 | **否定** | 官方 `params` 里没有 mac；`hitsz-autonet/AGENTS.md` 写明「MAC disagreement is notify-only, never a blocker」 |
| 该校部署禁用了用户侧踢设备 | **基本否定** | 官方码表有 `E4104`「来自自服务（8800）的 DM 下线」；官方 Portal 内置在线设备管理 UI |
| `unbind=1` 只是解绑绑定而不踢会话 | **未找到支持证据** | 18 个实现用 `1` 且工作正常；无任何资料这样描述它 |
| **`username` 多了 `@域` 后缀** | **未否定** | 见 §3.3。6 份官方 JS + 11 个实现一致用裸名；服务端另有 `user_name_error` / `E6501` 通道。**这是做法差异，不是已确认的失败原因** |
| **目标设备自动重连** | **机制已证实** | 官方码表有 `E3101` 心跳包超时、`E3007` 超时、`E3010` 无流量超时、`E2405` Session-Timeout；`rad_user_info` 带 `keepalive_time` 字段；DM 只置离线不封禁 |
| **`online_device_detail` 里的 IP 是僵尸记录或不属本账号** | **机制成立** | 该字段无 `add_time`、无 MAC、无 `is_online`；对比 `/v1/auth/device/get` 多出 `user_mac` / `add_time` / `is_online`，`SRunAuth` 显式跳过 `is_online is False` |
| `time` 单位或时钟偏移导致签名被拒 | **低，但须排除** | 官方 `E6522`「客户端时间不正确…时差超过 2 小时」；LinkUp 的秒级换算与官方一致 |

### 4.1 按可能性排序

1. **`username` 带了 `@域` 后缀。** 置信度**中**。可观察到的事实是「LinkUp 与官方和 11 个实现取值不同」；「因此服务端匹配在线表走了另一分支却仍返回 `ok`」是【推测】，没有直接证据。
2. **只判 `error == 'ok'`、不做踢后验证。** 置信度**高**。这**未必是踢不掉的原因，但是「弹了成功却没踢掉」被掩盖的直接原因**——在这个实现下，「没踢掉」在 UI 上根本不可观测。**本 PR 已修掉这一项**（§7 的 D4），但它只让「没踢掉」变得可观测，不能让踢设备真的生效。
3. **目标设备自动重连。** 置信度**中高**。DM 只置离线不封禁。若目标设备跑着自动认证客户端（LinkUp 自己就是），它会立刻重连。
4. **目标 IP 是过期记录或不属于本账号。** 置信度**中**。`online_device_detail` 不带 `is_online`，无法从字段本身分辨。
5. **`unbind=1` 在非 MAC 认证部署上语义不对。** 置信度**中低**。有 6 个实现用 `0` 正常工作，但没有任何实现记录了「试过 0 不行才改 1」的过程。
6. **`error: "ok"` 是校验前的短路返回。** 置信度**中低**。`SzuDesktopTeam/szudesktop` 的测试注释说明深澜在 `ip_already_online` 场景下于「校验账号密码和 `ac_id` 之前」就返回 `error:"ok"`。**没有直接证据表明 DM 端点也这样短路。**

### 4.2 踢设备本来的天花板

【一手·官方】`E3008`「连线数超额，挤出在线表」、`E2621`「已经达到授权人数」、`E2620Tips`「在线设备数量已达上限，请注销选择并注销已在线设备」。

【一手·官方】5 份 Portal 快照 + 25 个客户端源码里，**没有任何「踢掉最早上线设备」的用户端接口**。管理端只有 `batch-online-drop`（整号下线）。多数学校的策略是「后上线挤掉先上线」。

【一手·官方】`srun.com/cn/list/info?id=178`（2025 版自助服务平台官方公告）的功能清单是产品设置 / 记录查询 / 账号设置，**通篇没有在线设备管理或强制下线**。用户自助踢设备是可选部署能力。

已知会限制效果的官方说明：

- 山东大学 `info.sdu.edu.cn/info/1113/2060.htm`：**「自助服务只能下线本地校区在线的终端」**
- 西北农林科技大学 `nic.nwafu.edu.cn/bzzx/fwznZ/6abab3b7bc454fd094df4a6d7a79f036.htm`：**「只能在校园网环境访问」**

## 5. 错误码勘误

调查中拿到的官方 `lang.js` 错误码表与 `docs/深澜认证协议技术文档.md` §10 存在若干出入。**注意各校可以定制语言包**，下表是「官方默认表 vs LinkUp 文档」的差异，不保证用户所在部署一致。

| 错误码 | 官方 `lang.js` | LinkUp 文档 §10 | 备注 |
| --- | --- | --- | --- |
| `E2620` | **已经在线了** | 同时在线设备数超限 | 真正的并发超限码是 `E2621`「已经达到授权人数」/ `E3008`「连线数超额」 |
| `E2821` | **官方码表中不存在** | IP 不在线 | 语义对应 `E6527`「当前设备不在线」/ token `not_online_error` |
| `E27xx` 整段 | **官方码表中不存在** | — | |
| `E2833` | IP 不在 DHCP 表中，需要重新拿地址 | IP 已被占用 | |
| `E2901` | 第三方认证接口返回的错误信息 | 密码错误或账号不存在 | |
| `E2602` | 您还没有绑定手机号或绑定的非联通手机号码 | 认证设备响应超时 | |
| `E6502` | **注销时发生错误，或没有帐号在线** | 未收录 | DM 失败的官方文案 |
| `E6504` | 注销成功，请等 1 分钟后登录 | 未收录 | DM 成功后的收敛期 |
| `E6522` | 客户端时间不正确（时差超过 2 小时） | 未收录 | 对应签名 `time` 的时钟风险 |
| `E6527` | **当前设备不在线** | 未收录 | DM 目标不在线的官方码 |
| `E6528` | 您已经被服务器强制下线 | 未收录 | 被踢方会看到的码 |
| `E4104` | **来自自服务（8800）的 DM 下线** | 未收录 | 用户侧 DM 是官方承认的合法来源 |

与踢设备直接相关的 `E6502` / `E6503` / `E6504` / `E6527` / `E6528` 整组官方 DM 语义错误码，LinkUp 的 `SrunLogin` 错误分类没有覆盖。

## 6. 跨实现交叉验证

【一手·源码】共读了 25 个有实质注销实现的开源深澜客户端（Go / Python / Rust / C++ / C / C# / Bash）。npm 上不存在深澜库，OpenWrt 官方 feed 没有 srun / drcom 包。

**真正实现了「从设备列表踢任意目标」的只有 3 家**：

| 项目 | 做法 |
| --- | --- |
| `PengweeWang/SRunAuth` | `devices` 子命令 + `--auto-kick oldest\|newest\|all` + `--kick-ip`。设备列表取自 `/v1/auth/device/get`，失败回落 `online_device_detail`。批量就是循环调 DM，**没有批量参数** |
| `Fun10165/hitsz-autonet` | 唯一有归属校验的完整闭环：踢之前先 `rad_user_info?ip=<目标>` 复查是否在线、`user_name` 是否等于自己、默认路由是否变化；踢完 3 次 `sleep(1)` + 复查，未确认就报 `"Srun accepted logout for %s, but the session is still online."`。取舍是宁可漏踢也不误踢 |
| `DustinChen04/hitsz-srun-login` | `logout -ip <ip>` 手动 + `list-devices`。另有走学校自建门户 `/home/delete?id=&user_mac=` 的路径（需 CAS + CSRF，通用性低） |

**参数上没有任何区别。** 四个实现（含 LinkUp）的参数集和签名公式完全相同，唯一变化是 `ip` 填谁的值，`username` 始终是发起者自己的账号。踢人和注销在协议层是同一个请求。

**踢完要不要二次确认，业界 3 : 22 分裂**：只有 `smart-srun`（有界重试确认）、`hitsz-autonet`（固定 3 次复查）、`SRunAuth`（重登成功当隐式证据）做了；`srun-c` / `bitsrun-rs` / `bitgateway` 把「本来就不在线」当幂等成功；其余 20 个（含 LinkUp）完全不做。**没有任何实现对注销本身做指数退避重试，重试的只有确认那一侧。**

**唯一字段级方言**：HITSZ 两家用 `user_ip` 而非 `ip` 作参数名（签名仍按 `ip` 参与），其余 20+ 家全用 `ip`。

**一条重要的反面证据**：`matthewlu070111/smart-srun`（业界最严谨的实现）的 issue #14 至今 open，标题「[Feature]: 考虑新增对深澜自服务页面的适配」，原文：

> 有些学校确实存在这种情况：新设备登录必须要去自服务页面注销老设备，要不然登录不上去
> 可能需要去实地抓一下自服务页面的包，并且增加 TLS 的支持

同一项目在 `core/internal/auth/authworker.go:456-459` 明确**拒绝**跨账号自动下线：

```go
if !identity.MatchesExpected && prepared.intent != auth.IntentManual {
  return prepared.failed(a, domain.Errorf(domain.CodeOnlineIdentityMismatch,
    "这条线路上在线的是另一个账号，自动维护不会将其下线"), domain.AuthVerifiedOther, identity.Username)
}
```

**在全部 24 个仓库的 issue 里搜索 `rad_user_dm` / `踢设备`，标题与正文全部 0 命中。** 跨设备踢人在开源社区基本没人踩坑，因为几乎没人实现它。也没有找到任何公开的 `rad_user_dm` 抓包（pcap 或分析文章）。

## 7. LinkUp 现状清单

下面三类分开的依据是**证据强度**：只有能从仓库代码直接读出来的算第一类；「别的实现这么做」只能说明做法有差异，不能说明目标部署一定要求它——那是第三类。

### 本 PR 已处理

| # | 问题 | 位置 |
| --- | --- | --- |
| D2 | 只看 `error`，不回落 `res` / `ecode` / `error_msg`，失败时用户看不到原因 | `lib/utils/SrunClient.dart` |
| D4 | 踢完不做任何确认，`error == 'ok'` 直接被当成已下线 | `lib/utils/AuthenticationAttempt.dart` |
| D5 | 踢出成功后不刷新设备列表，要等下一轮轮询 | `lib/navigation/MainNavigation.dart` |
| D8 | `rad_user_dm` 的 URL、query、`unbind`、`sign` 无任何测试断言 | `test/srun_client_test.dart` |

### 与多数实现做法不同，是否构成偏差未验证

| # | 差异 | 证据 | LinkUp 的做法 |
| --- | --- | --- | --- |
| D1 | 成功值取值 | 9 个实现要求 `logout_ok`，另有实现认 `LogoutOK` 或裸文本，其中一份明确把 `ok` 判为失败 | 只认 `ok` |
| D3 | `username` 取值 | 官方 Portal 与 11 个实现用 `rad_user_info` 返回的裸 `user_name`；`ucas_portal_login` 拼 `username@domain` | 用配置值 `authenticatedUsername`，是否带 `@域` 取决于用户填没填运营商类型 |
| D6 | `not_online_error` | 部分实现把它当幂等成功 | 只认 `ok`，`not_online_error` 报失败 |
| D7 | 目标 IP 校验 | `logout` 侧会校验地址非空 | `kickDevice` 只 trim 后判空，不校验归属与格式 |

**这四条不是已确认的缺陷。** 目标部署返回什么、要求什么，只有实机抓包能确定；本 PR 不动它们。

### 无法判定（学校方言，只能实机抓包）

- `unbind` 该取 `0` 还是 `1`（18 家用 1，6 家用 0，无任何实现记录了试错过程）
- `username` 该带 `@域` 还是裸名（见 D3）
- `ip` 还是 `user_ip`（HITSZ 方言）
- `time` 用秒 / 毫秒 / 十分之一秒
- `rad_user_dm` 相对 `srun_portal?action=logout` 是否必需（取决于学校是否开 MacAuth 无感知认证）
- **踢设备在目标部署上是否真能跨设备生效**——必须实机验证

## 8. 建议的验证顺序

调查无法在只读条件下确定用户部署的实际行为。下一步应当先诊断再改代码。

1. **先做诊断，把「真没踢掉」和「踢掉了但没验证」彻底分开。** 踢完拉一次 `rad_user_info`，看 `online_device_detail` 里还有没有目标地址。这一步能把所有候选原因一刀切成两半，优先做。**不要用 `rad_user_info?ip=<目标IP>` 判据**——那个 `ip` 是可选参数，不拼进查询串的部署会回答调用者自己，得到假阳性（见 §2.2）。
2. **抓 LinkUp 实际发出的请求，比对 `username=` 是否含 `@`。** 官方 Portal 是可用的对照：用浏览器打开官方 Portal 登录，点它自己的「踢」按钮，对比两边 URL 的 `username` / `unbind` / `ip` 三个值。这是分辨学校方言最直接的办法。
3. **换一个裸 `user_name` 重试。** 如果目标学校门户确认用裸名，改用 `rad_user_info` 的 `user_name` 签名后重发，看目标是否掉线。
4. **对照实验 `unbind`。** 把 `unbind` 改成 `0` 重算签名发一次（老代官方前端行为）。改 `unbind` 必须同步改签名输入。
5. **观察是否自动重连。** 被踢设备若跑着自动认证客户端，DM 后每 2 秒拉一次 `rad_user_info` 看目标地址是否重新出现，持续 60–120 秒。若出现「掉线 → 又在线」的锯齿，则「踢设备」在该场景下本来就没有产品意义。
6. **确认该部署是否开放用户侧 DM。** 官方 Portal 能踢、LinkUp 不能踢 → 差异在参数；官方也不能踢 → 该部署禁用了此能力。

如果后续要改代码，按 `docs/深澜认证协议技术文档.md` 的定位，改协议实现前先核对本文与真实 Portal 响应。

## 9. 未能证实的部分

| 问题 | 状态 |
| --- | --- |
| `rad_user_dm` 的公开抓包（pcap 或分析文章） | **未找到**。已用 16 份请求构造替代 |
| 「返回 ok 但设备还在线」的社区实测报告 | **未找到**。24 个仓库 issue 零命中，中文论坛无 |
| `rad_user_dm` 传非本账号 IP 时的错误码 | **未找到** |
| `online_device_detail` 的刷新延迟 / TTL / 僵尸记录清理策略 | **未找到任何资料** |
| 深澜是否有「DM 后禁止重连」机制 | **未找到**，证据倾向「没有」【推测】 |
| 是否存在部署在 Web 侧（`/v1/*`）限权但保留 `/cgi-bin/rad_user_dm` | **未找到** |
| `CREATER.useOnlineDeviceMgr` 在各校的实际取值 | **未找到**（公开的 Portal 部署快照里不含这一个字段） |
| 管理端 `drop_type` 枚举含义 | **未找到**（官方 apifox 文档需密码） |
| `8800` 端口自助 Web 应用的内部下线接口 | **未取证**（Portal 内置面板走同 origin 的 `/v1/*`，不经过 8800） |
| DM 端点是否支持 IPv6 目标、或接受 `mac` 作键 | **未找到** |
| `srun_portal` 是否有并发登录控制参数 | **未找到**（4 份 Portal.js 参数字面量无 `max_login` / `kick_oldest` / `force_kick`；`operator` 字段在 Srun 侧是移动运营商，与踢旧会话无关） |
| `error` 取值 `Rad_user_dm_error` | **不存在于公开世界**（GitHub 全库 0 命中），不要依赖 |

## 10. 来源

### 官方前端（一手，未混淆产物）

| 来源 | 提供的事实 |
| --- | --- |
| <http://139.155.140.234:4821/static/themes/pro/js/Portal.js> | 活的 2020 代部署实例。`_logoutDm`（`sendLogout` + `sendCheckOnline` + `checkNum = 3` 轮询确认）、`userInfo.username = res.user_name` 与「不会携带域」注释、端点常量表、`translate()` 字段优先级 |
| <http://139.155.140.234:4821/static/themes/pro/js/lang.js> | 官方 `E####` 全表与符号 token（`LogoutOK`、`E6502`、`E6504`、`E6522`、`E6527`、`E6528`、`E4104`） |
| <https://raw.githubusercontent.com/hduhelp/hdu-cli/main/pkg/srun/Portal.js> | 同代 `Portal.js` 副本，作者 `xr@srun.com`。`OnlineDeviceManager` 面板、`getOnlineDevice`（`/v1/srun_portal_online`）、`useOnlineDeviceMgr` 开关 |
| <https://raw.githubusercontent.com/leo2www/uestc-shenlan/main/test/电子科技大学_files/jquery.srun.portal.js.download> | 老代官方。`if (response.error == "logout_ok")`、`unbind` 仅在 `portal.MacAuth` 时置 1 |
| <https://srun.com/cn/list/info?id=178> | 2025 版自助服务平台官方功能公告（**不含**在线设备管理） |
| <https://www.drcom.com.cn/detail/NoRP13zB> | Dr.COM 官方错误码页**无 `E####` 段**，作为「深澜错误码无官方公开文档」的反证 |

### 学校官方页面（一手）

- 西北农林科技大学《校园网用户自助下线说明》：<https://nic.nwafu.edu.cn/bzzx/fwznZ/6abab3b7bc454fd094df4a6d7a79f036.htm>
- 山东大学自助服务说明（含「只能下线本地校区在线的终端」）：<https://info.sdu.edu.cn/info/1113/2060.htm>

### 开源实现（一手源码或注释）

- <https://github.com/matthewlu070111/smart-srun> —— `core/internal/application/terminal.go:32-51` `verifyLogout`；`core/internal/auth/result.go` `SessionUsername`；`core/internal/auth/gateway.go:27-35` 端点选错的后果；`core/internal/auth/authworker.go:456-459` 拒绝跨账号下线；issue #14
- <https://github.com/PengweeWang/SRunAuth> —— `srun_auth/client.py:122-158` 实测 token 表与字段优先级；`:217-334` 设备列表两种来源的字段差异与 `is_dm_success`；`:608-783` 定向踢与 `handle_overlimit`
- <https://github.com/Fun10165/hitsz-autonet> —— `AGENTS.md` 踢设备四前置条件、MAC notify-only；`hitsz_net.py` 归属校验与踢后复查
- <https://github.com/DustinChen04/hitsz-srun-login> —— `portal.go` 学校自建门户 `/home/delete` 路径
- <https://github.com/zhangui1/ubuntu-campus-net-autologin> —— `campus_net/client.py` 用 portal `user_name` + 踢后 `rad_user_info` 校验
- <https://github.com/LYCaikano/lzunet> —— `lzunet.py:10,181-198` MacAuth 无感知认证与 `unbind=1` 的逆向注释
- <https://github.com/CPT-KK/BitLogin> —— `src/BitSrunUser.cpp:209-241` 把 `ok` 判为失败
- <https://github.com/wensssl/auto_gateway_bnu> —— `dm.py` 裸文本 `logout_ok` 与 `unbind=0`
- <https://github.com/Mythologyli/zju-web-login> —— `weblogin.py:64,271-289` 浙大实测响应体子串匹配
- <https://github.com/WangYihang/srunc> —— `rad_user_info` 响应模型（`rad_online_id` 为 key 的对象、THU 测试向量）
- <https://github.com/luguohuakai/srun> —— 管理端北向 API（`sdks/OnlineV2.php`、`sdks/UserV2.php`）
- <https://github.com/SzuDesktopTeam/szudesktop> —— `internal/portal/srun_test.go` 关于「`error:"ok"` 是校验前短路返回」的注释

### LinkUp 自身（只读定位）

| 路径 | 行 | 内容 |
| --- | --- | --- |
| `lib/utils/SrunClient.dart` | 234-268 | `dmLogout`：签名、参数、唯一成功判定 `error == 'ok'` |
| `lib/utils/ConfigUtil.dart` | 70-71 | `authenticatedUsername => '$username@$userType'` |
| `lib/utils/AuthenticationAttempt.dart` | 91-113 | `logout` 与 `kickDevice` 的差异（`reset()`、`_ipFrom` 校验） |
| `lib/utils/RadUserInfo.dart` | 30-31, 96 | `user_name` / `domain` 已解析，踢设备路径未用 |
| `lib/utils/RadUserInfo.dart` | 169-180, 193-215 | `onlineDeviceDetail` 返回以 `rad_online_id` 为 key 的 `Map`；`OnlineDevice` 五个字段与一手资料一致 |
| `lib/navigation/MainNavigation.dart` | 87-91, 236-266 | 状态流驱动 `_userInfo`；`_kickDevice` 不刷新列表 |
| `lib/page/OverViewPage.dart` | 64-71, 73-109, 530-550 | 按钮可见性判断、确认弹窗、按钮渲染 |
| `lib/utils/AuthenticationCoordinator.dart` | 434-457 | `logout` 与 `kickDevice` 的编排差异 |
| `docs/深澜认证协议技术文档.md` | 53, 219-227, 229-247 | 端点表、DM 注销、错误码表 |

**行号对应调查当时的 `master`。** 本 PR 之后 `docs/深澜认证协议技术文档.md` 新增了 §9.1「踢其他设备」，上面这条观察已不成立；其余路径的行号会随改动漂移，请按符号名定位。§10 的错误码表与官方 `lang.js` 存在出入，见 §5。
