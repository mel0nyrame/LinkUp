import 'dart:async';

import 'package:flutter/services.dart';
import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/RuntimeContract.g.dart';

class AuthRuntimeUnavailableException implements Exception {
  const AuthRuntimeUnavailableException();
}

/// UI 侧对后台认证运行时的窄客户端。
///
/// 概况页和设置页只通过它订阅状态、发送命令。Activity 的 FlutterEngine 不创建
/// 协调器，也不创建认证周期 Timer，因此不会和前台服务里的运行时竞争。
class AuthRuntimeClient {
  AuthRuntimeClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(uiChannelName);

  /// 必须与 Kotlin 侧 `MainActivity.UI_CHANNEL` 一致。
  static const String uiChannelName = RuntimeContract.uiChannel;

  final MethodChannel _channel;
  final StreamController<AuthRuntimeState> _states =
      StreamController<AuthRuntimeState>.broadcast();
  bool _attached = false;
  bool _receivedState = false;

  Stream<AuthRuntimeState> get states => _states.stream;

  /// 订阅状态流并取回最近一次发布的状态。
  Future<void> attach() async {
    if (_attached) return;
    _channel.setMethodCallHandler(_handleHostCall);
    _attached = true;
    final latest = await _invoke(RuntimeContract.methodAttach, null);
    // 宿主先推送再回包，因此回包只用于补上尚未收到过的首个状态，避免旧值
    // 覆盖已经到达的更新。
    if (latest is Map && !_receivedState) _addState(latest);
  }

  /// 取消订阅。Activity 销毁后运行时继续工作，重新进入时再次 [attach]。
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    await _invoke(RuntimeContract.methodDetach, null);
    _channel.setMethodCallHandler(null);
  }

  /// 请求后台运行时立即开始监控。
  ///
  /// Activity 刚变为可见时使用，让概况页立即反映一次真实检查结果。
  Future<void> start() => _fire(AuthRuntimeController.commandStart);

  Future<void> manualCheck() => _fire(AuthRuntimeController.commandManualCheck);

  /// 用户修改认证配置后通知运行时，使其取消旧调度并重新评估监控。
  Future<void> configurationChanged() =>
      _fire(AuthRuntimeController.commandConfigurationChanged);

  /// 注销结果决定 UI 提示，因此需要命令回传值。
  Future<bool> logout() async =>
      await _command(AuthRuntimeController.commandLogout) == true;

  /// 踢设备结果决定 UI 提示，因此需要命令回传值。
  ///
  /// 运行时回传 [DmOutcome] 的名字。无法识别时如实报「已受理但未确认」，因为此时既
  /// 不能声称踢掉了，也不能断言服务器拒绝了请求。
  Future<DmOutcome> kickDevice(String ip) async {
    final value = await _command(
      AuthRuntimeController.commandKickDevice,
      <String, Object?>{RuntimeContract.keyIp: ip},
    );
    for (final outcome in DmOutcome.values) {
      if (outcome.name == value) return outcome;
    }
    await LogUtil.warning('认证运行时回传了无法识别的踢设备结果');
    return DmOutcome.accepted;
  }

  Future<void> _fire(String name, [Map<String, Object?>? args]) async {
    await _invoke(RuntimeContract.methodFireCommand, <String, Object?>{
      RuntimeContract.keyName: name,
      RuntimeContract.keyArgs: args,
    });
  }

  Future<Object?> _command(String name, [Map<String, Object?>? args]) {
    return _invoke(RuntimeContract.methodCommand, <String, Object?>{
      RuntimeContract.keyName: name,
      RuntimeContract.keyArgs: args,
    }, throwOnFailure: true);
  }

  Future<Object?> _invoke(
    String method,
    Object? arguments, {
    bool throwOnFailure = false,
  }) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } catch (error, stackTrace) {
      await LogUtil.error('认证运行时命令失败: $method', error, stackTrace);
      if (throwOnFailure) throw const AuthRuntimeUnavailableException();
      return null;
    }
  }

  Future<Object?> _handleHostCall(MethodCall call) async {
    if (call.method == RuntimeContract.methodOnState) {
      final payload = call.arguments;
      if (payload is Map) _addState(payload);
    }
    return null;
  }

  void _addState(Map<dynamic, dynamic> payload) {
    if (_states.isClosed) return;
    _receivedState = true;
    _states.add(AuthRuntimeState.fromMap(payload));
  }

  Future<void> dispose() async {
    await detach();
    await _states.close();
  }
}
