import 'dart:async';

import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:LinkUp/main.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/page/SettingsPage.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/SrunAuthenticationProtocol.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.coordinator});

  final AuthenticationCoordinator? coordinator;

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

  late final AuthenticationCoordinator _coordinator;
  late final StreamSubscription<AuthenticationState> _authStateSubscription;
  StreamSubscription<dynamic>? _networkSubscription;
  bool _ownsCoordinator = false;
  Timer? _monitorTimer;

  // 用户操作锁只保护 UI 交互；认证协议本身由协调器单飞锁保护。
  bool _userOperationInProgress = false;

  // 检查间隔（秒）
  static const int checkInterval = 3;

  @override
  void initState() {
    super.initState();

    final injectedCoordinator = widget.coordinator;
    if (injectedCoordinator == null) {
      _coordinator = AuthenticationCoordinator(
        configSource: ConfigUtilSource(),
        protocol: SrunAuthenticationProtocol(),
        networkState: AuthenticationNetworkTracker(),
      );
      _ownsCoordinator = true;
    } else {
      _coordinator = injectedCoordinator;
    }

    _authStateSubscription = _coordinator.states.listen(_onAuthenticationState);
    _networkSubscription = NetworkUtil.onConnectivityChanged.listen((_) {
      _coordinator.invalidateNetwork();
      unawaited(_coordinator.check());
    });

    // 页面加载后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });

    // 启动监控
    _startMonitor();
  }

  void _onAuthenticationState(AuthenticationState state) {
    if (!mounted) return;

    switch (state.status) {
      case AuthenticationStatus.checking:
        setState(() {
          _isLoading = true;
          _statusMessage = '正在检查网络状态...';
        });
      case AuthenticationStatus.authenticating:
        setState(() {
          _isLoading = true;
          _statusMessage = '正在登录...';
        });
      case AuthenticationStatus.online:
      case AuthenticationStatus.alreadyOnline:
        setState(() {
          _isLoading = false;
          _isOnline = true;
          _userInfo = state.userInfo ?? _userInfo;
          _currentAcid = state.parameters?.acid ?? _currentAcid;
          _statusMessage = state.message ?? '已在线';
        });
      case AuthenticationStatus.failed:
      case AuthenticationStatus.cancelled:
      case AuthenticationStatus.stale:
        setState(() {
          _isLoading = false;
          _isOnline = false;
          _statusMessage = state.message ?? '认证未完成，将自动重试';
        });
      case AuthenticationStatus.idle:
      case AuthenticationStatus.offline:
        setState(() {
          _isLoading = false;
          _isOnline = false;
        });
    }
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
    unawaited(_authStateSubscription.cancel());
    unawaited(_networkSubscription?.cancel());
    if (_ownsCoordinator) unawaited(_coordinator.dispose());
    super.dispose();
  }

  // 启动网络监控
  void _startMonitor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shouldStopMonitor || !mounted) return;

      unawaited(_checkAndReconnect());
      _monitorTimer = Timer.periodic(
        const Duration(seconds: checkInterval),
        (_) => unawaited(_checkAndReconnect()),
      );
    });
  }

  // 重建监控定时器（注销/手动刷新路径）。
  Future<void> _restartMonitor() async {
    if (_shouldStopMonitor || !mounted) return;
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: checkInterval),
      (_) => unawaited(_checkAndReconnect()),
    );
  }

  // 检查连接状态并自动重连
  Future<void> _checkAndReconnect() async {
    if (_shouldStopMonitor || !mounted) return;
    await _runCoordinatorCheck();
  }

  Future<void> _runCoordinatorCheck({bool? manual}) async {
    await _coordinator.authenticate(manual: manual);
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
    if (_userOperationInProgress) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('正在处理中，请稍候再试')));
      }
      return;
    }

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
    if (confirmed != true || !mounted) return;

    _userOperationInProgress = true;
    _monitorTimer?.cancel();
    setState(() {
      _isLoading = true;
      _statusMessage = '正在注销...';
    });

    try {
      final success = await _coordinator.logout();
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _userInfo = null;
        _isLoading = false;
        _statusMessage = success ? '已注销' : '注销失败';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '已成功注销' : '注销失败，请重试'),
          backgroundColor: success ? MyApp.iosGreen : MyApp.iosRed,
        ),
      );
      if (success) await _restartMonitor();
    } catch (error, stackTrace) {
      LogUtil.error('注销异常', error, stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '注销异常';
        });
      }
    } finally {
      _userOperationInProgress = false;
    }
  }

  // 踢设备下线 — 通过 DM 接口强制解绑账号下的指定 IP
  Future<bool> _kickDevice(String targetIp) async {
    try {
      final success = await _coordinator.kickDevice(targetIp);
      if (!mounted) return success;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '已踢 $targetIp' : '踢人失败：服务器返回错误'),
          backgroundColor: success ? MyApp.iosGreen : MyApp.iosRed,
        ),
      );
      return success;
    } catch (error, stackTrace) {
      LogUtil.error('踢设备异常', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('踢人失败，请重试'),
            backgroundColor: MyApp.iosRed,
          ),
        );
      }
      return false;
    }
  }

  // 手动触发登录（下拉刷新）
  Future<void> _manualLogin() async {
    if (_userOperationInProgress) return;
    _userOperationInProgress = true;
    _monitorTimer?.cancel();
    try {
      await _runCoordinatorCheck();
    } finally {
      _userOperationInProgress = false;
      await _restartMonitor();
    }
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
                onKickDevice: _kickDevice,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 8,
                ),
                child: LiquidGlass.withOwnLayer(
                  settings: const LiquidGlassSettings(
                    blur: 18,
                    thickness: 10,
                    glassColor: Color(0x1AFFFFFF),
                    saturation: 1.05,
                  ),
                  shape: LiquidRoundedSuperellipse(borderRadius: 28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
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
