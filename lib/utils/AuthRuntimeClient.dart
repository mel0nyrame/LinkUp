import 'dart:async';

import 'package:flutter/services.dart';
import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// UI 侧对后台认证运行时的窄客户端。
///
/// 概况页和设置页只通过它订阅状态、发送命令。Activity 的 FlutterEngine 不创建
/// 协调器，也不创建认证周期 Timer，因此不会和前台服务里的运行时竞争。
class AuthRuntimeClient {
  AuthRuntimeClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(uiChannelName);

  /// 必须与 Kotlin 侧 `MainActivity.UI_CHANNEL` 一致。
  static const String uiChannelName = 'com.mel0ny.linkup/authUi';

  final MethodChannel _channel;
  final StreamController<AuthRuntimeState> _states =
      StreamController<AuthRuntimeState>.broadcast();
  bool _attached = false;

  Stream<AuthRuntimeState> get states => _states.stream;

  /// 订阅状态流并取回最近一次发布的状态。
  Future<void> attach() async {
    if (_attached) return;
    _channel.setMethodCallHandler(_handleHostCall);
    _attached = true;
    final latest = await _invoke('attach');
    if (latest is Map) _addState(latest);
  }

  /// 取消订阅。Activity 销毁后运行时继续工作，重新进入时再次 [attach]。
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    await _invoke('detach');
    _channel.setMethodCallHandler(null);
  }

  /// 请求后台运行时立即开始监控。
  ///
  /// Activity 刚变为可见时使用，让概况页立即反映一次真实检查结果。
  Future<bool> start() => _command(AuthRuntimeController.commandStart);

  Future<bool> manualCheck() =>
      _command(AuthRuntimeController.commandManualCheck);

  Future<bool> logout() => _command(AuthRuntimeController.commandLogout);

  Future<bool> kickDevice(String ip) => _command(
    AuthRuntimeController.commandKickDevice,
    <String, Object?>{'ip': ip},
  );

  Future<bool> configurationChanged({required bool hasConfig}) => _command(
    AuthRuntimeController.commandConfigurationChanged,
    <String, Object?>{'hasConfig': hasConfig},
  );

  Future<bool> _command(String name, [Map<String, Object?>? args]) async {
    final result = await _invoke('command', <String, Object?>{
      'name': name,
      'args': args,
    });
    return result == true;
  }

  Future<Object?> _invoke(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } catch (error, stackTrace) {
      await LogUtil.error('认证运行时命令失败: $method', error, stackTrace);
      return null;
    }
  }

  Future<Object?> _handleHostCall(MethodCall call) async {
    if (call.method == 'onState') {
      final payload = call.arguments;
      if (payload is Map) _addState(payload);
    }
    return null;
  }

  void _addState(Map<dynamic, dynamic> payload) {
    if (_states.isClosed) return;
    _states.add(AuthRuntimeState.fromMap(payload));
  }

  Future<void> dispose() async {
    await detach();
    await _states.close();
  }
}
