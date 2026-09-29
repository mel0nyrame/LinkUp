import 'package:flutter/services.dart';

enum WindowsTrayAction {
  openMain,
  openSettings,
  openLogs,
  manualCheck,
  exitRequested,
}

class WindowsTrayClient {
  WindowsTrayClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.mel0ny.linkup/windowsTray';
  static const String methodAttach = 'attach';
  static const String methodSetTooltip = 'setTooltip';
  static const String methodSetPopupState = 'setPopupState';
  static const String methodExitComplete = 'exitComplete';
  static const String methodOnAction = 'onAction';

  final MethodChannel _channel;
  Future<void> Function(WindowsTrayAction action)? onAction;

  Future<void> attach() async {
    _channel.setMethodCallHandler(_handleHostCall);
    await _channel.invokeMethod<void>(methodAttach);
  }

  Future<void> setTooltip(String text) async {
    try {
      await _channel.invokeMethod<void>(methodSetTooltip, text);
    } on PlatformException {
      // The tray can restart independently of the Flutter view.
    } on MissingPluginException {
      // Tests and non-Windows hosts have no native tray implementation.
    }
  }

  Future<void> setPopupState(Map<String, Object?> state) =>
      _channel.invokeMethod<void>(methodSetPopupState, state);

  Future<void> completeExit() =>
      _channel.invokeMethod<void>(methodExitComplete);

  Future<Object?> _handleHostCall(MethodCall call) async {
    if (call.method != methodOnAction || call.arguments is! String) return null;

    final action = WindowsTrayAction.values.where(
      (value) => value.name == call.arguments,
    );
    if (action.isEmpty) return null;

    await onAction?.call(action.single);
    return null;
  }
}
