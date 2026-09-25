import 'dart:async';

import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/NetworkUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

export 'package:LinkUp/utils/AuthParameters.dart';

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
  const RealityProbeResult({this.acid, this.isOnline = false, this.error});

  final String? acid;
  final bool isOnline;
  final String? error;
}

enum AuthenticationStatus {
  stopped,
  idle,
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

class AuthenticationState {
  const AuthenticationState({
    required this.status,
    this.message,
    this.userInfo,
    this.parameters,
    this.retryAfter,
  });

  final AuthenticationStatus status;
  final String? message;
  final RadUserInfo? userInfo;
  final AuthParameters? parameters;
  final Duration? retryAfter;

  bool get isOnline =>
      status == AuthenticationStatus.online ||
      status == AuthenticationStatus.alreadyOnline;
}

class AuthenticationResult {
  const AuthenticationResult({
    required this.status,
    this.message,
    this.userInfo,
    this.parameters,
    this.candidate,
    this.diagnosticEnc,
    this.persistenceFailed = false,
  });

  final AuthenticationStatus status;
  final String? message;
  final RadUserInfo? userInfo;
  final AuthParameters? parameters;
  final AcidCandidate? candidate;
  final String? diagnosticEnc;
  final bool persistenceFailed;

  bool get isOnline =>
      status == AuthenticationStatus.online ||
      status == AuthenticationStatus.alreadyOnline;

  bool get isSuccess => isOnline;

  AuthenticationState get state => AuthenticationState(
    status: status,
    message: message,
    userInfo: userInfo,
    parameters: parameters,
  );
}

abstract class AuthenticationConfigSource {
  Future<AuthConfig?> load();

  Future<bool> update(ConfigUpdate update, {bool Function()? canPersist});
}

class ConfigUtilSource implements AuthenticationConfigSource {
  @override
  Future<AuthConfig?> load() => ConfigUtil.loadConfig();

  @override
  Future<bool> update(ConfigUpdate update, {bool Function()? canPersist}) {
    if (canPersist == null) return ConfigUtil.updateConfig(update);
    return ConfigUtil.updateConfig(update, canPersist: canPersist);
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

  Future<String?> detectEnc(String server);

  Future<bool> logout({
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

/// 统一编排一次检查、候选选择、登录和在线确认。
///
/// [protocolFactory] 用于停止或注销释放旧协议后重建新的 HTTP 资源。
class AuthenticationCoordinator {
  AuthenticationCoordinator({
    required this.configSource,
    required AuthenticationProtocol protocol,
    required this.networkState,
    AuthenticationProtocol Function()? protocolFactory,
    AuthenticationScheduler? scheduler,
  }) : _protocolInstance = protocol,
       // ignore: prefer_initializing_formals
       _protocolFactory = protocolFactory,
       _scheduler = scheduler ?? TimerAuthenticationScheduler();

  static const String supportedEnc = AuthParameters.supportedEnc;

  final AuthenticationConfigSource configSource;
  final AuthenticationNetworkState networkState;
  final AuthenticationProtocol Function()? _protocolFactory;
  final AuthenticationScheduler _scheduler;
  AuthenticationProtocol? _protocolInstance;

  bool get _canRun => _protocolInstance != null || _protocolFactory != null;

  AuthenticationProtocol get protocol {
    final current = _protocolInstance;
    if (current != null) return current;
    final factory = _protocolFactory;
    if (factory == null) {
      throw StateError('认证协议已释放且没有可用的重建工厂');
    }
    return _protocolInstance = factory();
  }

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
    _protocolInstance?.reset();
  }

  Future<AuthenticationResult> networkChanged() {
    invalidateNetwork();
    if (!_monitoring) return start();
    final active = _inFlight;
    if (active != null) {
      _checkAgainAfterInFlight = true;
      return active;
    }
    _cancelSchedule();
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

  Future<AuthenticationResult> configurationChanged({
    required bool hasConfig,
  }) async {
    await stop();
    if (!hasConfig || _disposed) return _stoppedResult();
    return start();
  }

  Future<bool> logout() async {
    if (_disposed || _stopping) return false;
    _beginStop();

    try {
      await _quiesce();
      if (!_canRun) return false;
      _protocolInstance?.reset();

      final config = await configSource.load();
      if (config == null) return false;

      final server = normalizeAuthServer(config.authServer);
      final currentProtocol = protocol;
      final info = await currentProtocol.getUserInfo(server);
      final ip = _ipFrom(info);
      if (ip.isEmpty) return false;

      return await currentProtocol.logout(
        server: server,
        username: config.authenticatedUsername,
        ip: ip,
      );
    } finally {
      _finishStop();
    }
  }

  Future<bool> kickDevice(String targetIp) async {
    if (!_canRun) return false;
    final active = _inFlight;
    if (active != null) await active;
    final config = await configSource.load();
    if (config == null) return false;
    final server = normalizeAuthServer(config.authServer);
    return protocol.logout(
      server: server,
      username: config.authenticatedUsername,
      ip: targetIp,
    );
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
    _releaseProtocol();
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

  void _releaseProtocol() {
    final current = _protocolInstance;
    _protocolInstance = null;
    if (current == null) return;
    current.reset();
    current.dispose();
  }

  void _scheduleNext(AuthenticationResult result) {
    if (!_monitoring || _disposed) return;
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
        return _failed('未找到有效认证配置');
      }

      final server = normalizeAuthServer(config.authServer);
      if (_activeServer != server) {
        protocol.reset();
        _activeServer = server;
      }
      final generation = networkState.generation;
      final useManualAcid = manual ?? !config.autoAcid;

      if (!await networkState.isConnected()) {
        return _offline('WiFi 未连接');
      }
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final reality = await protocol.reality(server, getAcid: !useManualAcid);
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final userInfo = await protocol.getUserInfo(server);
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      if (userInfo.isOnline) {
        final result = AuthenticationResult(
          status: AuthenticationStatus.alreadyOnline,
          message: '已在线',
          userInfo: userInfo,
        );
        _emit(result.state);
        return result;
      }

      final ip = _ipFrom(userInfo);
      if (ip.isEmpty) return _failed('无法获取本机 IP');

      final candidate = await _selectCandidate(
        config: config,
        reality: reality,
        useManualAcid: useManualAcid,
        server: server,
        generation: generation,
      );
      if (candidate == null) return _failed('无法确定 ACID');
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final diagnosticEnc = await protocol.detectEnc(server);
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final parameters = AuthParameters(
        server: server,
        username: config.authenticatedUsername,
        ip: ip,
        acid: candidate.value,
        enc: supportedEnc,
      );
      _emit(
        AuthenticationState(
          status: AuthenticationStatus.authenticating,
          parameters: parameters,
        ),
      );

      final challenge = await protocol.getChallenge(
        server: server,
        username: parameters.username,
        ip: parameters.ip,
      );
      if (!challenge.isSuccess || challenge.challenge.isEmpty) {
        return _failed('获取认证令牌失败');
      }
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final loginResult = await protocol.login(
        server: server,
        parameters: parameters,
        password: config.password,
        challenge: challenge.challenge,
      );
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();
      if (!loginResult.success) {
        return _failed('登录失败: ${loginResult.message}');
      }

      final confirmed = await protocol.getUserInfo(server);
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();
      if (!confirmed.isOnline) {
        return _failed('登录后在线确认失败');
      }

      if (!await _serverStillCurrent(server)) return _staleResult();

      var persistenceFailed = false;
      if (loginResult.errorType != LoginErrorType.alreadyOnline) {
        try {
          persistenceFailed = !await configSource.update(
            ConfigUpdate(acid: candidate.value),
            canPersist: () =>
                !_cancelled(cancellation) && _isCurrent(server, generation),
          );
        } catch (_) {
          await LogUtil.warning('ACID 持久化失败，可重试');
          persistenceFailed = true;
        }
      }
      if (_cancelled(cancellation)) return _cancelledResult();
      if (!_isCurrent(server, generation)) return _staleResult();

      final result = AuthenticationResult(
        status: loginResult.errorType == LoginErrorType.alreadyOnline
            ? AuthenticationStatus.alreadyOnline
            : AuthenticationStatus.online,
        message: persistenceFailed ? '登录成功，但 ACID 保存失败' : '登录成功',
        userInfo: confirmed,
        parameters: parameters,
        candidate: loginResult.errorType == LoginErrorType.alreadyOnline
            ? null
            : candidate,
        diagnosticEnc: diagnosticEnc == supportedEnc ? null : diagnosticEnc,
        persistenceFailed: persistenceFailed,
      );
      _emit(result.state);
      return result;
    } on ConfigStorageException {
      LogUtil.warning('认证配置不可用');
      return _failed('认证配置不可用，请重试');
    } catch (_, stackTrace) {
      LogUtil.error('认证流程异常', null, stackTrace);
      return _failed('认证流程异常，请重试');
    }
  }

  Future<bool> _serverStillCurrent(String server) async {
    try {
      final current = await configSource.load();
      return current != null &&
          normalizeAuthServer(current.authServer) == server;
    } catch (_) {
      return false;
    }
  }

  Future<AcidCandidate?> _selectCandidate({
    required AuthConfig config,
    required RealityProbeResult reality,
    required bool useManualAcid,
    required String server,
    required String generation,
  }) async {
    if (useManualAcid) {
      return _candidate(config.acid, AcidCandidateSource.saved, generation);
    }

    if (reality.acid != null && reality.acid!.trim().isNotEmpty) {
      return _candidate(reality.acid!, AcidCandidateSource.reality, generation);
    }

    if (config.hasExplicitAcid && config.acid.trim().isNotEmpty) {
      return _candidate(config.acid, AcidCandidateSource.saved, generation);
    }

    final rootAcid = await protocol.detectAcid(server);
    return _candidate(rootAcid, AcidCandidateSource.rootProbe, generation);
  }

  AcidCandidate? _candidate(
    String? value,
    AcidCandidateSource source,
    String generation,
  ) {
    if (value == null || value.trim().isEmpty) return null;
    return AcidCandidate(
      value: value.trim(),
      source: source,
      networkGeneration: generation,
    );
  }

  bool _isCurrent(String server, String generation) {
    return _activeServer == server && networkState.generation == generation;
  }

  bool _cancelled(AuthenticationCancellationToken? token) {
    return token?.isCancelled == true;
  }

  String _ipFrom(RadUserInfo info) {
    final clientIp = info.clientIp;
    if (clientIp != null && clientIp.isNotEmpty) return clientIp;
    return info.onlineIp ?? '';
  }

  AuthenticationResult _stoppedResult() {
    return const AuthenticationResult(
      status: AuthenticationStatus.stopped,
      message: '认证监控已停止',
    );
  }

  AuthenticationResult _offline(String message) {
    final result = AuthenticationResult(
      status: AuthenticationStatus.offline,
      message: message,
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _failed(String message) {
    final result = AuthenticationResult(
      status: AuthenticationStatus.failed,
      message: message,
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _cancelledResult() {
    const result = AuthenticationResult(
      status: AuthenticationStatus.cancelled,
      message: '认证已取消',
    );
    _emit(result.state);
    return result;
  }

  AuthenticationResult _staleResult() {
    const result = AuthenticationResult(
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
