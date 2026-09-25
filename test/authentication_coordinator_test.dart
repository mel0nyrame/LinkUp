import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixturePassword = List.filled(8, 'p').join();
final _fixtureChallenge = List.filled(9, 'c').join();

void main() {
  test('Reality ACID 优先于根目录探测，并在在线确认后保存', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(
      AuthConfig(
        username: _fixtureUsername,
        password: _fixturePassword,
        acid: '1',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(result.candidate?.source, AcidCandidateSource.reality);
    expect(result.candidate?.networkGeneration, 'network-1');
    expect(protocol.loginParameters?.acid, '143');
    expect(protocol.rootProbeCalls, 0);
    expect(config.updates, hasLength(1));
    expect(config.updates.single.acid, '143');
  });

  test('Reality 无候选时优先使用已保存 ACID，不执行根目录探测', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(
      AuthConfig(
        username: _fixtureUsername,
        password: _fixturePassword,
        acid: '143',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.loginParameters?.acid, '143');
    expect(protocol.rootProbeCalls, 0);
  });

  test('手动模式只使用保存的 ACID', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(
      AuthConfig(
        username: _fixtureUsername,
        password: _fixturePassword,
        acid: '7',
        autoAcid: false,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.loginParameters?.acid, '7');
    expect(protocol.rootProbeCalls, 0);
    expect(protocol.lastRealityGetAcid, isFalse);
  });

  test('保存 ACID 不可用时才执行根目录探测', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      rootAcid: '11',
    );
    final config = _FakeConfigSource(
      AuthConfig(
        username: _fixtureUsername,
        password: _fixturePassword,
        acid: '',
        hasExplicitAcid: false,
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.loginParameters?.acid, '11');
    expect(protocol.rootProbeCalls, 1);
  });

  test('Portal 假成功且在线确认失败时不发布在线状态或保存 ACID', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
      ],
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.failed);
    expect(result.isOnline, isFalse);
    expect(config.updates, isEmpty);
  });

  test('登录失败时不保存本轮 ACID', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [RadUserInfo(clientIp: '10.0.0.8', error: '')],
      loginSuccess: false,
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.failed);
    expect(config.updates, isEmpty);
  });

  test('未支持的 Enc 只作为诊断值，不进入认证参数', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      detectedEnc: 'srun_bx2',
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.loginParameters?.enc, 'srun_bx1');
    expect(result.diagnosticEnc, 'srun_bx2');
  });

  test('已经在线时不执行登录且不保存 ACID', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143', isOnline: true),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.alreadyOnline);
    expect(protocol.loginParameters, isNull);
    expect(config.updates, isEmpty);
  });

  test('并发检查共享同一轮单飞认证', () async {
    final gate = Completer<void>();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      realityGate: gate,
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final first = coordinator.check();
    final second = coordinator.check();
    expect(identical(first, second), isTrue);
    expect(protocol.realityCalls, 0);

    gate.complete();
    final result = await first;
    await second;

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.realityCalls, 1);
  });

  test('网络事件在单飞期间排队一次新的检查', () async {
    final gate = Completer<void>();
    final secondLogin = Completer<void>();
    var loginCount = 0;
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      realityGate: gate,
      afterLogin: () {
        loginCount++;
        if (loginCount == 2) secondLogin.complete();
      },
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final first = coordinator.check();
    coordinator.requestCheck();
    gate.complete();
    await first;
    await secondLogin.future;

    expect(protocol.realityCalls, 2);
  });

  test('网络世代变化时旧候选不会落盘', () async {
    final network = _FakeNetworkState();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      afterLogin: network.invalidate,
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: network,
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.stale);
    expect(config.updates, isEmpty);
  });

  test('Portal 报告 already-online 时仍需确认且不保存候选', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      loginErrorType: LoginErrorType.alreadyOnline,
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.alreadyOnline);
    expect(result.candidate, isNull);
    expect(config.updates, isEmpty);
  });

  test('在线确认成功但 ACID 保存失败时仍保持在线状态', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(_config(), updateSucceeds: false);
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.online);
    expect(result.persistenceFailed, isTrue);
  });

  test('取消中的认证不会保存候选', () async {
    final cancellation = AuthenticationCancellationToken()..cancel();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check(cancellation: cancellation);

    expect(result.status, AuthenticationStatus.cancelled);
    expect(config.updates, isEmpty);
  });

  test('WiFi 未连接时不启动认证探测', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: const [],
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(connected: false),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.failed);
    expect(protocol.realityCalls, 0);
    expect(config.updates, isEmpty);
  });

  test('认证服务器变化时旧尝试不会落盘', () async {
    final config = _FakeConfigSource(_config());
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      afterLogin: () {
        config.config = _config().copyWith(authServer: '10.129.1.2');
      },
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final result = await coordinator.check();

    expect(result.status, AuthenticationStatus.stale);
    expect(config.updates, isEmpty);
  });
}

AuthConfig _config({String acid = '1', bool autoAcid = true}) {
  return AuthConfig(
    username: _fixtureUsername,
    password: _fixturePassword,
    acid: acid,
    hasExplicitAcid: acid.trim().isNotEmpty,
    autoAcid: autoAcid,
    authServer: '10.129.1.1',
    userType: '',
  );
}

class _FakeConfigSource implements AuthenticationConfigSource {
  _FakeConfigSource(this.config, {this.updateSucceeds = true});

  AuthConfig config;
  final bool updateSucceeds;
  final updates = <ConfigUpdate>[];

  @override
  Future<AuthConfig?> load() async => config;

  @override
  Future<bool> update(
    ConfigUpdate update, {
    bool Function()? canPersist,
  }) async {
    if (canPersist != null && !canPersist()) return false;
    updates.add(update);
    return updateSucceeds;
  }
}

class _FakeNetworkState implements AuthenticationNetworkState {
  _FakeNetworkState({this.connected = true});

  int value = 1;
  bool connected;

  @override
  String get generation => 'network-$value';

  @override
  Future<bool> isConnected() async => connected;

  @override
  void invalidate() {
    value++;
  }
}

class _FakeAuthenticationProtocol implements AuthenticationProtocol {
  _FakeAuthenticationProtocol({
    required this.realityResult,
    required this.userInfo,
    this.rootAcid = '1',
    this.loginSuccess = true,
    this.detectedEnc = 'srun_bx1',
    this.realityGate,
    this.afterLogin,
    this.loginErrorType,
  });

  final RealityProbeResult realityResult;
  final List<RadUserInfo> userInfo;
  final String? rootAcid;
  final bool loginSuccess;
  final String? detectedEnc;
  final Completer<void>? realityGate;
  final void Function()? afterLogin;
  final LoginErrorType? loginErrorType;
  final List<String> servers = [];
  int rootProbeCalls = 0;
  int realityCalls = 0;
  bool? lastRealityGetAcid;
  AuthParameters? loginParameters;

  int _userInfoIndex = 0;

  @override
  Future<RealityProbeResult> reality(
    String server, {
    bool getAcid = true,
  }) async {
    realityCalls++;
    lastRealityGetAcid = getAcid;
    servers.add(server);
    await realityGate?.future;
    return realityResult;
  }

  @override
  Future<RadUserInfo> getUserInfo(String server) async {
    final result = userInfo[_userInfoIndex++];
    return result;
  }

  @override
  Future<ChallengeResponse> getChallenge({
    required String server,
    required String username,
    required String ip,
  }) async {
    return ChallengeResponse.fromJson({
      'challenge': _fixtureChallenge,
      'client_ip': '10.0.0.8',
      'ecode': 0,
      'error': 'ok',
    });
  }

  @override
  Future<LoginResult> login({
    required String server,
    required AuthParameters parameters,
    required String password,
    required String challenge,
  }) async {
    loginParameters = parameters;
    afterLogin?.call();
    return LoginResult(
      success: loginSuccess,
      message: loginSuccess ? '登录成功' : '登录失败',
      errorType: loginErrorType ?? LoginErrorType.success,
    );
  }

  @override
  Future<String?> detectAcid(String server) async {
    rootProbeCalls++;
    return rootAcid;
  }

  @override
  Future<String?> detectEnc(String server) async => detectedEnc;

  @override
  Future<bool> logout({
    required String server,
    required String username,
    required String ip,
  }) async {
    return true;
  }

  @override
  void reset() {}

  @override
  void dispose() {}
}
