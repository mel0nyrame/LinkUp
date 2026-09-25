import 'dart:async';

import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 后台认证运行时在 Dart 侧的唯一 owner。
///
/// 它持有唯一的 [AuthenticationCoordinator]、订阅状态流并把状态发布给宿主，
/// 同时执行宿主通过 callback dispatcher 下发的命令。UI、通知和平台入口都路由
/// 到这里，不允许出现第二个协调器。
class AuthRuntimeController {
  AuthRuntimeController({required this.coordinator, required this.host});

  static const String commandStart = 'start';
  static const String commandStop = 'stop';
  static const String commandManualCheck = 'manualCheck';
  static const String commandLogout = 'logout';
  static const String commandKickDevice = 'kickDevice';
  static const String commandConfigurationChanged = 'configurationChanged';

  final AuthenticationCoordinator coordinator;
  final AuthRuntimeHost host;

  StreamSubscription<AuthenticationState>? _subscription;
  bool _disposed = false;

  /// 开始把协调器状态转发给宿主，并立即发布当前状态。
  void subscribe() {
    _subscription ??= coordinator.states.listen(_publish);
    _publish(coordinator.state);
  }

  void _publish(AuthenticationState state) {
    if (_disposed) return;
    unawaited(host.publishState(AuthRuntimeState.fromCoordinatorState(state)));
  }

  /// 执行一条宿主命令，返回需要回传给调用方的结果。
  Future<Object?> execute(String command, [Map<String, Object?>? args]) async {
    if (_disposed) return null;

    switch (command) {
      case commandStart:
        await coordinator.start();
        return null;
      case commandStop:
        await coordinator.stop();
        return null;
      case commandManualCheck:
        await coordinator.manualCheck();
        return null;
      case commandLogout:
        return coordinator.logout();
      case commandKickDevice:
        final ip = args?['ip'];
        if (ip is! String || ip.isEmpty) return false;
        return coordinator.kickDevice(ip);
      case commandConfigurationChanged:
        await coordinator.configurationChanged(
          hasConfig: args?['hasConfig'] == true,
        );
        return null;
      default:
        await LogUtil.warning('收到未知的认证运行时命令');
        return null;
    }
  }

  /// 停止协调器并释放 HTTP client、Portal 缓存和状态流。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await coordinator.dispose();
  }
}
