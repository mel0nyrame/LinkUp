import 'dart:async';
import 'package:flutter/material.dart';
import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/page/SettingsPage.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

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
    // 启动监控
    _startMonitor();
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

    if (isConnected) {
      // 已在线，更新状态
      if (!_isOnline) {
        setState(() {
          _isOnline = true;
          _statusMessage = '已在线';
        });
      }
      return;
    }

    // 未在线，需要重连
    setState(() {
      _isOnline = false;
      _statusMessage = '网络断开，正在自动重连...';
    });

    // 执行安全登录
    await _safeLogin();
  }

  // 检查在线状态
  Future<bool> _checkOnlineStatus() async {
    try {
      final info = await client.getUserInfo();
      _userInfo = info;
      return info.isOnline;
    } catch (e) {
      return false;
    }
  }

  // 安全登录（带异常捕获）
  Future<void> _safeLogin() async {
    try {
      await _doLogin();
    } catch (e, stackTrace) {
      print('❌ 登录逻辑异常: $e');
      print('堆栈: $stackTrace');
      setState(() {
        _statusMessage = '登录异常: $e';
      });
    }
  }

  // 执行登录
  Future<void> _doLogin() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在检测网络状态...';
    });

    // 1. 检测 WiFi 是否开启
    final bool isWifiConnected = await NetworkUtil.isWifiConnected();
    if (!isWifiConnected) {
      setState(() {
        _isOnline = false;
        _statusMessage = 'WiFi未开启';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _statusMessage = '正在获取配置...';
    });

    // 2. 读取本地保存的配置
    final config = await ConfigUtil.loadConfig();
    if (config == null) {
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

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _isOnline = false;
        _statusMessage = '账号或密码为空';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取网络信息...');

    // 3. 获取 IP 和用户信息
    final info = await client.getUserInfo();
    _userInfo = info;
    final String ip = info.onlineIp;

    // 再次检查是否已经在线（可能在这期间已连接）
    if (info.isOnline) {
      setState(() {
        _isOnline = true;
        _statusMessage = '已在线';
        _isLoading = false;
      });
      return;
    }

    setState(() => _statusMessage = '正在获取认证令牌...');

    // 4. 获取 Challenge/Token
    final challenge = await client.getChallenge(username: username, ip: ip);
    final String token = challenge.challenge;

    setState(() => _statusMessage = '正在登录...');

    // 5. 执行登录（自动尝试 ACID）
    LoginResult loginResult;

    if (autoAcid) {
      // 自动模式：尝试 ACID 1-20
      loginResult = await _tryLoginWithAutoAcid(username, password, token, ip);
      acid = _currentAcid;
    } else {
      // 手动模式：使用配置的 ACID
      _currentAcid = acid;
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

    // 6. 检查登录结果
    if (!loginResult.success) {
      setState(() {
        _isOnline = false;
        _statusMessage = '登录失败: ${loginResult.message}';
        _isLoading = false;
      });
      return;
    }

    // 7. 登录成功，刷新用户信息
    final newInfo = await client.getUserInfo();
    setState(() {
      _isOnline = true;
      _userInfo = newInfo;
      _statusMessage = '登录成功';
      _isLoading = false;
    });

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
  }

  // 自动尝试 ACID 1-20
  Future<LoginResult> _tryLoginWithAutoAcid(
    String username,
    String password,
    String token,
    String ip,
  ) async {
    LoginResult lastResult = LoginResult(
      success: false,
      message: '所有 ACID 尝试失败',
    );

    for (int i = 1; i <= 20; i++) {
      if (_shouldStopMonitor) break;

      final acid = i.toString();
      _currentAcid = acid;

      setState(() {
        _statusMessage = '正在尝试 ACID: $acid...';
      });

      final result = await SrunLogin.srucPortalLogin(
        username,
        password,
        acid,
        token,
        ip,
      );

      if (result.success) {
        // 登录成功，保存成功的 ACID
        final config = await ConfigUtil.loadConfig();
        if (config != null) {
          await ConfigUtil.saveConfig(
            username: config['username'] ?? '',
            password: config['password'] ?? '',
            acid: acid,
            autoAcid: true,
          );
        }
        return result;
      }

      lastResult = result;

      // 如果是账号密码错误，不需要继续尝试其他 ACID
      if (result.errorType == LoginErrorType.authFailed) {
        return result;
      }

      // 小延迟避免请求过快
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return lastResult;
  }

  // 手动触发登录（下拉刷新）
  Future<void> _manualLogin() async {
    // 取消当前的监控定时器
    _monitorTimer?.cancel();

    // 执行登录
    await _safeLogin();

    // 重新启动监控
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => _checkAndReconnect(),
    );
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
