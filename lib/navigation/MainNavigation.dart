import 'dart:async';
import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:LinkUp/main.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/page/SettingsPage.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';
import 'package:LinkUp/utils/AcidDetector.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isOnline = false;
  bool _shouldStopMonitor = false;
  RadUserInfo? _userInfo;
  String _currentAcid = '1';
  String _currentEnc = 'srun_bx1';

  final SrunClient client = SrunClient();
  Timer? _monitorTimer;
  Timer? _retryTimer;

  // 检查间隔（秒）
  static const int checkInterval = 3;

  // 退避策略
  int _consecutiveFailures = 0;
  static const int maxBackoffSeconds = 60;

  @override
  void initState() {
    super.initState();

    // 页面加载后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });

    // 启动监控
    _startMonitor();
  }

  Future<void> _checkForUpdate() async {
    // 延迟 2 秒检查，避免启动时阻塞
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final updateInfo = await UpdateUtil.checkUpdate();

    if (updateInfo != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: !updateInfo.isForceUpdate,
        builder: (context) => UpdateDialog(
          updateInfo: updateInfo,
          onDismiss: () => Navigator.pop(context),
        ),
      );
    }
  }

  @override
  void dispose() {
    _shouldStopMonitor = true;
    _monitorTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  // 启动网络监控
  void _startMonitor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 立即执行一次检查
      _checkAndReconnect();

      // 定时检查（每3秒）
      _monitorTimer = Timer.periodic(
        const Duration(seconds: checkInterval),
        (_) => _checkAndReconnect(),
      );
    });
  }

  // 检查连接状态并自动重连
  Future<void> _checkAndReconnect() async {
    if (_shouldStopMonitor) return;
    if (_isLoading) return; // 如果正在登录中，跳过

    // 检查是否已在线
    final isConnected = await _checkOnlineStatus();

    if (isConnected == true) {
      // 已在线，重置退避计数
      if (_consecutiveFailures > 0) {
        LogUtil.info('检测到在线状态，重置退避计数');
        _consecutiveFailures = 0;
      }
      if (!_isOnline) {
        setState(() {
          _isOnline = true;
          _statusMessage = '已在线';
        });
      }
      return;
    }

    if (isConnected == false) {
      setState(() {
        _isOnline = false;
        _statusMessage = '网络断开，正在自动重连...';
      });
    } else {
      setState(() {
        _isOnline = false;
        _statusMessage = '网络检测失败，尝试连接...';
      });
    }

    // 执行安全登录
    await _safeLogin();
  }

  // 检查在线状态 - 使用 Reality 模式同时检测在线状态和 ACID
  Future<bool?> _checkOnlineStatus() async {
    try {
      LogUtil.info('检查在线状态...');
      
      // 使用 Reality 模式检测（同时检测在线状态和 ACID）
      final detector = AcidDetector(baseUrl: client.baseURL);
      final (detectedAcid, isOnline, err) = await detector.reality(
        getAcid: true,
      );

      if (err != null) {
        LogUtil.error('Reality 检测失败', err);
        // Reality 失败时，尝试直接请求认证服务器看是否能通
        LogUtil.info('尝试直接请求认证服务器...');
      }

      LogUtil.info('Reality 检测结果: 在线=$isOnline, ACID=$detectedAcid, 错误=$err');

      // 如果检测到 ACID，保存下来供后续使用
      if (detectedAcid != null && detectedAcid.isNotEmpty) {
        _currentAcid = detectedAcid;
        // 保存到配置
        final config = await ConfigUtil.loadConfig();
        if (config != null) {
          await ConfigUtil.saveConfig(
            username: config['username'] ?? '',
            password: config['password'] ?? '',
            acid: detectedAcid,
            autoAcid: true,
          );
          LogUtil.info('Reality 模式保存 ACID: $detectedAcid');
        }
      }

      if (isOnline) {
        // 已在线，获取用户信息
        try {
          final info = await client.getUserInfo();
          _userInfo = info;
          LogUtil.info('在线状态: true, IP: ${info.onlineIp ?? "unknown"}');
        } catch (e) {
          LogUtil.warning('已在线但获取用户信息失败: $e');
        }
      }
      
      return isOnline;
    } catch (e, stackTrace) {
      LogUtil.error('检查在线状态失败', e, stackTrace);
      return null; // 返回 null 表示检测失败（网络问题），不是不在线
    }
  }

  // 安全登录（带异常捕获和退避策略）
  Future<void> _safeLogin() async {
    // 退避策略：连续失败越多，等待越久
    if (_consecutiveFailures > 0) {
      final backoffSeconds = (checkInterval * (1 << (_consecutiveFailures - 1)))
          .clamp(checkInterval, maxBackoffSeconds);
      LogUtil.info('退避等待 ${backoffSeconds}s（连续失败 $_consecutiveFailures 次）');
      await Future.delayed(Duration(seconds: backoffSeconds));
      if (_shouldStopMonitor || !mounted) return;
    }

    try {
      LogUtil.info('开始安全登录流程');
      await _doLogin();
      LogUtil.info('安全登录流程结束');
    } catch (e, stackTrace) {
      LogUtil.error('登录逻辑异常', e, stackTrace);
      setState(() {
        _statusMessage = '登录异常: $e';
      });
    }

    // 根据结果更新退避计数
    if (_isOnline) {
      if (_consecutiveFailures > 0) {
        LogUtil.info('登录成功，重置退避计数（之前连续失败 $_consecutiveFailures 次）');
      }
      _consecutiveFailures = 0;
    } else {
      _consecutiveFailures++;
      LogUtil.info('登录未成功，连续失败 $_consecutiveFailures 次');
    }
  }

  // 执行登录
  Future<void> _doLogin() async {
    LogUtil.info('========== 开始执行登录 ==========');
    setState(() {
      _isLoading = true;
      _statusMessage = '正在检测网络状态...';
    });

    // 1. 检测 WiFi 是否开启
    bool isWifiConnected = false;
    for (int i = 0; i < 3; i++) {
      isWifiConnected = await NetworkUtil.isWifiConnected();
      LogUtil.info('WiFi 连接状态检测第${i + 1}次: $isWifiConnected');
      if (isWifiConnected) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    if (!isWifiConnected) {
      LogUtil.warning('WiFi 未连接，尝试直接请求认证服务器...');
    }

    setState(() {
      _statusMessage = '正在获取配置...';
    });

    // 2. 读取本地保存的配置
    LogUtil.info('正在读取本地配置...');
    final config = await ConfigUtil.loadConfig();
    if (config == null) {
      LogUtil.warning('未找到配置信息');
      setState(() {
        _isOnline = false;
        _statusMessage = '未找到配置信息';
        _isLoading = false;
      });
      return;
    }

    final String rawUsername = config['username'] ?? '';
    final String password = config['password'] ?? '';
    final String userType = config['user_type'] ?? '';
    String acid = config['acid'] ?? '1';
    _currentAcid = acid;
    final bool autoAcid = config['auto_acid'] ?? true;
    final String authServer = config['auth_server'] ?? '10.129.1.1';

    // 拼接用户名和运营商后缀
    final String username = userType.isNotEmpty ? '$rawUsername@$userType' : rawUsername;

    // 设置认证服务器地址
    if (client.host != authServer) {
      client.setHost(authServer);
      LogUtil.info('认证服务器地址已设置为: $authServer');
    }

    LogUtil.info(
      '配置信息: username=$username, acid=$acid, autoAcid=$autoAcid, server=$authServer',
    );

    if (username.isEmpty || password.isEmpty) {
      LogUtil.warning('账号或密码为空，终止登录');
      setState(() {
        _isOnline = false;
        _statusMessage = '账号或密码为空';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取网络信息...');
    LogUtil.info('正在获取用户信息...');

    // 3. 获取 IP 和用户信息
    final String ip;
    try {
      final info = await client.getUserInfo();
      _userInfo = info;
      // 优先使用 client_ip（始终存在），回退到 online_ip
      ip = (info.clientIp?.isNotEmpty == true ? info.clientIp : info.onlineIp) ?? '';
      LogUtil.info('获取到用户信息: clientIp=${info.clientIp}, onlineIp=${info.onlineIp}, 使用IP=$ip, 是否在线=${info.isOnline}');

      // 再次检查是否已经在线（可能在这期间已连接）
      if (info.isOnline) {
        LogUtil.info('用户已在线，跳过登录');
        setState(() {
          _isOnline = true;
          _statusMessage = '已在线';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      LogUtil.error('获取用户信息失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '无法连接认证服务器: $e';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取认证令牌...');
    LogUtil.info('正在获取 Challenge/Token...');

    // 4. 获取 Challenge/Token
    late final String token;
    try {
      final challenge = await client.getChallenge(username: username, ip: ip);
      token = challenge.challenge;
      LogUtil.info(
        '获取到 Token: ${token.substring(0, token.length > 10 ? 10 : token.length)}...',
      );
    } catch (e) {
      LogUtil.error('获取认证令牌失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '获取认证令牌失败: $e';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在登录...');

    // 5. 执行登录（自动尝试 ACID）
    LoginResult loginResult;

    try {
      if (autoAcid) {
        // 自动模式：先检测 ACID，如果检测失败则使用配置的 ACID
        LogUtil.info('使用自动 ACID 模式，开始检测 ACID...');
        final detector = AcidDetector(baseUrl: client.baseURL);
        final detectedAcid = await _detectAcid(detector);
        if (detectedAcid != null) {
          _currentAcid = detectedAcid;
          acid = detectedAcid;
          LogUtil.info('使用检测到的 ACID: $acid');
        } else {
          LogUtil.warning('ACID 检测失败，使用配置的 ACID: $acid');
        }

        // 同时自动检测 enc 版本
        setState(() => _statusMessage = '正在检测加密版本...');
        final detectedEnc = await detector.detectEnc();
        if (detectedEnc != null && detectedEnc.isNotEmpty) {
          _currentEnc = detectedEnc;
          LogUtil.info('使用检测到的 enc: $_currentEnc');
        } else {
          LogUtil.warning('enc 检测失败，使用默认值: $_currentEnc');
        }

        setState(() {
          _statusMessage = '正在使用 ACID: $acid 登录...';
        });
        loginResult = await SrunLogin.srucPortalLogin(
          username,
          password,
          acid,
          token,
          ip,
          encVer: _currentEnc,
        );
      } else {
        // 手动模式：使用配置的 ACID
        _currentAcid = acid;
        LogUtil.info('使用手动 ACID 模式: acid=$acid');
        setState(() {
          _statusMessage = '正在使用 ACID: $acid 登录...';
        });
        loginResult = await SrunLogin.srucPortalLogin(
          username,
          password,
          acid,
          token,
          ip,
          encVer: _currentEnc,
        );
      }
    } catch (e) {
      LogUtil.error('登录请求失败', e);
      setState(() {
        _isOnline = false;
        _statusMessage = '登录请求失败: $e';
        _isLoading = false;
      });
      return;
    }

    // 6. 检查登录结果
    if (!loginResult.success) {
      LogUtil.warning(
        '登录失败: ${loginResult.message}, 错误类型: ${loginResult.errorType}',
      );
      setState(() {
        _isOnline = false;
        _statusMessage = '登录失败: ${loginResult.message}';
        _isLoading = false;
      });
      return;
    }

    // 7. 登录成功，刷新用户信息
    LogUtil.info('登录成功，正在刷新用户信息...');
    final newInfo = await client.getUserInfo();
    setState(() {
      _isOnline = true;
      _userInfo = newInfo;
      _statusMessage = '登录成功';
      _isLoading = false;
    });
    LogUtil.info('登录流程完成，用户已在线，IP: ${newInfo.onlineIp ?? "unknown"}');

    // 显示成功提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('校园网已连接'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
    LogUtil.info('========== 登录流程结束 ==========');
  }

  // 使用 AcidDetector 自动检测 ACID（使用缓存的 detector）
  Future<String?> _detectAcid(AcidDetector detector) async {
    LogUtil.info('[MainNavigation] 开始自动检测 ACID...');

    setState(() {
      _statusMessage = '正在自动检测网络接入点...';
    });

    try {
      final acid = await detector.detectAcid();
      
      if (acid != null && acid.isNotEmpty) {
        LogUtil.info('[MainNavigation] 自动检测 ACID 成功: $acid');
        
        // 保存检测到的 ACID 到配置
        final config = await ConfigUtil.loadConfig();
        if (config != null) {
          await ConfigUtil.saveConfig(
            username: config['username'] ?? '',
            password: config['password'] ?? '',
            acid: acid,
            autoAcid: true,
          );
          LogUtil.info('[MainNavigation] 已保存检测到的 ACID: $acid');
        }
        
        return acid;
      } else {
        LogUtil.warning('[MainNavigation] 自动检测 ACID 失败，将使用配置的 ACID');
        return null;
      }
    } catch (e, stackTrace) {
      LogUtil.error('[MainNavigation] 检测 ACID 过程出错', e, stackTrace);
      return null;
    }
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? MyApp.iosBlue.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? MyApp.iosBlue : const Color(0xFF8E8E93),
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? MyApp.iosBlue : const Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 注销 — 使用 DM API (/cgi-bin/rad_user_dm)，与登录加密链无关
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认注销'),
        content: const Text('确定要注销校园网连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: MyApp.iosRed),
            child: const Text('注销'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _monitorTimer?.cancel();
    setState(() {
      _isLoading = true;
      _statusMessage = '正在注销...';
    });

    try {
      final config = await ConfigUtil.loadConfig();
      if (config == null) return;

      final rawUsername = config['username'] ?? '';
      final userType = config['user_type'] ?? '';
      final username = userType.isNotEmpty ? '$rawUsername@$userType' : rawUsername;

      // 获取当前 IP
      final info = await client.getUserInfo();
      final ip = (info.clientIp?.isNotEmpty == true ? info.clientIp : info.onlineIp) ?? '';

      // DM 注销：只需要 username + ip + 时间戳签名，不需要 token/加密
      final success = await SrunLogin.dmLogout(username: username, ip: ip);

      setState(() {
        _isOnline = false;
        _userInfo = null;
        _isLoading = false;
        _statusMessage = success ? '已注销' : '注销失败';
        _consecutiveFailures = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '已成功注销' : '注销失败，请重试'),
            backgroundColor: success ? MyApp.iosGreen : MyApp.iosRed,
          ),
        );
      }
    } catch (e, stackTrace) {
      LogUtil.error('注销异常', e, stackTrace);
      setState(() {
        _isLoading = false;
        _statusMessage = '注销异常';
      });
    }

    // 重新启动监控
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => _checkAndReconnect(),
    );
  }

  // 手动触发登录（下拉刷新）
  Future<void> _manualLogin() async {
    LogUtil.info('用户手动触发登录（下拉刷新）');
    _consecutiveFailures = 0;
    _monitorTimer?.cancel();
    await _safeLogin();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => _checkAndReconnect(),
    );
    LogUtil.info('手动登录完成，监控已恢复');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        actions: [
          if (_isOnline)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('注销'),
                style: TextButton.styleFrom(
                  foregroundColor: MyApp.iosRed,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              OverviewPage(
                isLoading: _isLoading,
                statusMessage: _statusMessage,
                isOnline: _isOnline,
                currentAcid: _currentAcid,
                userInfo: _userInfo,
                onRefresh: () => _manualLogin(),
              ),
              const SettingsPage(),
            ],
          ),
          // Floating liquid glass pill — transparent background, no Scaffold chrome
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                child: LiquidGlass.withOwnLayer(
                  settings: const LiquidGlassSettings(
                    blur: 18,
                    thickness: 10,
                    glassColor: Color(0x1AFFFFFF),
                    saturation: 1.05,
                  ),
                  shape: LiquidRoundedSuperellipse(borderRadius: 28),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildNavItem(
                          index: 0,
                          icon: Icons.speed_outlined,
                          selectedIcon: Icons.speed,
                          label: '概况',
                        ),
                        _buildNavItem(
                          index: 1,
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          label: '设置',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
