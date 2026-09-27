part of 'AuthenticationCoordinator.dart';

/// 单轮认证及协议资源的边界；协调器只处理单飞、网络世代和调度。
abstract class AuthenticationAttempt {
  Future<AuthenticationResult> run(AuthenticationAttemptContext context);

  bool get canRun => true;

  void reset() {}

  void invalidateNetwork() => reset();

  void stop() {}

  Future<bool> logout(AuthConfig config);

  Future<bool> kickDevice(AuthConfig config, String targetIp);
}

class AuthenticationAttemptContext {
  const AuthenticationAttemptContext({
    required this.config,
    required this.server,
    required this.generation,
    required this.manual,
    required this.configSource,
    required this.isCurrent,
    required this.emit,
    this.cancellation,
  });

  final AuthConfig config;
  final String server;
  final String generation;
  final bool? manual;
  final AuthenticationConfigSource configSource;
  final bool Function() isCurrent;
  final void Function(AuthenticationState) emit;
  final AuthenticationCancellationToken? cancellation;

  bool get cancelled => cancellation?.isCancelled == true;
}

class SrunAuthenticationAttempt extends AuthenticationAttempt {
  SrunAuthenticationAttempt({
    required AuthenticationProtocol protocol,
    AuthenticationProtocol Function()? protocolFactory,
  }) : _protocolInstance = protocol,
       // ignore: prefer_initializing_formals
       _protocolFactory = protocolFactory;

  AuthenticationProtocol? _protocolInstance;
  final AuthenticationProtocol Function()? _protocolFactory;

  @override
  bool get canRun => _protocolInstance != null || _protocolFactory != null;

  AuthenticationProtocol get _protocol {
    final current = _protocolInstance;
    if (current != null) return current;
    final factory = _protocolFactory;
    if (factory == null) {
      throw StateError('认证协议已释放且没有可用的重建工厂');
    }
    return _protocolInstance = factory();
  }

  @override
  void reset() => _protocolInstance?.reset();

  @override
  void invalidateNetwork() {
    if (_protocolFactory != null) {
      _releaseProtocol();
    } else {
      reset();
    }
  }

  @override
  void stop() => _releaseProtocol();

  void _releaseProtocol() {
    final current = _protocolInstance;
    _protocolInstance = null;
    if (current == null) return;
    current.reset();
    current.dispose();
  }

  @override
  Future<bool> logout(AuthConfig config) async {
    reset();
    final server = normalizeAuthServer(config.authServer);
    final protocol = _protocol;
    final info = await protocol.getUserInfo(server);
    final ip = _ipFrom(info);
    if (ip.isEmpty) return false;
    return protocol.logout(
      server: server,
      username: config.authenticatedUsername,
      ip: ip,
    );
  }

  @override
  Future<bool> kickDevice(AuthConfig config, String targetIp) {
    return _protocol.logout(
      server: normalizeAuthServer(config.authServer),
      username: config.authenticatedUsername,
      ip: targetIp,
    );
  }

  @override
  Future<AuthenticationResult> run(AuthenticationAttemptContext context) async {
    try {
      _guard(context);
      final protocol = _protocol;
      final useManualAcid = context.manual ?? !context.config.autoAcid;
      final reality = await _step(
        context,
        () => protocol.reality(context.server, getAcid: !useManualAcid),
      );
      final userInfo = await _step(
        context,
        () => protocol.getUserInfo(context.server),
      );
      if (userInfo.isOnline) {
        return AuthenticationResult(
          status: AuthenticationStatus.alreadyOnline,
          message: '已在线',
          userInfo: userInfo,
        );
      }

      final ip = _ipFrom(userInfo);
      if (ip.isEmpty) {
        return AuthenticationResult(
          status: AuthenticationStatus.failed,
          message: '无法获取本机 IP',
          reason: AuthenticationReason.networkUnavailable,
        );
      }

      final candidate = await _selectCandidate(
        context,
        reality,
        protocol,
        useManualAcid,
      );
      _guard(context);
      if (candidate == null) {
        return AuthenticationResult(
          status: AuthenticationStatus.failed,
          message: '无法确定 ACID',
          reason: AuthenticationReason.invalidAcid,
        );
      }

      final parameters = AuthParameters(
        server: context.server,
        username: context.config.authenticatedUsername,
        ip: ip,
        acid: candidate.value,
        enc: AuthParameters.supportedEnc,
      );
      context.emit(
        AuthenticationState(
          status: AuthenticationStatus.authenticating,
          parameters: parameters,
        ),
      );

      final challenge = await _step(
        context,
        () => protocol.getChallenge(
          server: context.server,
          username: parameters.username,
          ip: parameters.ip,
        ),
      );
      if (!challenge.isSuccess || challenge.challenge.isEmpty) {
        return AuthenticationResult(
          status: AuthenticationStatus.failed,
          message: '获取认证令牌失败',
          reason: AuthenticationReason.serverUnavailable,
        );
      }

      final loginResult = await _step(
        context,
        () => protocol.login(
          server: context.server,
          parameters: parameters,
          password: context.config.password,
          challenge: challenge.challenge,
        ),
      );
      if (!loginResult.success) {
        return AuthenticationResult(
          status: AuthenticationStatus.failed,
          message: '登录失败: ${loginResult.message}',
          reason: _loginFailureReason(loginResult.errorType),
        );
      }

      // Portal 的 error == ok 不代表在线，必须再次查询 rad_user_info。
      final confirmed = await _step(
        context,
        () => protocol.getUserInfo(context.server),
      );
      if (!confirmed.isOnline) {
        return AuthenticationResult(
          status: AuthenticationStatus.failed,
          message: '登录后在线确认失败',
          reason: AuthenticationReason.serverUnavailable,
        );
      }
      if (!await _serverStillCurrent(context)) {
        return AuthenticationResult(
          status: AuthenticationStatus.stale,
          message: '网络环境已变化，请重试',
        );
      }
      _guard(context);

      var persistenceFailed = false;
      if (loginResult.errorType != LoginErrorType.alreadyOnline) {
        try {
          persistenceFailed = !await context.configSource.update(
            ConfigUpdate(acid: candidate.value),
            canPersist: () => !context.cancelled && context.isCurrent(),
          );
        } catch (_) {
          await LogUtil.warning('ACID 持久化失败，可重试');
          persistenceFailed = true;
        }
      }
      _guard(context);

      return AuthenticationResult(
        status: loginResult.errorType == LoginErrorType.alreadyOnline
            ? AuthenticationStatus.alreadyOnline
            : AuthenticationStatus.online,
        message: persistenceFailed ? '登录成功，但 ACID 保存失败' : '登录成功',
        userInfo: confirmed,
        parameters: parameters,
        candidate: loginResult.errorType == LoginErrorType.alreadyOnline
            ? null
            : candidate,
      );
    } on _AttemptCancelled {
      return AuthenticationResult(
        status: AuthenticationStatus.cancelled,
        message: '认证已取消',
      );
    } on _AttemptStale {
      return AuthenticationResult(
        status: AuthenticationStatus.stale,
        message: '网络环境已变化，请重试',
      );
    }
  }

  Future<T> _step<T>(
    AuthenticationAttemptContext context,
    Future<T> Function() action,
  ) async {
    _guard(context);
    final value = await action();
    _guard(context);
    return value;
  }

  void _guard(AuthenticationAttemptContext context) {
    if (context.cancelled) throw const _AttemptCancelled();
    if (!context.isCurrent()) throw const _AttemptStale();
  }

  Future<AcidCandidate?> _selectCandidate(
    AuthenticationAttemptContext context,
    RealityProbeResult reality,
    AuthenticationProtocol protocol,
    bool useManualAcid,
  ) async {
    final config = context.config;
    final generation = context.generation;
    if (useManualAcid) {
      return _candidate(config.acid, AcidCandidateSource.saved, generation);
    }
    if (reality.acid != null && reality.acid!.trim().isNotEmpty) {
      return _candidate(reality.acid!, AcidCandidateSource.reality, generation);
    }
    if (config.hasExplicitAcid && config.acid.trim().isNotEmpty) {
      return _candidate(config.acid, AcidCandidateSource.saved, generation);
    }
    final rootAcid = await _step(
      context,
      () => protocol.detectAcid(context.server),
    );
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

  Future<bool> _serverStillCurrent(AuthenticationAttemptContext context) async {
    try {
      final current = await context.configSource.loadFacts();
      return current != null &&
          normalizeAuthServer(current.authServer) == context.server;
    } catch (_) {
      return false;
    }
  }

  String _ipFrom(RadUserInfo info) {
    final clientIp = info.clientIp;
    if (clientIp != null && clientIp.isNotEmpty) return clientIp;
    return info.onlineIp ?? '';
  }
}

class _AttemptCancelled implements Exception {
  const _AttemptCancelled();
}

class _AttemptStale implements Exception {
  const _AttemptStale();
}
