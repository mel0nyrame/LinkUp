import 'package:flutter/services.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 后台认证运行时向 Android 前台服务发布状态的窄桥。
///
/// 桥只负责搬运状态与就绪句柄，不包含任何认证协议或状态机规则。
abstract interface class AuthRuntimeHost {
  /// 认证入口就绪后把命令回调句柄交给宿主。
  ///
  /// 宿主随后通过 embedder 的 callback dispatcher 下发启动、停止和手动检查
  /// 等命令，因此后台入口不再依赖 MethodChannel 的处理时序。
  Future<void> publishCommandHandle(int handle);

  /// 发布一次状态变化。宿主用它更新常驻通知并转发给可见的 UI。
  Future<void> publishState(AuthRuntimeState state);

  /// 回传一条带请求标识的命令结果。
  ///
  /// 只有需要返回值的命令才带标识；启动和停止等命令不回传结果。
  Future<void> publishCommandResult(int requestId, Object? value);
}

/// 生产实现：把状态发布到前台服务的 MethodChannel。
class MethodChannelAuthRuntimeHost implements AuthRuntimeHost {
  MethodChannelAuthRuntimeHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(hostChannelName);

  /// 必须与 Kotlin 侧 `AuthRuntimeBridge.HOST_CHANNEL` 一致。
  static const String hostChannelName = 'com.mel0ny.linkup/authRuntime';

  final MethodChannel _channel;

  @override
  Future<void> publishCommandHandle(int handle) async {
    await _invoke('ready', <String, Object?>{'commandHandle': handle});
  }

  @override
  Future<void> publishState(AuthRuntimeState state) async {
    await _invoke('state', state.toMap());
  }

  @override
  Future<void> publishCommandResult(int requestId, Object? value) async {
    await _invoke('commandResult', <String, Object?>{
      'id': requestId,
      'value': value,
    });
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
