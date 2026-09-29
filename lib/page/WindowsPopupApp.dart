import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:LinkUp/page/WindowsStatusPopup.dart';

/// Runs only in the tray window's UI isolate; it never owns authentication.
class WindowsPopupApp extends StatefulWidget {
  const WindowsPopupApp({super.key});

  static const String channelName = 'com.mel0ny.linkup/windowsPopup';
  static const String methodGetState = 'getState';
  static const String methodReady = 'ready';
  static const String methodUpdateState = 'updateState';
  static const String methodManualCheck = 'manualCheck';
  static const String methodOpenDetails = 'openDetails';
  static const String methodHidePopup = 'hidePopup';

  @override
  State<WindowsPopupApp> createState() => _WindowsPopupAppState();
}

class _WindowsPopupAppState extends State<WindowsPopupApp> {
  static const _channel = MethodChannel(WindowsPopupApp.channelName);

  WindowsPopupState? _state;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == WindowsPopupApp.methodUpdateState &&
          call.arguments is Map) {
        _update(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final snapshot = await _channel.invokeMapMethod<Object?, Object?>(
        WindowsPopupApp.methodGetState,
      );
      if (!mounted || snapshot == null) return;
      _update(snapshot);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _channel.invokeMethod<void>(WindowsPopupApp.methodReady);
      });
    });
  }

  void _update(Map<Object?, Object?> snapshot) {
    if (mounted) {
      setState(() => _state = WindowsPopupState.fromMap(snapshot));
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkUp 状态',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: _state == null
          ? const SizedBox.shrink()
          : WindowsStatusPopup(
              state: _state!,
              onManualCheck: () => _channel.invokeMethod<void>(
                WindowsPopupApp.methodManualCheck,
              ),
              onOpenDetails: () => _channel.invokeMethod<void>(
                WindowsPopupApp.methodOpenDetails,
              ),
              onClose: () =>
                  _channel.invokeMethod<void>(WindowsPopupApp.methodHidePopup),
            ),
    );
  }
}
