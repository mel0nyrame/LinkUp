import 'dart:async';

import 'package:flutter/material.dart';
import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/page/WindowsLogsPage.dart';
import 'package:LinkUp/page/WindowsSettingsPage.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';

class WindowsHome extends StatefulWidget {
  const WindowsHome({
    super.key,
    required this.initialState,
    required this.states,
    required this.onManualCheck,
    this.compact = false,
    this.wifiConnected = false,
    this.monitoringEnabled = false,
    this.onOpenDetails,
    this.selectedDestination = 0,
    this.onDestinationChanged,
    this.configuration,
    this.onLogout,
    this.onKickDevice,
    this.checkForUpdatesOnStartup = false,
    @visibleForTesting this.updateChecker,
  });

  final AuthRuntimeState initialState;
  final Stream<AuthRuntimeState> states;
  final Future<void> Function() onManualCheck;
  final bool compact;
  final bool wifiConnected;
  final bool monitoringEnabled;
  final VoidCallback? onOpenDetails;
  final int selectedDestination;
  final ValueChanged<int>? onDestinationChanged;
  final ConfigManager? configuration;
  final Future<DmResult> Function()? onLogout;
  final Future<DmKickResult> Function(String ip)? onKickDevice;
  final bool checkForUpdatesOnStartup;
  @visibleForTesting
  final Future<UpdateInfo?> Function()? updateChecker;

  @override
  State<WindowsHome> createState() => _WindowsHomeState();
}

class _WindowsHomeState extends State<WindowsHome> {
  late AuthRuntimeState _state = widget.initialState;
  late int _selectedDestination = widget.selectedDestination;
  StreamSubscription<AuthRuntimeState>? _subscription;
  bool _deviceOperationInProgress = false;
  bool _checkingForUpdate = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    if (widget.checkForUpdatesOnStartup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) unawaited(_checkForUpdate());
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant WindowsHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDestination != widget.selectedDestination) {
      _selectedDestination = widget.selectedDestination;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _selectDestination(int destination) {
    if (widget.onDestinationChanged != null) {
      widget.onDestinationChanged!(destination);
    } else {
      setState(() => _selectedDestination = destination);
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      final updateInfo =
          await (widget.updateChecker ?? UpdateUtil.checkUpdate)();
      if (!mounted) return;
      setState(() => _checkingForUpdate = false);
      if (updateInfo == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没有发现可用更新。')));
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: !updateInfo.isForceUpdate,
        builder: (dialogContext) => UpdateDialog(
          updateInfo: updateInfo,
          onDismiss: () => Navigator.pop(dialogContext),
        ),
      );
    } finally {
      if (mounted && _checkingForUpdate) {
        setState(() => _checkingForUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _state.presentation;
    if (widget.compact) return _buildPopup(context, presentation);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LinkUp'),
        actions: [
          IconButton(
            tooltip: '检查更新',
            onPressed: _checkingForUpdate
                ? null
                : () => unawaited(_checkForUpdate()),
            icon: _checkingForUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: FilledButton.icon(
              onPressed: widget.onManualCheck,
              icon: const Icon(Icons.refresh),
              label: const Text('立即检查'),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedDestination,
            onDestinationSelected: _selectDestination,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('概况'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('账号与网络'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article),
                label: Text('诊断日志'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedDestination == 0
                ? _buildOverview(context)
                : _selectedDestination == 1
                ? WindowsSettingsPage(
                    configuration: widget.configuration ?? configManager,
                  )
                : const WindowsLogsPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final state = _state;
    final presentation = state.presentation;
    final userInfo = state.isOnline && state.userInfo?.isOnline == true
        ? state.userInfo
        : null;

    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('网络概况', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  '查看当前认证状态、网络连接和账号使用情况。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatusCard(context, presentation),
                const SizedBox(height: 20),
                Text('网络信息', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _buildMetrics(context, userInfo),
                const SizedBox(height: 20),
                _buildDevicesCard(context, userInfo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    AuthStatusPresentation presentation,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _state.isOnline
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: statusColor, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_state.reason != AuthenticationReason.missingConfig &&
                          presentation.detail != null &&
                          presentation.detail != presentation.title) ...[
                        const SizedBox(height: 4),
                        Text(presentation.detail!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (presentation.actionHint != null) ...[
              const SizedBox(height: 12),
              Text(
                presentation.actionHint!,
                style: TextStyle(color: colorScheme.primary),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _StatusChip(
                  icon: Icons.wifi,
                  label: widget.wifiConnected ? 'Wi-Fi 已连接' : '未连接 Wi-Fi',
                ),
                _StatusChip(
                  icon: Icons.monitor_heart_outlined,
                  label: widget.monitoringEnabled ? '正在监控' : '未监控',
                ),
              ],
            ),
            if (_state.reason == AuthenticationReason.missingConfig) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _selectDestination(1),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('设置账号和认证参数'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(BuildContext context, RadUserInfo? userInfo) {
    final emptyDetail = userInfo == null ? '在线确认后显示' : '认证服务器未提供此项数据';
    final metrics = <_WindowsMetric>[
      _WindowsMetric(
        label: 'IP 地址',
        value:
            _networkValue(userInfo?.onlineIp) ??
            _networkValue(userInfo?.clientIp),
        emptyDetail: emptyDetail,
      ),
      _WindowsMetric(
        label: '本次流量',
        value: _formatBytes(userInfo?.allBytes),
        emptyDetail: emptyDetail,
      ),
      _WindowsMetric(
        label: '累计流量',
        value: _formatBytes(userInfo?.sumBytes),
        emptyDetail: emptyDetail,
      ),
      _WindowsMetric(
        label: '累计在线时长',
        value: _formatDuration(userInfo?.sumSeconds),
        emptyDetail: emptyDetail,
      ),
      _WindowsMetric(
        label: '在线设备',
        value: userInfo == null ? null : _formatOnlineDeviceCount(userInfo),
        emptyDetail: emptyDetail,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = availableWidth >= 780
            ? 3
            : availableWidth >= 520
            ? 2
            : 1;
        final itemWidth = (availableWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: itemWidth,
                child: _MetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDevicesCard(BuildContext context, RadUserInfo? userInfo) {
    final devices =
        userInfo?.onlineDeviceDetail?.values.toList() ?? const <OnlineDevice>[];
    final currentAddresses = userInfo == null
        ? const <String>{}
        : _currentDeviceAddresses(userInfo);
    final canKickDevices =
        widget.onKickDevice != null && currentAddresses.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('在线设备详情', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (userInfo == null)
              const Text('设备信息将在认证确认后显示。')
            else if (devices.isEmpty)
              const Text('认证已确认，服务端暂未提供设备明细。')
            else ...[
              if (currentAddresses.isEmpty) ...[
                Text(
                  '无法识别本机设备，已隐藏踢下线操作。',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
              ],
              for (final device in devices) ...[
                Builder(
                  builder: (context) {
                    final addresses = _deviceAddresses(device);
                    final isCurrent = addresses.any(currentAddresses.contains);
                    final targetAddress = addresses.isEmpty
                        ? null
                        : addresses.first;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.devices_outlined),
                      title: Text(_deviceName(device)),
                      subtitle: Text(_deviceAddress(device)),
                      trailing: isCurrent
                          ? const Chip(label: Text('本机'))
                          : canKickDevices && targetAddress != null
                          ? TextButton(
                              onPressed: _deviceOperationInProgress
                                  ? null
                                  : () => _confirmKickDevice(targetAddress),
                              child: const Text('踢下线'),
                            )
                          : null,
                    );
                  },
                ),
                if (device != devices.last) const Divider(height: 1),
              ],
            ],
            if (userInfo != null && widget.onLogout != null) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _deviceOperationInProgress ? null : _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('注销当前连接'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _deviceName(OnlineDevice device) {
    final osName = device.osName?.trim() ?? '';
    if (osName.isNotEmpty) return osName;
    final className = device.className?.trim() ?? '';
    return className.isNotEmpty ? className : '未知设备';
  }

  String _deviceAddress(OnlineDevice device) {
    final addresses = _deviceAddresses(device);
    return addresses.isEmpty ? '暂无地址信息' : addresses.join(' · ');
  }

  List<String> _deviceAddresses(OnlineDevice device) {
    final ip = _networkValue(device.ip);
    final ip6 = _networkValue(device.ip6);
    return <String>[if (ip != null) ip, if (ip6 != null) ip6];
  }

  Set<String> _currentDeviceAddresses(RadUserInfo userInfo) {
    final addresses = <String>{};
    for (final value in <String?>[
      userInfo.clientIp,
      userInfo.onlineIp,
      userInfo.onlineIp6,
    ]) {
      final address = _networkValue(value);
      if (address != null) addresses.add(address);
    }
    return addresses;
  }

  Future<void> _confirmKickDevice(String targetAddress) async {
    final kickDevice = widget.onKickDevice;
    if (_deviceOperationInProgress || kickDevice == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认踢设备'),
        content: Text('确定要将设备 $targetAddress 下线吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认踢'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deviceOperationInProgress = true);
    try {
      final result = await kickDevice(targetAddress);
      if (!mounted) return;
      _showKickOutcome(targetAddress, result);
      if (result.outcome == DmOutcome.kicked) {
        try {
          await widget.onManualCheck();
        } catch (_) {
          if (mounted) {
            _showOperationMessage(
              '已踢掉 $targetAddress，但刷新设备状态失败',
              Theme.of(context).colorScheme.tertiary,
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        _showOperationMessage('踢设备失败，请重试', Theme.of(context).colorScheme.error);
      }
    } finally {
      if (mounted) setState(() => _deviceOperationInProgress = false);
    }
  }

  Future<void> _confirmLogout() async {
    final logout = widget.onLogout;
    if (_deviceOperationInProgress || logout == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认注销'),
        content: const Text('确定要注销当前校园网连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认注销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deviceOperationInProgress = true);
    try {
      final result = await logout();
      if (!mounted) return;
      final colorScheme = Theme.of(context).colorScheme;
      _showOperationMessage(
        result.accepted
            ? '已要求注销'
            : result.reason == null
            ? '注销失败，请重试'
            : '注销失败：${result.reason}',
        result.accepted ? colorScheme.tertiary : colorScheme.error,
      );
    } catch (_) {
      if (mounted) {
        _showOperationMessage('注销失败，请重试', Theme.of(context).colorScheme.error);
      }
    } finally {
      if (mounted) setState(() => _deviceOperationInProgress = false);
    }
  }

  void _showKickOutcome(String targetAddress, DmKickResult result) {
    final colorScheme = Theme.of(context).colorScheme;
    final (message, color) = switch (result.outcome) {
      DmOutcome.kicked => ('已踢掉 $targetAddress', colorScheme.primary),
      DmOutcome.accepted => (
        '已要求 $targetAddress 下线，但未能确认它已断开',
        colorScheme.tertiary,
      ),
      DmOutcome.rejected => (
        result.reason == null ? '踢人失败：服务器返回错误' : '踢人失败：${result.reason}',
        colorScheme.error,
      ),
    };
    _showOperationMessage(message, color);
  }

  void _showOperationMessage(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  String? _networkValue(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _formatOnlineDeviceCount(RadUserInfo userInfo) {
    final total = int.tryParse(userInfo.onlineDeviceTotal ?? '');
    if (total != null) return '$total 台';
    final devices = userInfo.onlineDeviceDetail;
    return devices == null ? null : '${devices.length} 台';
  }

  String? _formatBytes(int? bytes) {
    if (bytes == null) return null;
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var index = bytes.bitLength ~/ 10;
    if (index >= suffixes.length) index = suffixes.length - 1;
    final size = bytes / (1 << (index * 10));
    return '${size.toStringAsFixed(2)} ${suffixes[index]}';
  }

  String? _formatDuration(int? seconds) {
    if (seconds == null) return null;
    if (seconds <= 0) return '0 分钟';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days} 天 ${hours} 小时 ${minutes} 分';
    if (hours > 0) return '${hours} 小时 ${minutes} 分';
    return '${minutes} 分钟';
  }

  Widget _buildPopup(
    BuildContext context,
    AuthStatusPresentation presentation,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'LinkUp',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onOpenDetails,
                      child: const Text('打开窗口'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE1E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (presentation.detail != null &&
                          presentation.detail != presentation.title &&
                          presentation.actionHint == null) ...[
                        const SizedBox(height: 6),
                        Text(presentation.detail!),
                      ],
                      if (presentation.actionHint != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          presentation.actionHint!,
                          style: TextStyle(color: colorScheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, size: 18),
                      const SizedBox(width: 8),
                      Text(widget.wifiConnected ? 'Wi-Fi 已连接' : '未连接 Wi-Fi'),
                      const Spacer(),
                      Text(widget.monitoringEnabled ? '正在监控' : '未监控'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: widget.onManualCheck,
                  icon: const Icon(Icons.refresh),
                  label: const Text('立即检查'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _WindowsMetric {
  const _WindowsMetric({
    required this.label,
    required this.value,
    required this.emptyDetail,
  });

  final String label;
  final String? value;
  final String emptyDetail;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _WindowsMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(metric.value ?? '暂无数据', style: theme.textTheme.titleLarge),
            if (metric.value == null) ...[
              const SizedBox(height: 4),
              Text(
                metric.emptyDetail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
