import 'package:flutter/services.dart';

class WindowsAutoStartClient {
  WindowsAutoStartClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.mel0ny.linkup/windowsStartup';
  static const String methodGetEnabled = 'getEnabled';
  static const String methodSetEnabled = 'setEnabled';

  final MethodChannel _channel;

  Future<bool> getEnabled() async {
    final enabled = await _channel.invokeMethod<bool>(methodGetEnabled);
    if (enabled == null) throw StateError('Windows 启动项没有返回状态');
    return enabled;
  }

  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>(methodSetEnabled, enabled);
}
