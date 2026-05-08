# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

LinkUp 是基于深澜(Srun)协议的校园网自动认证客户端，主要目标平台为 Android。核心功能：自动检测网络状态、断网自动重连、ACID 自动探测、后台保活。

## 常用命令

```bash
# 安装依赖
flutter pub get

# 代码静态分析
flutter analyze

# 构建 Android APK（Release）
flutter build apk --release

# 运行测试
flutter test

# 生成 JSON 序列化代码（修改 RadUserInfo 后需要）
flutter pub run build_runner build

# 更新应用图标
flutter pub run flutter_launcher_icons
```

## 架构概览

### 页面导航

`main.dart` → `AuthWrapperPage`（首次配置检测）→ `MainNavigator`（主体）

- `AuthWrapperPage`: 检查 `ConfigUtil.configExists()`，无配置时弹出 `FirstSetupDialog`，有配置时直接显示 `MainNavigator`
- `MainNavigator`: 使用 `IndexedStack` + `NavigationBar` 管理两个页面（概况/设置），**同时是登录逻辑和网络监控的核心控制器**
- `OverviewPage`: 纯展示组件，所有状态通过构造函数 props 传入（`isOnline`, `userInfo`, `statusMessage` 等），下拉刷新触发 `onRefresh` 回调
- `SettingsPage`: 组合 `AccountCard`、`SystemSettingsCard`、`NetworkConfigCard`、`LogViewerCard`

### 登录流程（核心链路）

`MainNavigator._doLogin()` 编排完整的登录流程：

1. `NetworkUtil.isWifiConnected()` - 检测 WiFi 连接
2. `ConfigUtil.loadConfig()` - 读取本地配置（用户名、密码、ACID、认证服务器地址）
3. `SrunClient.getUserInfo()` - HTTP GET → JSONP 解析，获取 IP 和在线状态
4. `SrunClient.getChallenge()` - 获取认证 token（challenge）
5. `SrunLogin.srucPortalLogin()` - 执行登录：
   - `SrunEncrypt.Hmd5()` - HMAC-MD5 密码加密
   - `SrunEncrypt.getInfo()` - XXTEA 加密 + 自定义 Base64 编码用户信息
   - `SrunEncrypt.Chkstr()` + `Sha1()` - 生成校验和
   - HTTP GET 发送登录请求，解析 JSONP 响应
6. 如果开启自动 ACID，`AcidDetector` 先通过 HTTP 重定向链探测正确的 ACID 值

### 网络监控

`MainNavigator` 的 `Timer.periodic`（每 3 秒）驱动 `_checkAndReconnect()`：
- 使用 `AcidDetector.reality()` 同时检测在线状态和 ACID
- 在线 → 更新 UI 状态；离线 → 触发 `_safeLogin()` → `_doLogin()`
- 登录中（`_isLoading == true`）时跳过检查，避免并发

### 数据层

| 工具类 | 存储方式 | 用途 |
|--------|---------|------|
| `ConfigUtil` | JSON 文件 (`linkup_config.json`) | 用户名、密码、ACID、认证服务器地址 |
| `SystemSettingsUtil` | `SharedPreferences` | 后台保活、开机自启开关 |
| `LogUtil` | 文件 (`error.log`) | 运行日志 |

### 协议层

- `SrunClient`: HTTP 客户端，封装对认证服务器的三个 CGI 接口（`rad_user_info`, `get_challenge`, `srun_portal`），处理 JSONP 响应解析
- `SrunLogin`: 登录编排器，包含密码加密、请求构建、错误分类（`LoginErrorType` 枚举 + `LoginResult` 返回类型）
- `SrunEncrypt`: 纯加密工具，实现 XXTEA 加密、HMAC-MD5、SHA-1、自定义 Base64 编码
- `AcidDetector`: 跟随 HTTP 重定向链（包括 JS/Meta 跳转），从 URL 参数或 HTML 表单中提取 ACID

### 深澜协议详解

> 以下内容来源于 `深澜认证协议技术文档.md` 和 BitSrunLoginGo 项目源码分析。

#### API 接口

| 接口路径 | 方法 | 功能 | 返回关键字段 |
| :---: | :---: | :---: | :---: |
| `/cgi-bin/rad_user_info` | GET | 获取 IP、查询在线状态 | `error`("ok"=在线), `online_ip`, `client_ip`, `sum_bytes`, `sum_seconds`, `online_device_detail`(JSON字符串需二次解析) |
| `/cgi-bin/get_challenge` | GET | 获取 Token (32位十六进制随机字符串) | `challenge`, `client_ip`, `ecode`, `expire` |
| `/cgi-bin/srun_portal` | GET | 登录/注销提交 | `error`("ok"=成功), `error_msg`, `res`, `suc_msg` |
| `/v1/srun_portal_online` | GET | 查询在线设备列表 | 需携带 username 和 password 的 MD5 |
| `:8800` 或 `/site` | GET | 自服务系统 | 流量、余额、设备详情 |

**四个 API 端点的注意**：所有接口返回均为 JSONP 格式（`jQueryCallback({...})`），非纯 JSON。`online_device_detail` 字段是 JSON 字符串，需二次 `jsonDecode` 解析。

#### 四步登录流程

```
1. GET /cgi-bin/rad_user_info
   → 获取 online_ip，判断是否已在线

2. GET /cgi-bin/get_challenge?username=xxx&ip=xxx
   → 获取 challenge (32位十六进制 token)

3. 本地计算（按顺序）:
   a. hmd5 = HMAC-MD5(password, token)  // token 作为 key
   b. info = "{SRBX1}" + CustomBase64(XXTEA_Encrypt(JSON{username,password,ip,acid,enc_ver}, token))
   c. chkstr = token + username + token + hmd5 + token + acid + token + ip + token + n + token + type + token + info
   d. chksum = SHA1(chkstr)

4. GET /cgi-bin/srun_portal?action=login&username=xxx&password={MD5}hmd5&ac_id=xxx&ip=xxx&info=xxx&chksum=xxx&n=200&type=1&os=Windows+10&name=Windows&double_stack=0
   → 检查 error == "ok" 确认成功
```

**重要**: 登录后必须再次调用 `rad_user_info` 确认在线状态，仅凭 `srun_portal` 返回的 `error: "ok"` 不可靠。

#### 核心字段概念

| 字段 | 含义 | 说明 |
| :---: | :---: | :---: |
| `ACID` | 接入点 ID | 标识楼栋/区域的数字，如 1, 2, 5, 11, 15 |
| `Token/Challenge` | 认证令牌 | `get_challenge` 返回的 32 位十六进制字符串，作为 HMAC 密钥和 XXTEA 密钥 |
| `HMD5` | 加密密码 | `HMAC-MD5(password, token)` 的十六进制小写结果 |
| `Info` | 加密用户信息 | `{SRBX1}` 开头，内容为 XXTEA 加密 + 自定义 Base64 编码 |
| `Chkstr` | 校验字符串 | 格式: `token+username+token+hmd5+token+acid+token+ip+token+n+token+type+token+info` |
| `Chksum` | 校验和 | `SHA1(chkstr)` 的十六进制小写结果，用于防篡改 |

#### XXTEA 加密细节

- **模式**: ECB（电子密码本）
- **密钥**: Token 字符串按 Latin-1 编码转 uint32 小端序数组（不足 4 个补 0）
- **Delta**: `0x9E3779B9`（Go/JS 中写作 `0x86014019 | 0x183639A0`）
- **轮数**: `floor(6 + 52/(n+1))`，n = 数据块数 - 1
- **填充**: 加密时在数组末尾追加原始明文字节长度，解密时根据该值截断
- **字节序**: 全程小端序（Little Endian）
- **编码**: 所有字符串操作基于 **Latin-1 (ISO-8859-1)** 编码，不是 UTF-8

#### 自定义 Base64

- **标准字母表**: `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/`
- **深澜字母表**: `LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA`
- **实现方式**: 先用标准 Base64 编码，再逐字符映射替换（本项目）；BitSrunLoginGo 中直接使用自定义字母表实现 Base64 编码

**本项目实现路径**: `SrunEncrypt._customBase64Encode()` → 先 `base64.encode()` 再映射表替换
**BitSrunLoginGo 实现路径**: `XBase64.go` → 直接用自定义字母表实现 3 字节→4 字符的 Base64 编码

#### ACID 自动探测策略

> 核心思想源自 BitSrunLoginGo 的 `pkg/srun/detect.go`：
> 未认证用户访问任意 HTTP 网站 → 被重定向到认证服务器 → URL 变成 `http://auth.server/srun_portal_pc.php?ac_id=5&...` → 从中提取 `ac_id`

**两阶段查找**（`AcidDetector.detectAcid()`）：

1. **阶段 1 - URL 参数提取**: 跟随 HTTP 重定向链，检查每个中间 URL 的 query 参数中是否有 `ac_id`、`acid` 或 `Acid`
2. **阶段 2 - HTML 表单提取**: 若 URL 中找不到，请求登录页面 HTML，正则匹配 `"ac_id".*?value="(.+)"` 从隐藏表单中提取

**重定向链跟随**（`_followRedirect`）处理三种跳转方式：
- HTTP 3xx 状态码 → 从 `Location` header 获取下一跳
- JavaScript 跳转 → 正则 `top.self.location.href='(.*)'` 匹配
- Meta Refresh 跳转 → 正则 `<meta[^>]*http-equiv="refresh"[^>]*url=(.+?)["'>]` 匹配

**Reality 模式**（`AcidDetector.reality()`）同时完成两件事：
- 检测是否已在线：如果重定向链最终回到原始目标地址 → 已在线（未触发 Portal 拦截）
- 顺便捕获 ACID：在重定向过程中从 URL 参数提取

**检测入口地址**（按优先级）：
1. `http://www.msftconnecttest.com/connecttest.txt` (Windows)
2. `http://captive.apple.com/hotspot-detect.html` (Apple)
3. `http://connectivitycheck.gstatic.com/generate_204` (Android)
4. `http://detectportal.firefox.com/canonical.html` (Firefox)
5. `http://www.baidu.com` (通用 fallback)

**BitSrunLoginGo 额外特性**（本项目暂未实现）：
- `DetectEnc()`: 自动检测加密版本号（从 Portal JS 文件提取 `var enc = ...`）
- `DetectIp()`: 从登录页 HTML 提取 IP（正则 `ip\s*:\s*"(.+)"`）
- 使用自定义 `CheckRedirect` 返回 `http.ErrUseLastResponse` 禁用自动重定向

#### 加密算法速查

| 算法 | 输入 | 密钥 | 输出格式 |
| :---: | :---: | :---: | :---: |
| `HMAC-MD5` | Password (Latin-1 bytes) | Token (Latin-1 bytes) | 十六进制小写 |
| `SHA1` | Chkstr (ASCII string) | 无 | 十六进制小写 |
| `XXTEA` | JSON 明文 (Latin-1 bytes) | Token (Latin-1 bytes) | 二进制 (uint32 小端数组) |
| `Custom Base64` | XXTEA 密文 (bytes) | 无 | 自定义字母表编码 |

#### 在线状态验证

- `rad_user_info` 返回 `error == "ok"` → 在线
- `rad_user_info` 返回 `error == "not_online_error"` → 离线
- 登录成功判断：`srun_portal` 返回 `error == "ok"` **且** `rad_user_info` 返回 `error == "ok"`
- `online_device_detail` 是 JSON 字符串（值为 `{}` 或设备详情对象），需二次解析

#### 常见错误码映射

| 错误码 | 含义 | 解决方案 |
| :---: | :---: | :---: |
| `ok` | 成功 | — |
| `E2901` | 密码错误或账号不存在 | 检查密码或账号后缀 `@域` |
| `E2902` | 账号不存在或已停用 | 联系网络中心 |
| `E2905` | 账号已欠费停机 | 充值 |
| `E2620` | 设备数超限 | 下线其他设备 |
| `E2821` | IP 不在线 | 检查网络连接 |
| `E2833` | IP 已被占用 | 等待后重试 |
| `E2606` | 用户被禁用 | 联系网络中心 |
| `E3001` | 流量/时长已用尽 | 充值或购买流量包 |
| `E2553` | 密码错误（加密方式不对） | 检查密码 |
| `E2602` | 认证设备响应超时 | 服务器负载高，稍后重试 |
| `ip_already_online_error` | IP 已被其他账号占用 | 先注销再登录 |
| `not_online_error` | 未在线（查询时正常） | 正常待登录状态 |
| `ACID error` | 接入点 ID 错误 | 更换 ACID 重试 |

### 数据模型

- `RadUserInfo` + `OnlineDevice`: 使用 `json_serializable` 生成序列化代码（`.g.dart`），对应深澜 `/rad_user_info` 接口返回
- `ChallengeResponse`: 手动 `fromJson`，对应 `/get_challenge` 接口

### Android 原生

- `MainActivity.kt`: Flutter 入口 Activity
- `BootReceiver.kt`: 开机自启广播接收器
- 通过 `MethodChannel(com.mel0ny.linkup/system)` 与 Flutter 通信，处理开机自启权限和电池优化设置

## 关键注意事项

- 项目使用 `http` 包（非 `dio`）作为主要 HTTP 客户端用于认证请求，`dio` 仅用于 `UpdateUtil` 的 APK 下载
- 认证服务器返回 JSONP 格式（`jQueryCallback({...})`），不是纯 JSON，需要先提取括号内容再解析
- SDK 环境使用开发版 `^3.12.0-239.0.dev`（pubspec.yaml），与其他环境的兼容性需注意
- `RadUserInfo` 的 JSON 字段名使用大驼峰和下划线混用（如 `ServerFlag` 和 `add_time`），`@JsonKey` 注解做了映射
- 测试文件 `widget_test.dart` 是 Flutter 默认模板，尚未更新为实际项目测试

### 协议实现注意事项

- **编码**: 深澜协议中所有字符串操作基于 **Latin-1 (ISO-8859-1)** 编码，不是 UTF-8。本项目 `SrunEncrypt` 中使用 `latin1.encode()` 处理所有加密输入；处理中文用户名时需特别小心（但通常校园网账号是数字/字母）
- **JSONP callback**: 返回格式为 `jQuery随机数字_时间戳({...})`，`SrunClient` 通过 `_extractJsonFromJsonp` 去掉外层包裹后解析，`SrunLogin.doRequest` 通过查找首尾括号位置来提取 JSON
- **密码格式**: 登录请求中 password 参数需加 `{MD5}` 前缀：`{MD5}hmd5value`
- **Info 前缀**: 加密后的 info 参数需加 `{SRBX1}` 协议头前缀，表示使用 XXTEA + 自定义 Base64 加密
- **登录结果不可靠**: `srun_portal` 返回 `error: "ok"` 不代表真正在线，必须再次调用 `rad_user_info` 确认
- **HTTP 重定向控制**: `AcidDetector` 手动控制重定向链（设置 `followRedirects: false`），以便在每个中间跳转 URL 中查找 ACID
- **BitSrunLoginGo vs LinkUp**: Go 版本使用自定义 `CheckRedirect` + `http.ErrUseLastResponse` 禁用自动重定向；LinkUp 使用 `http.Request.followRedirects = false` 实现相同效果
- **Delta 常数差异**: Go/JS 中 XXTEA delta 写作 `0x86014019 | 0x183639A0`（因 32 位溢出拆分），Dart 中直接使用 `0x9E3779B9`（支持大整数）
