import 'dart:async';

import 'package:flutter/material.dart';
import 'package:LinkUp/page/WindowsHome.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/WindowsAuthRuntime.dart';
import 'package:LinkUp/utils/WindowsTray.dart';

class WindowsTrayApp extends StatefulWidget {
  const WindowsTrayApp({super.key, required this.runtime, required this.tray});

  final WindowsAuthRuntime runtime;
  final WindowsTrayClient tray;

  @override
  State<WindowsTrayApp> createState() => _WindowsTrayAppState();
}

class _WindowsTrayAppState extends State<WindowsTrayApp> {
  late AuthRuntimeState _state = widget.runtime.state;
  late bool _wifiConnected = widget.runtime.wifiConnected;
  late bool _monitoringEnabled = widget.runtime.monitoringEnabled;
  int _selectedDestination = 0;
  StreamSubscription<AuthRuntimeState>? _stateSubscription;
  StreamSubscription<bool>? _wifiSubscription;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    widget.tray.onAction = _handleTrayAction;
    _stateSubscription = widget.runtime.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _state = state;
        _monitoringEnabled = widget.runtime.monitoringEnabled;
      });
      unawaited(widget.tray.setTooltip(_tooltipFor(state)));
    });
    _wifiSubscription = widget.runtime.wifiStates.listen((connected) {
      if (mounted) setState(() => _wifiConnected = connected);
    });
    unawaited(widget.tray.setTooltip(_tooltipFor(_state)));
    unawaited(_attachTray());
  }

  Future<void> _attachTray() async {
    try {
      await widget.tray.attach();
    } catch (error, stackTrace) {
      await LogUtil.error('注册 Windows 托盘图标失败', error, stackTrace);
    }
  }

  String _tooltipFor(AuthRuntimeState state) =>
      'LinkUp · ${state.presentation.title}';

  Future<void> _handleTrayAction(WindowsTrayAction action) async {
    switch (action) {
      case WindowsTrayAction.manualCheck:
        await widget.runtime.manualCheck();
        break;
      case WindowsTrayAction.exitRequested:
        await _exit();
        break;
      case WindowsTrayAction.togglePopup:
      case WindowsTrayAction.hidePopup:
        break;
      case WindowsTrayAction.openMain:
        setState(() => _selectedDestination = 0);
        break;
      case WindowsTrayAction.openSettings:
        setState(() => _selectedDestination = 1);
        break;
      case WindowsTrayAction.openLogs:
        break;
    }
  }

  Future<void> _openDetails() async {
    setState(() => _selectedDestination = 0);
    await widget.tray.showMain();
  }

  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await widget.runtime.dispose();
    } catch (error, stackTrace) {
      await LogUtil.error('退出时释放 Windows 认证运行时失败', error, stackTrace);
    }
    await widget.tray.completeExit();
  }

  @override
  void dispose() {
    widget.tray.onAction = null;
    unawaited(_stateSubscription?.cancel());
    unawaited(_wifiSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkUp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: ValueListenableBuilder<bool>(
        valueListenable: widget.tray.popupVisible,
        builder: (context, popupVisible, _) => WindowsHome(
          initialState: _state,
          states: widget.runtime.states,
          compact: popupVisible,
          wifiConnected: _wifiConnected,
          monitoringEnabled: _monitoringEnabled,
          onManualCheck: widget.runtime.manualCheck,
          onLogout: widget.runtime.logout,
          onKickDevice: widget.runtime.kickDevice,
          onOpenDetails: _openDetails,
          selectedDestination: _selectedDestination,
          onDestinationChanged: (destination) {
            setState(() => _selectedDestination = destination);
          },
        ),
      ),
    );
  }
}
