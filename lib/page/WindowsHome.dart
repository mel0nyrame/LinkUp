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
  });

  final AuthRuntimeState initialState;
  final Stream<AuthRuntimeState> states;
  final Future<void> Function() onManualCheck;

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
}
