import 'dart:async';
import 'dart:convert';

import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';
import 'package:LinkUp/main.dart';
import 'package:flutter/material.dart';
import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
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
  final ValueNotifier<AuthRuntimeState> _status = ValueNotifier(
    const AuthRuntimeState.stopped(),
  );
  final ValueNotifier<RadUserInfo?> _userInfo = ValueNotifier(null);
  final ValueNotifier<bool> _online = ValueNotifier(false);
  final ValueNotifier<String?> _acid = ValueNotifier(null);
  final ValueNotifier<OverviewOperation> _operation = ValueNotifier((
    loading: false,
    message: null,
  ));

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
    final previous = _status.value;
    if (previous.status != state.status ||
        previous.message != state.message ||
        previous.retryAfterSeconds != state.retryAfterSeconds ||
        previous.reason != state.reason ||
        previous.isOnline != state.isOnline) {
      _status.value = state;
    }
    if (_acid.value != state.acid) _acid.value = state.acid;
    if (_online.value != state.isOnline) {
      _online.value = state.isOnline;
    }
    final nextInfo = state.isOnline ? state.userInfo ?? _userInfo.value : null;
    if (jsonEncode(nextInfo?.toJson()) !=
        jsonEncode(_userInfo.value?.toJson())) {
      _userInfo.value = nextInfo;
    }
    if (!_userOperationInProgress && _operation.value.message != null) {
      _operation.value = (loading: false, message: null);
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
    _status.dispose();
    _userInfo.dispose();
    _online.dispose();
    _acid.dispose();
    _operation.dispose();
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
    _operation.value = (loading: true, message: '正在注销...');

    try {
      final result = await _client.logout();
      if (!mounted) return;
      _operation.value = (loading: false, message: null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_logoutMessage(result)),
          backgroundColor: result.accepted ? MyApp.iosGreen : MyApp.iosRed,
        ),
      );
    } on AuthRuntimeUnavailableException {
      if (mounted) {
        _operation.value = (loading: false, message: '后台认证运行时不可用');
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('后台认证运行时不可用，请稍后重试')));
      }
    } catch (error, stackTrace) {
      LogUtil.error('注销异常', error, stackTrace);
      if (mounted) {
        _operation.value = (loading: false, message: '注销异常');
      }
    } finally {
      _userOperationInProgress = false;
    }
  }

  // 踢设备下线 — 通过 DM 接口强制解绑账号下的指定 IP
  Future<void> _kickDevice(String targetIp) async {
    try {
      final result = await _client.kickDevice(targetIp);
      if (!mounted) return;

      _showKickOutcome(targetIp, result);
      if (result.outcome == DmOutcome.kicked) {
        // 踢掉的那一行就是复查的依据，本地这份列表仍是旧的，重新拉一次。
        await _manualLogin();
      }
      await LogUtil.info('踢设备 $targetIp 结果：${result.outcome.name}');
    } on AuthRuntimeUnavailableException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('后台认证运行时不可用，请稍后重试')));
      }
    } catch (error, stackTrace) {
      LogUtil.error('踢设备 $targetIp 异常', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('踢人失败，请重试'),
            backgroundColor: MyApp.iosRed,
          ),
        );
      }
    }
  }

  /// 注销提示。被拒绝时把服务器给的原因带上，否则用户只知道失败、不知道为什么。
  String _logoutMessage(DmResult result) {
    if (result.accepted) return '已要求注销';
    final reason = result.reason;
    return reason == null ? '注销失败，请重试' : '注销失败：$reason';
  }

  void _showKickOutcome(String targetIp, DmKickResult result) {
    final (message, color) = switch (result.outcome) {
      DmOutcome.kicked => ('已踢掉 $targetIp', MyApp.iosGreen),
      // 服务器受理了请求，但复查没能确认断开。这条也覆盖复查中途拿不到设备表的
      // 情况，所以措辞只能说「未能确认」，不能说它仍在线——我们没有那个证据。
      DmOutcome.accepted => ('已要求 $targetIp 下线，但未能确认它已断开', MyApp.iosOrange),
      DmOutcome.rejected => (
        result.reason == null ? '踢人失败：服务器返回错误' : '踢人失败：${result.reason}',
        MyApp.iosRed,
      ),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
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
          ValueListenableBuilder<bool>(
            valueListenable: _online,
            builder: (context, online, child) => online
                ? Padding(
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
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              TickerMode(
                enabled: _currentIndex == 0,
                child:
                    widget._testPages?[0] ??
                    OverviewPage(
                      status: _status,
                      acid: _acid,
                      online: _online,
                      userInfo: _userInfo,
                      operation: _operation,
                      onRefresh: _manualLogin,
                      onKickDevice: _kickDevice,
                    ),
              ),
              TickerMode(
                enabled: _currentIndex == 1,
                child: widget._testPages?[1] ?? const SettingsPage(),
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
