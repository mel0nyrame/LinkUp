import 'dart:async';

import 'package:flutter/material.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';

/// Windows 的最小认证入口；完整桌面窗口由后续票据补齐。
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
  });

  final AuthRuntimeState initialState;
  final Stream<AuthRuntimeState> states;
  final Future<void> Function() onManualCheck;
  final bool compact;
  final bool wifiConnected;
  final bool monitoringEnabled;
  final VoidCallback? onOpenDetails;

  @override
  State<WindowsHome> createState() => _WindowsHomeState();
}

class _WindowsHomeState extends State<WindowsHome> {
  late AuthRuntimeState _state = widget.initialState;
  StreamSubscription<AuthRuntimeState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _state.presentation;
    if (widget.compact) return _buildPopup(context, presentation);

    return Scaffold(
      appBar: AppBar(title: const Text('LinkUp')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  presentation.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                if (_state.reason != AuthenticationReason.missingConfig &&
                    presentation.detail != null) ...[
                  const SizedBox(height: 8),
                  Text(presentation.detail!),
                ],
                if (presentation.actionHint != null) ...[
                  const SizedBox(height: 8),
                  Text(presentation.actionHint!),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.onManualCheck,
                  child: const Text('立即检查'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
