import 'dart:async';

import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:LinkUp/main.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:lightweight_liquid_glass/lightweight_liquid_glass.dart';
import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/page/SettingsPage.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.client}) : _testPages = null;

  @visibleForTesting
  const MainNavigator.test({
    super.key,
    this.client,
    required List<Widget> pages,
  }) : assert(pages.length == 2),
       _testPages = pages;

  final AuthRuntimeClient? client;
  final List<Widget>? _testPages;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _statusMessage;
  bool _isOnline = false;
  RadUserInfo? _userInfo;
  String _currentAcid = '1';

  late final AuthRuntimeClient _client;
  StreamSubscription<AuthRuntimeState>? _authStateSubscription;

  // 用户操作锁只保护 UI 交互；认证协议本身由后台运行时单飞锁保护。
  bool _userOperationInProgress = false;

  @override
  void initState() {
    super.initState();

    _client = widget.client ?? AuthRuntimeClient();
    _authStateSubscription = _client.states.listen(_onAuthRuntimeState);

    // Activity 只绑定后台认证运行时，不在这里创建协调器或认证周期 Timer。
    unawaited(_client.attach());

    // 页面加载后检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_client.start());
    });
  }

  void _onAuthRuntimeState(AuthRuntimeState state) {
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
          _currentAcid = state.acid ?? _currentAcid;
          _statusMessage = state.message ?? '已在线';
        });
      case AuthenticationStatus.failed:
      case AuthenticationStatus.cancelled:
      case AuthenticationStatus.stale:
      case AuthenticationStatus.backingOff:
        setState(() {
          _isLoading = false;
          _isOnline = false;
          _statusMessage = state.message ?? '认证未完成，将自动重试';
        });
      case AuthenticationStatus.offline:
        setState(() {
          _isLoading = false;
          _isOnline = false;
          _statusMessage = state.message ?? 'WiFi 未连接';
        });
      case AuthenticationStatus.stopped:
        setState(() {
          _isLoading = false;
          _isOnline = false;
          _userInfo = null;
          _statusMessage = state.message;
        });
      case AuthenticationStatus.idle:
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
    unawaited(_authStateSubscription?.cancel());
    unawaited(_client.dispose());
    super.dispose();
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
    setState(() {
      _isLoading = true;
      _statusMessage = '正在注销...';
    });

    try {
      final success = await _client.logout();
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
      final success = await _client.kickDevice(targetIp);
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

  // 手动触发检查（下拉刷新）
  Future<void> _manualLogin() async {
    if (_userOperationInProgress) return;
    _userOperationInProgress = true;
    try {
      await _client.manualCheck();
    } finally {
      _userOperationInProgress = false;
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
            children:
                widget._testPages ??
                [
                  OverviewPage(
                    isLoading: _isLoading,
                    statusMessage: _statusMessage,
                    isOnline: _isOnline,
                    currentAcid: _currentAcid,
                    userInfo: _userInfo,
                    onRefresh: _manualLogin,
                    onKickDevice: _kickDevice,
                  ),
                  SettingsPage(
                    onConfigChanged: (hasConfig) {
                      unawaited(
                        _client.configurationChanged(hasConfig: hasConfig),
                      );
                    },
                  ),
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
                child: GlassSurface(
                  style: const GlassStyle(
                    blurSigmaX: 6,
                    blurSigmaY: 6,
                    tintOpacity: 0.18,
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    shadowOpacity: 0,
                  ),
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
