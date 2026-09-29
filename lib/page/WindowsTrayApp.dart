import 'dart:async';

import 'package:flutter/material.dart';
import 'package:LinkUp/page/WindowsHome.dart';
import 'package:LinkUp/page/WindowsStatusPopup.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/WindowsAuthRuntime.dart';
import 'package:LinkUp/utils/WindowsTray.dart';

class WindowsTrayApp extends StatefulWidget {
  const WindowsTrayApp({
    super.key,
    required this.runtime,
    required this.tray,
    this.checkForUpdatesOnStartup = true,
  });

  final WindowsAuthRuntime runtime;
  final WindowsTrayClient tray;
  final bool checkForUpdatesOnStartup;

  @override
  State<WindowsTrayApp> createState() => _WindowsTrayAppState();
}

class _WindowsTrayAppState extends State<WindowsTrayApp> {
  late AuthRuntimeState _state = widget.runtime.state;
  late bool _wifiConnected = widget.runtime.wifiConnected;
  late String? _wifiName = widget.runtime.wifiName;
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
      unawaited(_publishPopupState());
    });
    _wifiSubscription = widget.runtime.wifiStates.listen((connected) {
      if (mounted) {
        setState(() {
          _wifiConnected = connected;
          _wifiName = widget.runtime.wifiName;
        });
        unawaited(_publishPopupState());
      }
    });
    unawaited(widget.tray.setTooltip(_tooltipFor(_state)));
    unawaited(_attachTray());
  }

  Future<void> _attachTray() async {
    try {
      await _publishPopupState();
      await widget.tray.attach();
    } catch (error, stackTrace) {
      await LogUtil.error('注册 Windows 托盘图标失败', error, stackTrace);
    }
  }

  String _tooltipFor(AuthRuntimeState state) =>
      'LinkUp · ${state.presentation.title}';

  Future<void> _publishPopupState() => widget.tray.setPopupState(
    WindowsPopupState.fromRuntime(
      _state,
      wifiConnected: _wifiConnected,
      wifiName: _wifiName,
      monitoringEnabled: _monitoringEnabled,
    ).toMap(),
  );

  Future<void> _handleTrayAction(WindowsTrayAction action) async {
    switch (action) {
      case WindowsTrayAction.manualCheck:
        await widget.runtime.manualCheck();
        break;
      case WindowsTrayAction.exitRequested:
        await _exit();
        break;
      case WindowsTrayAction.openMain:
        setState(() => _selectedDestination = 0);
        break;
      case WindowsTrayAction.openSettings:
        setState(() => _selectedDestination = 1);
        break;
      case WindowsTrayAction.openLogs:
        setState(() => _selectedDestination = 2);
        break;
    }
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
      home: WindowsHome(
        initialState: _state,
        states: widget.runtime.states,
        wifiConnected: _wifiConnected,
        wifiName: _wifiName,
        monitoringEnabled: _monitoringEnabled,
        checkForUpdatesOnStartup: widget.checkForUpdatesOnStartup,
        onManualCheck: widget.runtime.manualCheck,
        onLogout: widget.runtime.logout,
        onKickDevice: widget.runtime.kickDevice,
        selectedDestination: _selectedDestination,
        onDestinationChanged: (destination) {
          setState(() => _selectedDestination = destination);
        },
      ),
    );
  }
}
