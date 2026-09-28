import 'dart:async';

import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/SrunAuthenticationProtocol.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/RuntimeContract.g.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/WindowsWifi.dart';

/// Windows 进程内唯一认证运行时。界面只读状态并发送命令。
class WindowsAuthRuntime implements AuthRuntimeHost {
  WindowsAuthRuntime({
    required AuthenticationCoordinator coordinator,
    required this.configSource,
    this.wifiEvents,
    this.wifiState,
  }) : _coordinator = coordinator {
    _controller = AuthRuntimeController(coordinator: coordinator, host: this);
  }

  static final WindowsWifiNetworkState _productionWifiState =
      WindowsWifiNetworkState();
  static final WindowsWifiChannel _productionWifiChannel = WindowsWifiChannel();

  static SrunAuthenticationProtocol _productionProtocol() =>
      SrunAuthenticationProtocol(
        httpClient: createWindowsWifiHttpClient(_productionWifiChannel),
        ownsInjectedClient: true,
      );

  static final WindowsAuthRuntime production = WindowsAuthRuntime(
    configSource: ConfigUtilSource(),
    wifiEvents: _productionWifiChannel,
    wifiState: _productionWifiState,
    coordinator: AuthenticationCoordinator(
      configSource: ConfigUtilSource(),
      protocol: _productionProtocol(),
      protocolFactory: _productionProtocol,
      networkState: _productionWifiState,
    ),
  );

  final AuthenticationCoordinator _coordinator;
  final AuthenticationConfigSource configSource;
  final WindowsWifiEvents? wifiEvents;
  final WindowsWifiNetworkState? wifiState;
  late final AuthRuntimeController _controller;
  final StreamController<AuthRuntimeState> _states =
      StreamController<AuthRuntimeState>.broadcast(sync: true);
  final StreamController<bool> _wifiStates = StreamController<bool>.broadcast(
    sync: true,
  );
  AuthRuntimeState _state = const AuthRuntimeState.stopped();
  Future<void>? _initializing;
  Future<void> _wifiEventsTail = Future<void>.value();
  bool _monitoringEnabled = false;

  Stream<AuthRuntimeState> get states => _states.stream;
  Stream<bool> get wifiStates => _wifiStates.stream;
  AuthRuntimeState get state => _state;
  bool get wifiConnected => wifiState?.connected ?? false;
  bool get monitoringEnabled => _monitoringEnabled;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _controller.subscribe();
    final events = wifiEvents;
    if (events != null) {
      final snapshot = await events.start(_onWifiChanged);
      wifiState!.apply(snapshot);
      _wifiStates.add(snapshot.connected);
    }
    final present = await _configurationPresent();
    if (present == false) {
      _publishMissingConfig();
    } else if (present == true && events != null) {
      _monitoringEnabled = true;
      await _controller.execute(AuthRuntimeController.commandStart);
    }
  }

  void _onWifiChanged(WindowsWifiSnapshot snapshot) {
    _wifiEventsTail = _wifiEventsTail.then((_) async {
      final changed = wifiState!.apply(snapshot);
      if (changed) _wifiStates.add(snapshot.connected);
      if (changed && await _configurationPresent() == true) {
        await _controller.execute(
          AuthRuntimeController.commandNetworkChanged,
          <String, Object?>{RuntimeContract.keyConnected: snapshot.connected},
        );
      }
    });
  }

  Future<void> manualCheck() async {
    await initialize();
    final present = await _configurationPresent();
    if (present != true) {
      if (present == false) _publishMissingConfig();
      return;
    }
    await _controller.execute(AuthRuntimeController.commandManualCheck);
  }

  Future<DmResult> logout() async {
    await initialize();
    final result = _commandResult(
      await _controller.execute(AuthRuntimeController.commandLogout),
    );
    return DmResult(
      accepted: result.status == DmOutcome.accepted.name,
      errorMessage: result.reason,
    );
  }

  Future<DmKickResult> kickDevice(String ip) async {
    await initialize();
    final result = _commandResult(
      await _controller.execute(
        AuthRuntimeController.commandKickDevice,
        <String, Object?>{RuntimeContract.keyIp: ip},
      ),
    );
    for (final outcome in DmOutcome.values) {
      if (outcome.name == result.status) {
        return DmKickResult(outcome, result.reason);
      }
    }
    await LogUtil.warning('Windows 认证运行时回传了无法识别的踢设备结果');
    return const DmKickResult(DmOutcome.accepted);
  }

  ({String? status, String? reason}) _commandResult(Object? response) {
    if (response is! Map) return (status: null, reason: null);
    return (
      status: response[RuntimeContract.keyStatus] as String?,
      reason: response[RuntimeContract.keyReason] as String?,
    );
  }

  Future<void> configurationChanged() async {
    await initialize();
    _monitoringEnabled =
        await _configurationPresent() == true && wifiEvents != null;
    await _controller.execute(
      AuthRuntimeController.commandConfigurationChanged,
    );
    if (await _configurationPresent() == false) _publishMissingConfig();
  }

  /// null 表示读取失败，已经发布安全的失败状态。
  Future<bool?> _configurationPresent() async {
    try {
      return await configSource.loadFacts() != null;
    } catch (_) {
      _monitoringEnabled = false;
      _emit(
        const AuthRuntimeState(
          status: AuthenticationStatus.failed,
          message: '读取认证配置失败，请检查本地配置',
        ),
      );
      return null;
    }
  }

  void _publishMissingConfig() {
    _monitoringEnabled = false;
    publishState(
      const AuthRuntimeState(
        status: AuthenticationStatus.failed,
        reason: AuthenticationReason.missingConfig,
      ),
    );
  }

  @override
  Future<void> publishReady() async {}

  @override
  Future<void> publishState(AuthRuntimeState state) async {
    // Portal 错误文本可能回显请求字段；Windows 状态只发布结构化结果。
    _emit(
      AuthRuntimeState(
        status: state.status,
        reason: state.reason,
        retryAfterSeconds: state.retryAfterSeconds,
        acid: state.acid,
        userInfo: state.userInfo,
      ),
    );
  }

  void _emit(AuthRuntimeState state) {
    _state = state;
    if (!_states.isClosed) _states.add(_state);
  }

  Future<void> dispose() async {
    await wifiEvents?.dispose();
    await _wifiEventsTail;
    await _coordinator.dispose();
    await _wifiStates.close();
    await _states.close();
  }
}
