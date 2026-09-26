import 'package:flutter/services.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 后台认证运行时向 Android 前台服务发布状态的窄桥。
///
/// 桥只负责搬运状态与就绪通知，不包含任何认证协议或状态机规则。
abstract interface class AuthRuntimeHost {
  /// 命令处理器注册完成后通知宿主，可以发送排队的命令。
  Future<void> publishReady();

  /// 发布一次状态变化。宿主用它更新常驻通知并转发给可见的 UI。
  Future<void> publishState(AuthRuntimeState state);
}

/// 生产实现：把状态发布到前台服务的 MethodChannel。
class MethodChannelAuthRuntimeHost implements AuthRuntimeHost {
  MethodChannelAuthRuntimeHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(hostChannelName);

  /// 必须与 Kotlin 侧 `AuthRuntimeBridge.HOST_CHANNEL` 一致。
  static const String hostChannelName = 'com.mel0ny.linkup/authRuntime';

  final MethodChannel _channel;

  @override
  Future<void> publishReady() async {
    await _invoke('ready', <String, Object?>{});
  }

  @override
  Future<void> publishState(AuthRuntimeState state) async {
    await _invoke('state', state.toMap());
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error, stackTrace) {
      // 宿主未注册通道时认证运行时仍应继续工作，只是没有常驻通知和 UI。
      await LogUtil.warning('发布认证运行时状态失败: $method');
      LogUtil.error('发布认证运行时状态异常', error, stackTrace);
    }
  }
}
