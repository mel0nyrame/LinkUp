import 'dart:async';
import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/LogUtil.dart';
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

  final SrunClient client = SrunClient();
  Timer? _monitorTimer;
  Timer? _retryTimer;

  // 检查间隔（秒）
  static const int checkInterval = 3;

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
      // 已在线，更新状态
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

  // 安全登录（带异常捕获）
  Future<void> _safeLogin() async {
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

    final String username = config['username'] ?? '';
    final String password = config['password'] ?? '';
    String acid = config['acid'] ?? '1';
    _currentAcid = acid;
    final bool autoAcid = config['auto_acid'] ?? true;
    final String authServer = config['auth_server'] ?? '10.129.1.1';

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
      ip = info.onlineIp ?? '';
      LogUtil.info('获取到用户信息: IP=$ip, 是否在线=${info.isOnline}');

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

        setState(() {
          _statusMessage = '正在使用 ACID: $acid 登录...';
        });
        loginResult = await SrunLogin.srucPortalLogin(
          username,
          password,
          acid,
          token,
          ip,
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

  // 手动触发登录（下拉刷新）
  Future<void> _manualLogin() async {
    LogUtil.info('用户手动触发登录（下拉刷新）');
    // 取消当前的监控定时器
    _monitorTimer?.cancel();

    // 执行登录
    await _safeLogin();

    // 重新启动监控
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => _checkAndReconnect(),
    );
    LogUtil.info('手动登录完成，监控已恢复');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LinkUp'),
        actions: [
          // 显示监控状态指示器
          if (_isLoading)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 概况页
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '概况',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
