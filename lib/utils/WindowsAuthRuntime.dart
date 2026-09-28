import 'dart:async';

import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/SrunAuthenticationProtocol.dart';

/// Windows 进程内唯一认证运行时。界面只读状态并发送命令。
class WindowsAuthRuntime implements AuthRuntimeHost {
  WindowsAuthRuntime({
    required AuthenticationCoordinator coordinator,
    required this.configSource,
  }) : _coordinator = coordinator {
    _controller = AuthRuntimeController(coordinator: coordinator, host: this);
  }

  static final WindowsAuthRuntime production = WindowsAuthRuntime(
    configSource: ConfigUtilSource(),
    coordinator: AuthenticationCoordinator(
      configSource: ConfigUtilSource(),
      protocol: SrunAuthenticationProtocol(),
      protocolFactory: SrunAuthenticationProtocol.new,
      networkState: AuthenticationNetworkTracker(),
    ),
  );

  final AuthenticationCoordinator _coordinator;
  final AuthenticationConfigSource configSource;
  late final AuthRuntimeController _controller;
  final StreamController<AuthRuntimeState> _states =
      StreamController<AuthRuntimeState>.broadcast(sync: true);
  AuthRuntimeState _state = const AuthRuntimeState.stopped();
  bool _initialized = false;

  Stream<AuthRuntimeState> get states => _states.stream;
  AuthRuntimeState get state => _state;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _controller.subscribe();
    if (await _configurationPresent() == false) {
      _publishMissingConfig();
    }
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

  Future<void> configurationChanged() async {
    await initialize();
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
    await _coordinator.dispose();
    await _states.close();
  }
}
