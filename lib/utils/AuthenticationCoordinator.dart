import 'dart:async';

import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

export 'package:LinkUp/utils/AuthParameters.dart';

part 'AuthenticationAttempt.dart';

enum AcidCandidateSource { reality, saved, rootProbe }

class AcidCandidate {
  const AcidCandidate({
    required this.value,
    required this.source,
    required this.networkGeneration,
  });

  final String value;
  final AcidCandidateSource source;
  final String networkGeneration;

  bool get isUsable => value.trim().isNotEmpty;
}

class RealityProbeResult {
  const RealityProbeResult({this.acid});

  final String? acid;
}

enum AuthenticationStatus {
  stopped,
  checking,
  authenticating,
  online,
  alreadyOnline,
  offline,
  backingOff,
  failed,
  cancelled,
  stale,
}

enum AuthenticationReason {
  none,
  wifiUnavailable,
  missingConfig,
  invalidCredentials,
  accountUnavailable,
  paymentRequired,
  deviceLimit,
  invalidAcid,
  networkUnavailable,
  serverUnavailable,
  unknown,
}

AuthenticationReason _loginFailureReason(LoginErrorType errorType) {
  switch (errorType) {
    case LoginErrorType.authFailed:
      return AuthenticationReason.invalidCredentials;
    case LoginErrorType.accountUnavailable:
      return AuthenticationReason.accountUnavailable;
    case LoginErrorType.paymentRequired:
      return AuthenticationReason.paymentRequired;
    case LoginErrorType.deviceLimit:
      return AuthenticationReason.deviceLimit;
    case LoginErrorType.acIdError:
      return AuthenticationReason.invalidAcid;
    case LoginErrorType.ipNotAllowed:
    case LoginErrorType.networkError:
      return AuthenticationReason.networkUnavailable;
    case LoginErrorType.serverError:
    case LoginErrorType.challengeExpired:
    case LoginErrorType.parseError:
      return AuthenticationReason.serverUnavailable;
    case LoginErrorType.success:
    case LoginErrorType.alreadyOnline:
    case LoginErrorType.unknown:
      return AuthenticationReason.unknown;
  }
}

class AuthenticationState {
  const AuthenticationState({
    required this.status,
    this.message,
    this.userInfo,
    this.parameters,
    this.retryAfter,
    this.reason = AuthenticationReason.none,
  });

  final AuthenticationStatus status;
  final String? message;
  final RadUserInfo? userInfo;
  final AuthParameters? parameters;
  final Duration? retryAfter;
  final AuthenticationReason reason;

  bool get isOnline =>
      status == AuthenticationStatus.online ||
      status == AuthenticationStatus.alreadyOnline;
}

class AuthenticationResult {
  AuthenticationResult({
    required AuthenticationStatus status,
    String? message,
    RadUserInfo? userInfo,
    AuthParameters? parameters,
    this.candidate,
    AuthenticationReason reason = AuthenticationReason.none,
  }) : state = AuthenticationState(
         status: status,
         message: message,
         userInfo: userInfo,
         parameters: parameters,
         reason: reason,
       );

  final AuthenticationState state;
  AuthenticationStatus get status => state.status;
  String? get message => state.message;
  RadUserInfo? get userInfo => state.userInfo;
  AuthParameters? get parameters => state.parameters;
  final AcidCandidate? candidate;
  AuthenticationReason get reason => state.reason;

  bool get isOnline => state.isOnline;

  bool get isSuccess => isOnline;
}

abstract class AuthenticationConfigSource {
  Future<AuthConfig?> load();

  Future<AuthConfigFacts?> loadFacts() async {
    final config = await load();
    return config == null
        ? null
        : AuthConfigFacts(
            username: config.username,
            acid: config.acid,
            autoAcid: config.autoAcid,
            authServer: config.authServer,
            userType: config.userType,
            hasExplicitAcid: config.hasExplicitAcid,
          );
  }

  Future<bool> update(ConfigUpdate update, {bool Function()? canPersist});
}

class ConfigUtilSource implements AuthenticationConfigSource {
  @override
  Future<AuthConfig?> load() => configManager.load();

  @override
  Future<AuthConfigFacts?> loadFacts() => configManager.loadFacts();

  @override
  Future<bool> update(ConfigUpdate update, {bool Function()? canPersist}) {
    if (canPersist == null) return configManager.update(update);
    return configManager.update(update, canPersist: canPersist);
  }
}

abstract class AuthenticationNetworkState {
  String get generation;

  Future<bool> isConnected();

  void invalidate();
}

class AuthenticationNetworkTracker implements AuthenticationNetworkState {
  int _generation = 0;

  @override
  String get generation => 'network-$_generation';

  @override
  Future<bool> isConnected() => NetworkUtil.isWifiConnected();

  @override
  void invalidate() {
    _generation++;
  }
}

class AuthenticationCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 下线请求的结果。
///
/// 深澜的 `rad_user_dm` 只回答「请求是否被受理」，不回答目标会话是否已断开，
/// 因此把「确认断开」和「已受理但未确认」分成两级，避免把受理当成踢掉。
enum DmOutcome {
  /// 复查确认目标已不在线。
  kicked,

  /// 服务器受理了请求，但复查没能确认目标已断开。
  ///
  /// 目标仍留在账号在线设备表里，或者复查本身拿不到设备表，都归到这里。
  accepted,

  /// 服务器拒绝了请求，或请求根本没发出（目标地址非法）。
  rejected,
}

/// 一次踢设备的判定结果。
///
/// [outcome] 决定提示的颜色，[reason] 补上被拒绝时服务器给出的原因。两者一起过桥，
/// 因为只回传枚举名的话，被拒绝时用户仍然不知道为什么。
class DmKickResult {
  const DmKickResult(this.outcome, [this.reason]);

  final DmOutcome outcome;
  final String? reason;
}

/// 认证协议的可替换边界。生产实现连接 Srun 客户端，测试实现使用确定性 fake。
abstract class AuthenticationProtocol {
  Future<RealityProbeResult> reality(String server, {bool getAcid = true});

  Future<RadUserInfo> getUserInfo(String server);

  Future<ChallengeResponse> getChallenge({
    required String server,
    required String username,
    required String ip,
  });

  Future<LoginResult> login({
    required String server,
    required AuthParameters parameters,
    required String password,
    required String challenge,
  });

  Future<String?> detectAcid(String server);

  /// 下线请求的应答。协议层只回答受理与否，目标是否真断开由调用方复查。
  Future<DmResult> logout({
    required String server,
    required String username,
    required String ip,
  });

  void reset();

  void dispose() {}
}

/// 认证监控的可替换调度边界。
abstract class AuthenticationScheduler {
  void schedule(Duration delay, FutureOr<void> Function() callback);

  void cancel();
}

class TimerAuthenticationScheduler implements AuthenticationScheduler {
  Timer? _timer;

  @override
  void schedule(Duration delay, FutureOr<void> Function() callback) {
    cancel();
    _timer = Timer(delay, () {
      _timer = null;
      callback();
    });
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 统一编排认证轮次的单飞、网络世代和监控调度。
///
/// Srun 单轮实现通过 [protocolFactory] 在停止或网络变化后重建 HTTP 资源。
class AuthenticationCoordinator {
  AuthenticationCoordinator({
    required this.configSource,
    required this.networkState,
    AuthenticationProtocol? protocol,
    AuthenticationProtocol Function()? protocolFactory,
    AuthenticationScheduler? scheduler,
    AuthenticationAttempt? attempt,
  }) : assert(attempt != null || protocol != null),
       _scheduler = scheduler ?? TimerAuthenticationScheduler(),
       _attempt =
           attempt ??
           SrunAuthenticationAttempt(
             protocol: protocol!,
             protocolFactory: protocolFactory,
           );

  final AuthenticationConfigSource configSource;
  final AuthenticationNetworkState networkState;
  final AuthenticationScheduler _scheduler;
  final AuthenticationAttempt _attempt;

  bool get _canRun => _attempt.canRun;

  final StreamController<AuthenticationState> _stateController =
      StreamController<AuthenticationState>.broadcast(sync: true);
  Future<AuthenticationResult>? _inFlight;
  bool _checkAgainAfterInFlight = false;
  bool _pendingManualCheck = false;
  String? _activeServer;
  bool _monitoring = false;
  int _consecutiveFailures = 0;
  int _scheduleGeneration = 0;
  bool _stopping = false;
  bool _disposed = false;
  bool? _platformWifiConnected;
  AuthenticationState _state = const AuthenticationState(
    status: AuthenticationStatus.stopped,
  );

  Stream<AuthenticationState> get states => _stateController.stream;

  AuthenticationState get state => _state;

  bool get isRunning => _inFlight != null;

  Future<AuthenticationResult> start({
    bool manual = false,
    AuthenticationCancellationToken? cancellation,
  }) {
    if (_disposed || _stopping || !_canRun) {
      return Future.value(_stoppedResult());
    }
    _monitoring = true;
    return check(manual: manual, cancellation: cancellation);
  }

  Future<AuthenticationResult> check({
    bool? manual,
    AuthenticationCancellationToken? cancellation,
  }) {
    if (_disposed || _stopping || !_canRun) {
      return Future.value(_stoppedResult());
    }
    final active = _inFlight;
    if (active != null) {
      if (manual == true) {
        _checkAgainAfterInFlight = true;
        _pendingManualCheck = true;
      }
      return active;
    }

    AuthenticationResult? completedResult;
    late final Future<AuthenticationResult> operation;
    operation = _run(manual: manual, cancellation: cancellation)
        .then((result) {
          completedResult = result;
          return result;
        })
        .whenComplete(() {
          if (identical(_inFlight, operation)) {
            _inFlight = null;
            if (_checkAgainAfterInFlight && !_disposed) {
              _checkAgainAfterInFlight = false;
              final manual = _pendingManualCheck;
              _pendingManualCheck = false;
              unawaited(check(manual: manual ? true : null));
            } else if (completedResult != null) {
              _scheduleNext(completedResult!);
            }
          }
        });
    _inFlight = operation;
    return operation;
  }

  Future<AuthenticationResult> authenticate({
    bool? manual,
    AuthenticationCancellationToken? cancellation,
  }) {
    return check(manual: manual, cancellation: cancellation);
  }

  Future<AuthenticationResult> manualCheck({
    AuthenticationCancellationToken? cancellation,
  }) {
    if (!_monitoring) return start(manual: true, cancellation: cancellation);
    if (_inFlight != null) {
      return check(manual: true, cancellation: cancellation);
    }
    _cancelSchedule();
    return check(manual: true, cancellation: cancellation);
  }

  void invalidateNetwork() {
    networkState.invalidate();
    // Android 切换 Wi-Fi 路由后由单轮实现丢弃旧 HTTP 连接池。
    _attempt.invalidateNetwork();
  }

  /// 响应平台网络可用性变化。
  ///
  /// [connected] 由原生 `ConnectivityManager` 回调给出，只描述 Wi-Fi 是否可用。
  /// 任何一次事件都使当前网络世代失效：断开时丢弃已缓存的 ACID 与 Portal，
  /// 恢复时立刻通过同一个单飞入口检查，不等在线周期或退避周期。
  Future<AuthenticationResult> networkChanged({required bool connected}) {
    _platformWifiConnected = connected;
    invalidateNetwork();
    if (!_monitoring) {
      return connected ? start() : Future.value(_stoppedResult());
    }
    final active = _inFlight;
    if (active != null) {
      if (connected) {
        _checkAgainAfterInFlight = true;
      } else {
        _offline('WiFi 未连接');
      }
      return active;
    }
    _cancelSchedule();
    if (!connected) return Future.value(_offline('WiFi 未连接'));
    return check();
  }

  void requestCheck() {
    if (_disposed || _stopping) return;
    if (_inFlight != null) {
      _checkAgainAfterInFlight = true;
      return;
    }
    _cancelSchedule();
    unawaited(check());
  }

  Future<AuthenticationResult> configurationChanged() async {
    await stop();
    if (_disposed) return _stoppedResult();
    try {
      if (await configSource.loadFacts() == null) return _stoppedResult();
    } catch (_) {
      return _stoppedResult();
    }
    return start();
  }

  Future<DmResult> logout() async {
    if (_disposed || _stopping) {
      return const DmResult(accepted: false, errorMessage: '认证运行时未就绪');
    }
    _beginStop();

    try {
      await _quiesce();
      if (!_canRun) {
        return const DmResult(accepted: false, errorMessage: '认证运行时未就绪');
      }

      final config = await configSource.load();
      if (config == null) {
        return const DmResult(accepted: false, errorMessage: '没有可用的账号配置');
      }
      return await _attempt.logout(config);
    } finally {
      _finishStop();
    }
  }

  Future<DmKickResult> kickDevice(String targetIp) async {
    if (!_canRun) return const DmKickResult(DmOutcome.rejected, '认证运行时未就绪');
    final active = _inFlight;
    if (active != null) await active;
    final config = await configSource.load();
    if (config == null) {
      return const DmKickResult(DmOutcome.rejected, '没有可用的账号配置');
    }
    return _attempt.kickDevice(config, targetIp);
  }

  Future<void> stop() async {
    if (_disposed || _stopping) return;
    _beginStop();
    try {
      await _quiesce();
    } finally {
      _finishStop();
    }
  }

  void _beginStop() {
    _stopping = true;
    _monitoring = false;
    _platformWifiConnected = null;
    _checkAgainAfterInFlight = false;
    _pendingManualCheck = false;
    _cancelSchedule();
    networkState.invalidate();
  }

  Future<void> _quiesce() async {
    final active = _inFlight;
    if (active == null) return;
    try {
      await active;
    } catch (_) {
      // 生命周期仍需在异常后释放调度与协议资源。
    }
  }

  void _finishStop() {
    _platformWifiConnected = null;
    _attempt.stop();
    _activeServer = null;
    _emit(const AuthenticationState(status: AuthenticationStatus.stopped));
    _stopping = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _stateController.close();
  }

  void _scheduleNext(AuthenticationResult result) {
    if (!_monitoring || _disposed) return;
    if (_platformWifiConnected == false) {
      _offline('WiFi 未连接');
      return;
    }
    if (result.status == AuthenticationStatus.offline) {
      // 没有可用网络时重试不会改变结果，改为等平台网络事件唤醒。
      return;
    }
    final Duration delay;
    if (result.isOnline) {
      _consecutiveFailures = 0;
      delay = const Duration(seconds: 30);
    } else {
      final failureIndex = _consecutiveFailures;
      _consecutiveFailures++;
      final seconds = failureIndex >= 5 ? 60 : 3 * (1 << failureIndex);
      delay = Duration(seconds: seconds);
      _emit(
        AuthenticationState(
          status: AuthenticationStatus.backingOff,
          message: result.message,
          retryAfter: delay,
          reason: result.reason,
        ),
      );
    }
    _cancelSchedule();
    final generation = _scheduleGeneration;
    _scheduler.schedule(delay, () async {
      if (generation != _scheduleGeneration || !_monitoring || _disposed) {
        return;
      }
      await check();
    });
  }

  void _cancelSchedule() {
    _scheduleGeneration++;
    _scheduler.cancel();
  }

  Future<AuthenticationResult> _run({
    required bool? manual,
    required AuthenticationCancellationToken? cancellation,
  }) async {
    _emit(const AuthenticationState(status: AuthenticationStatus.checking));
    try {
      final config = await configSource.load();
      if (config == null ||
          config.username.isEmpty ||
          config.password.isEmpty) {
        return _failed('未找到有效认证配置', reason: AuthenticationReason.missingConfig);
      }

      final server = normalizeAuthServer(config.authServer);
      if (_activeServer != server) {
        _attempt.reset();
        _activeServer = server;
      }
      final generation = networkState.generation;
      if (!(_platformWifiConnected ?? await networkState.isConnected())) {
        return _offline('WiFi 未连接');
      }
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final result = await _attempt.run(
        AuthenticationAttemptContext(
          config: config,
          server: server,
          generation: generation,
          manual: manual,
          configSource: configSource,
          isCurrent: () => _isCurrent(server, generation),
          emit: _emit,
          cancellation: cancellation,
        ),
      );
      _emit(result.state);
      return result;
    } on ConfigStorageException {
      LogUtil.warning('认证配置不可用');
      return _failed('认证配置不可用，请重试', reason: AuthenticationReason.missingConfig);
    } catch (_, stackTrace) {
      LogUtil.error('认证流程异常', null, stackTrace);
      return _failed('认证流程异常，请重试');
    }
  }

  bool _isCurrent(String server, String generation) {
    return _activeServer == server && networkState.generation == generation;
  }

  bool _cancelled(AuthenticationCancellationToken? token) {
    return token?.isCancelled == true;
  }

  AuthenticationResult _stoppedResult() {
    return AuthenticationResult(
      status: AuthenticationStatus.stopped,
      message: '认证监控已停止',
    );
  }

  AuthenticationResult _offline(String message) {
    final result = AuthenticationResult(
      status: AuthenticationStatus.offline,
      message: message,
      reason: AuthenticationReason.wifiUnavailable,
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _failed(
    String message, {
    AuthenticationReason reason = AuthenticationReason.unknown,
  }) {
    final result = AuthenticationResult(
      status: AuthenticationStatus.failed,
      message: message,
      reason: reason,
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _cancelledResult() {
    final result = AuthenticationResult(
      status: AuthenticationStatus.cancelled,
      message: '认证已取消',
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _staleResult() {
    final result = AuthenticationResult(
      status: AuthenticationStatus.stale,
      message: '网络环境已变化，请重试',
    );
    _emit(result.state);
    return result;
  }

  void _emit(AuthenticationState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
