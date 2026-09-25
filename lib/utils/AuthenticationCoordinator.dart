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
  idle,
  checking,
  authenticating,
  online,
  alreadyOnline,
  offline,
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
  });

  final AuthenticationStatus status;
  final String? message;
  final RadUserInfo? userInfo;
  final AuthParameters? parameters;

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

/// 统一编排一次检查、候选选择、登录和在线确认。
class AuthenticationCoordinator {
  AuthenticationCoordinator({
    required this.configSource,
    required this.protocol,
    required this.networkState,
  });

  static const String supportedEnc = AuthParameters.supportedEnc;

  final AuthenticationConfigSource configSource;
  final AuthenticationProtocol protocol;
  final AuthenticationNetworkState networkState;

  final StreamController<AuthenticationState> _stateController =
      StreamController<AuthenticationState>.broadcast(sync: true);
  Future<AuthenticationResult>? _inFlight;
  bool _checkAgainAfterInFlight = false;
  String? _activeServer;
  bool _disposed = false;
  AuthenticationState _state = const AuthenticationState(
    status: AuthenticationStatus.idle,
  );

  Stream<AuthenticationState> get states => _stateController.stream;

  AuthenticationState get state => _state;

  bool get isRunning => _inFlight != null;

  Future<AuthenticationResult> check({
    bool? manual,
    AuthenticationCancellationToken? cancellation,
  }) {
    final active = _inFlight;
    if (active != null) return active;

    late final Future<AuthenticationResult> operation;
    operation = _run(manual: manual, cancellation: cancellation).whenComplete(
      () {
        if (identical(_inFlight, operation)) {
          _inFlight = null;
          if (_checkAgainAfterInFlight && !_disposed) {
            _checkAgainAfterInFlight = false;
            unawaited(check());
          }
        }
      },
    );
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
    return check(cancellation: cancellation);
  }

  void invalidateNetwork() {
    networkState.invalidate();
    protocol.reset();
  }

  void requestCheck() {
    if (_disposed) return;
    if (_inFlight != null) {
      _checkAgainAfterInFlight = true;
      return;
    }
    unawaited(check());
  }

  Future<bool> logout() async {
    final active = _inFlight;
    if (active != null) await active;
    invalidateNetwork();
    final config = await configSource.load();
    if (config == null) return false;

    final server = normalizeAuthServer(config.authServer);
    final info = await protocol.getUserInfo(server);
    final ip = _ipFrom(info);
    if (ip.isEmpty) return false;

    final success = await protocol.logout(
      server: server,
      username: config.authenticatedUsername,
      ip: ip,
    );
    return success;
  }

  Future<bool> kickDevice(String targetIp) async {
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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    protocol.dispose();
    await _stateController.close();
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
        return _failed('WiFi 未连接');
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
