import 'package:flutter/material.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';

/// Only the status needed by the tray window crosses into its UI isolate.
class WindowsPopupState {
  const WindowsPopupState({
    required this.title,
    required this.detail,
    required this.wifi,
    required this.authentication,
    required this.monitoring,
    required this.tone,
  });

  final String title;
  final String detail;
  final String wifi;
  final String authentication;
  final String monitoring;
  final String tone;

  factory WindowsPopupState.fromRuntime(
    AuthRuntimeState state, {
    required bool wifiConnected,
    required String? wifiName,
    required bool monitoringEnabled,
  }) {
    final presentation = state.presentation;
    final name = wifiName?.trim() ?? '';
    final wifi = !wifiConnected
        ? '未连接 Wi-Fi'
        : name.isEmpty
        ? 'Wi-Fi 已连接，名称不可用'
        : name;
    final waitingForWifi =
        state.status == AuthenticationStatus.offline ||
        state.reason == AuthenticationReason.wifiUnavailable;
    final missingConfig = state.reason == AuthenticationReason.missingConfig;
    final working =
        state.status == AuthenticationStatus.checking ||
        state.status == AuthenticationStatus.authenticating;
    final failed =
        state.status == AuthenticationStatus.failed ||
        state.status == AuthenticationStatus.backingOff ||
        state.status == AuthenticationStatus.cancelled ||
        state.status == AuthenticationStatus.stale;
    final authenticationFailed = failed && !missingConfig && !waitingForWifi;
    final String authentication;
    final String tone;
    if (state.isOnline) {
      authentication = '已确认在线';
      tone = 'online';
    } else if (working) {
      authentication = presentation.title;
      tone = 'working';
    } else if (missingConfig) {
      authentication = '未配置';
      tone = 'idle';
    } else if (waitingForWifi) {
      authentication = '等待 Wi-Fi';
      tone = 'idle';
    } else if (authenticationFailed) {
      authentication = '认证失败';
      tone = 'attention';
    } else {
      authentication = '尚未开始';
      tone = 'idle';
    }
    final detail =
        presentation.actionHint ??
        switch (state.status) {
          AuthenticationStatus.online ||
          AuthenticationStatus.alreadyOnline => '已确认连接校园网',
          AuthenticationStatus.checking => '正在检查网络状态',
          AuthenticationStatus.authenticating => '正在登录校园网',
          AuthenticationStatus.offline => '请连接 Wi-Fi 后重试',
          AuthenticationStatus.backingOff =>
            state.retryAfterSeconds == null
                ? '稍后自动重试'
                : '${state.retryAfterSeconds} 秒后自动重试',
          AuthenticationStatus.failed ||
          AuthenticationStatus.cancelled ||
          AuthenticationStatus.stale => '认证未完成，将自动重试',
          AuthenticationStatus.stopped => '等待启动监控',
        };

    return WindowsPopupState(
      title: waitingForWifi
          ? '等待 Wi-Fi'
          : authenticationFailed && presentation.title == '未连接'
          ? '认证失败'
          : presentation.title,
      detail: detail,
      wifi: wifi,
      authentication: authentication,
      monitoring: monitoringEnabled ? '正在监控' : '未监控',
      tone: tone,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'title': title,
    'detail': detail,
    'wifi': wifi,
    'authentication': authentication,
    'monitoring': monitoring,
    'tone': tone,
  };

  factory WindowsPopupState.fromMap(Map<Object?, Object?> map) =>
      WindowsPopupState(
        title: map['title'] as String? ?? '未连接',
        detail: map['detail'] as String? ?? '等待下一次检查',
        wifi: map['wifi'] as String? ?? '未连接 Wi-Fi',
        authentication: map['authentication'] as String? ?? '尚未开始',
        monitoring: map['monitoring'] as String? ?? '未监控',
        tone: map['tone'] as String? ?? 'idle',
      );
}

class WindowsStatusPopup extends StatelessWidget {
  const WindowsStatusPopup({
    super.key,
    required this.state,
    required this.onManualCheck,
    required this.onOpenDetails,
    required this.onClose,
  });

  final WindowsPopupState state;
  final VoidCallback onManualCheck;
  final VoidCallback onOpenDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = state.tone == 'attention'
        ? scheme.error
        : state.tone == 'idle'
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final statusIcon = state.tone == 'online'
        ? Icons.check_circle
        : state.tone == 'working'
        ? Icons.sync
        : state.tone == 'attention'
        ? Icons.error_outline
        : Icons.wifi_off;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi, color: scheme.primary, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'LinkUp',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭浮层',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(statusIcon, color: accent, size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.detail,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _StatusRow(icon: Icons.wifi, label: 'Wi-Fi', value: state.wifi),
                _StatusRow(
                  icon: Icons.verified_user_outlined,
                  label: '认证',
                  value: state.authentication,
                ),
                _StatusRow(
                  icon: Icons.monitor_heart_outlined,
                  label: '监控',
                  value: state.monitoring,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onManualCheck,
                        child: const Text('立即检查'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onOpenDetails,
                        child: const Text('详细信息'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Icon(icon, size: 19, color: scheme.primary),
              const SizedBox(width: 10),
              SizedBox(width: 52, child: Text(label)),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}
