part of 'AuthenticationCoordinator.dart';

/// 单轮认证及协议资源的边界；协调器只处理单飞、网络世代和调度。
abstract class AuthenticationAttempt {
  Future<AuthenticationResult> run(AuthenticationAttemptContext context);

  bool get canRun => true;

  void reset() {}

  void invalidateNetwork() => reset();

  void stop() {}

  Future<DmResult> logout(AuthConfig config);

  /// 踢掉 [targetIp] 这台设备，并复查它是否真的从账号在线设备表里消失。
  Future<DmKickResult> kickDevice(AuthConfig config, String targetIp);
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
    this.confirmInterval = const Duration(seconds: 1),
  }) : _protocolInstance = protocol,
       // ignore: prefer_initializing_formals
       _protocolFactory = protocolFactory;

  /// 复查目标是否下线时的最大尝试次数，含第一次立即发出的那次。
  ///
  /// 服务器回收会话和刷新在线设备表不是原子的，第一次复查很可能仍看到目标，
  /// 所以需要有界重试而不是单次判定。
  static const int confirmAttempts = 3;

  /// 两次复查之间的等待时间。
  ///
  /// 值由测试注入为 [Duration.zero] 以避免真实等待。
  final Duration confirmInterval;

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
  Future<DmResult> logout(AuthConfig config) async {
    reset();
    final server = normalizeAuthServer(config.authServer);
    final protocol = _protocol;
    final info = await protocol.getUserInfo(server);
    final ip = _ipFrom(info);
    if (ip.isEmpty) return const DmResult(accepted: false);
    return protocol.logout(
      server: server,
      username: config.authenticatedUsername,
      ip: ip,
    );
  }

  @override
  Future<DmKickResult> kickDevice(AuthConfig config, String targetIp) async {
    final target = targetIp.trim();
    if (target.isEmpty) {
      return const DmKickResult(DmOutcome.rejected, '目标地址为空');
    }
    final server = normalizeAuthServer(config.authServer);
    final protocol = _protocol;
    final result = await protocol.logout(
      server: server,
      username: config.authenticatedUsername,
      ip: target,
    );
    if (!result.accepted) {
      return DmKickResult(DmOutcome.rejected, result.reason);
    }
    return DmKickResult(await _confirmOffline(protocol, server, target));
  }

  /// 复查目标是否真的下线。
  ///
  /// 判据是账号的在线设备表里不再有目标地址，也就是 UI 那一行会不会消失——同一个
  /// 事实，不用新增协议面。设备表是账号级数据，因此按本机照常调用即可。
  ///
  /// 比对的是每条记录自己的 `ip`/`ip6` 字段，不是 map 的键：键是 `rad_online_id`，
  /// 它和 IP 的关系没有资料能确认，拿它当 IP 比会永远判定成「已踢掉」。
  ///
  /// 只在用户信息查询成功、设备表非空且每条记录都有地址，并且其中没有目标地址时
  /// 才判定踢掉。其余情况没有完整判据，此时宁可报未确认也不报已踢掉。
  Future<DmOutcome> _confirmOffline(
    AuthenticationProtocol protocol,
    String server,
    String target,
  ) async {
    for (var i = 0; i < confirmAttempts; i++) {
      if (i > 0) await Future<void>.delayed(confirmInterval);
      final RadUserInfo info;
      try {
        info = await protocol.getUserInfo(server);
      } catch (error, stackTrace) {
        // 这一次没有判据，继续重试；次数用尽后如实报未确认。
        await LogUtil.error('踢设备复查失败', error, stackTrace);
        continue;
      }
      if (!info.isOnline) continue;
      final devices = info.onlineDeviceDetail;
      if (devices == null || devices.isEmpty) continue;
      if (devices.values.any(
        (device) => device.getIp.trim().isEmpty && device.getIp6.trim().isEmpty,
      )) {
        continue;
      }
      final stillOnline = devices.values.any(
        (device) => device.getIp == target || device.getIp6 == target,
      );
      if (!stillOnline) return DmOutcome.kicked;
    }
    return DmOutcome.accepted;
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
