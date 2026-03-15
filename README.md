# LinkUp - 校园网自动认证客户端

基于深澜(Srun)协议的校园网自动连接工具，支持自动检测网络状态、断网自动重连、后台持续监控等功能。

## 思路/想法来源

https://github.com/1328411791/GDOUYJ_Internet_Client

https://github.com/CyLzzh/srun_client

## 功能特性

- 🔐 **自动认证**：支持深澜协议自动登录校园网
- 🔄 **智能重连**：网络断开时自动检测并重连，无需手动操作
- 🔍 **ACID自动探测**：自动尝试 1-20 范围内的 ACID 值，适配不同网络环境
- 📊 **状态监控**：实时显示在线状态、IP地址、流量统计、在线时长等信息
- 📱 **后台保活**：支持后台持续运行，切换应用不影响监控
- ⚡ **开机自启**：支持开机自动启动（Android）
- 📝 **错误日志**：详细的错误日志记录，便于排查问题
- 🎨 **Material Design 3**：现代化的界面设计

## 适用平台

| 平台 | 状态 | 说明 |
|------|------|------|
| Android | ✅ 完整支持 | 支持所有功能包括后台保活和开机自启 |
| iOS | ⚠️ 展示不支持 | 暂无适配 |
| Windows/macOS/Linux | ⚠️ 展示不支持 | 暂无适配 |
| Web | ❌ 不支持 | 由于网络权限限制，不支持 Web 平台 |

## 安装

### Android

1. 下载最新版本的 APK 文件
2. 允许安装未知来源应用
3. 安装完成后首次启动会提示配置账号

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/yourusername/linkup.git
cd linkup

# 安装依赖
flutter pub get

# 构建 Android APK
flutter build apk --release

# 或构建 iOS 应用（需要 macOS 和 Xcode）
flutter build ios --release
```

## 使用说明

### 首次配置

1. 首次启动应用会弹出配置对话框
2. 输入学号/工号和密码
3. 选择 ACID 模式：
   - **自动获取**：自动尝试 1-20 寻找可用接入点
   - **手动指定**：手动输入 ACID 值（常见值：1, 2, 5, 11, 15）
4. 点击保存并进入

### 主界面

- **概况页面**：显示在线状态、网络信息、流量统计、在线设备等
- **设置页面**：修改账号信息、系统设置、网络配置

### 下拉刷新

在概况页面下拉可手动触发重新连接。

### 后台运行

在设置 > 系统设置中开启"保留后台运行"：
- 开启后应用会持续监控网络状态，即使切换到后台
- 建议同时将此应用加入系统电池优化白名单

### 开机自启（Android）

在设置 > 系统设置中开启"开机自启动"：
- 开启后设备重启会自动启动应用
- 部分国产 ROM（小米、华为、OPPO、vivo）可能需要在系统设置中额外授权

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── navigation/
│   └── MainNavigation.dart      # 主导航框架
├── page/
│   ├── AuthWrapperPage.dart     # 认证包装页（首次配置检测）
│   ├── OverViewPage.dart        # 概况页（主页面）
│   └── SettingsPage.dart        # 设置页
├── components/
│   ├── AccountCart.dart         # 账号信息卡片
│   ├── NetWorkConfig.dart       # 网络配置卡片
│   ├── SystemSettingsCard.dart  # 系统设置卡片
│   ├── StatusCard.dart          # 状态卡片
│   ├── InfoDataRow.dart         # 数据行组件
│   ├── DeviceInfoRow.dart       # 设备信息行组件
│   └── InformationCart.dart     # 信息卡片组件
└── utils/
    ├── ConfigUtil.dart          # 配置存储工具
    ├── NetworkUtil.dart         # 网络状态检测
    ├── SrunClient.dart          # 深澜 API 客户端
    ├── SrunLogin.dart           # 登录逻辑
    ├── SrunEncrypt.dart         # 加密/校验工具
    ├── SystemSettingsUtil.dart  # 系统设置工具
    ├── LogUtil.dart             # 日志工具
    ├── RadUserInfo.dart         # 用户信息数据模型
    └── ChallengeResponse.dart   # Challenge 响应数据模型
```

## 常见问题

### Q: 为什么显示"WiFi未开启"？
A: 应用需要连接校园网 WiFi 才能正常工作。请确保已连接到校园网无线网络。

### Q: 登录失败，提示"ACID错误"？
A: 尝试切换 ACID 模式为"自动获取"，或手动尝试其他 ACID 值（如 1, 2, 5, 11, 15）。

### Q: 应用被杀后台怎么办？
A: 
1. 在设置中开启"保留后台运行"
2. 将应用加入系统电池优化白名单
3. 在系统设置中允许应用自启动（部分国产 ROM）

### Q: 日志文件在哪里？
A: 日志文件保存在应用配置目录下：
- Android: `/data/data/com.mel0ny.linkup/app_flutter/error.log`
- iOS: 应用沙盒的 Documents 目录下

### Q: 支持哪些学校？
A: 本应用基于深澜(Srun)认证协议开发，理论上支持所有使用深澜认证系统的学校。如果无法使用，可能是学校使用了定制版本。

## 错误代码对照

| 错误代码 | 说明 | 解决方案 |
|----------|------|----------|
| E2901 | 密码错误或账号不存在 | 检查学号/工号和密码是否正确 |
| E2902 | 账号不存在或已停用 | 联系网络中心确认账号状态 |
| E2905 | 账号已欠费停机 | 前往网络中心充值 |
| E2821 | IP 不在线 | 检查网络连接是否正常 |
| E2833 | IP 已经被占用 | 等待一段时间后重试 |
| E2606 | 用户被禁用 | 联系网络中心解除禁用 |
| E3001 | 流量或时长已用尽 | 充值或购买流量包 |

## 开发计划

- [ ] 添加桌面端支持（Windows/macOS/Linux）
- [ ] 支持多账号切换
- [ ] 深色模式支持

## 免责声明

本工具仅供学习和个人使用，请勿用于非法用途。使用本工具产生的任何后果由使用者自行承担。

## 许可证

[MIT License](LICENSE)

## 致谢

- 深澜认证协议参考：[comzyh/srun](https://github.com/comzyh/srun)
- Flutter 团队提供的优秀框架
- 所有贡献者和测试者

---

**注意**：本项目与深澜官方无关，是基于公开协议实现的第三方客户端。
