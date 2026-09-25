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
///
/// 运行时的释放由宿主销毁后台 FlutterEngine 表达：isolate 结束即释放 HTTP
/// client、Portal 缓存与调度，本类不另设拆卸入口。
class AuthRuntimeController {
  AuthRuntimeController({required this.coordinator, required this.host});

  static const String commandStart = 'start';
  static const String commandStop = 'stop';
  static const String commandManualCheck = 'manualCheck';
  static const String commandLogout = 'logout';
  static const String commandKickDevice = 'kickDevice';
  static const String commandConfigurationChanged = 'configurationChanged';
  static const String commandNetworkChanged = 'networkChanged';

  /// 本运行时接受的全部命令。宿主下发的名字必须在此集合内。
  static const Set<String> declaredCommands = <String>{
    commandStart,
    commandStop,
    commandManualCheck,
    commandLogout,
    commandKickDevice,
    commandConfigurationChanged,
    commandNetworkChanged,
  };

  final AuthenticationCoordinator coordinator;
  final AuthRuntimeHost host;

  StreamSubscription<AuthenticationState>? _subscription;

  /// 开始把协调器状态转发给宿主，并立即发布当前状态。
  void subscribe() {
    _subscription ??= coordinator.states.listen(_publish);
    _publish(coordinator.state);
  }

  void _publish(AuthenticationState state) {
    unawaited(host.publishState(AuthRuntimeState.fromCoordinatorState(state)));
  }

  /// 执行一条宿主命令，返回需要回传给调用方的结果。
  ///
  /// 返回 `null` 表示该命令没有结果，宿主不会为它分配请求标识。
  Future<Object?> execute(String command, [Map<String, Object?>? args]) async {
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
      case commandNetworkChanged:
        // 平台的 Wi-Fi 可用性事件，只描述网络条件，不携带认证决策。
        await coordinator.networkChanged(connected: args?['connected'] == true);
        return null;
      default:
        await LogUtil.warning('收到未知的认证运行时命令');
        return null;
    }
  }
}
