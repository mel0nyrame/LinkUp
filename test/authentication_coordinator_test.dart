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

  test('慢 Reality 期间合并定时、网络和手动触发', () async {
    final gate = Completer<void>();
    final secondLogin = Completer<void>();
    final scheduler = _FakeAuthenticationScheduler();
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
      realityGateCall: 2,
      afterLogin: () {
        loginCount++;
        if (loginCount == 2) secondLogin.complete();
      },
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    final slowCheck = coordinator.check();
    await protocol.realityGateStarted.future;

    final timerTrigger = scheduler.fireLast();
    unawaited(coordinator.networkChanged(connected: true));
    unawaited(coordinator.manualCheck());
    expect(protocol.realityCalls, 2);

    gate.complete();
    await timerTrigger;
    expect((await slowCheck).status, AuthenticationStatus.stale);
    await secondLogin.future;

    expect(protocol.realityCalls, 3);
    expect(protocol.maxConcurrentRealityCalls, 1);
    expect(protocol.realityGetAcidCalls, [true, true, false]);
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

    expect(result.status, AuthenticationStatus.offline);
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

  test('稳定在线状态使用 30 秒检查周期', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    final result = await coordinator.start();

    expect(result.status, AuthenticationStatus.online);
    expect(scheduler.lastDelay, const Duration(seconds: 30));
  });

  test('连续失败从 3 秒指数退避到最多 60 秒', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: _FakeAuthenticationProtocol(
        realityResult: const RealityProbeResult(acid: '143', isOnline: true),
        userInfo: _notAuthenticatedResponses(8),
      ),
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();

    expect(coordinator.state.status, AuthenticationStatus.backingOff);
    expect(coordinator.state.retryAfter, const Duration(seconds: 3));

    for (var i = 0; i < 6; i++) {
      await scheduler.fireLast();
    }

    expect(scheduler.delays, const [
      Duration(seconds: 3),
      Duration(seconds: 6),
      Duration(seconds: 12),
      Duration(seconds: 24),
      Duration(seconds: 48),
      Duration(seconds: 60),
      Duration(seconds: 60),
    ]);
  });

  test('停止和重新启动不会清零连续失败计数', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143', isOnline: true),
      userInfo: _notAuthenticatedResponses(2),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      protocolFactory: () => protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    await coordinator.stop();
    await coordinator.start();

    expect(scheduler.delays, const [
      Duration(seconds: 3),
      Duration(seconds: 6),
    ]);
  });

  test('Wi-Fi 恢复立即请求检查并回到在线周期', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final network = _FakeNetworkState(connected: false);
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: _FakeAuthenticationProtocol(
        realityResult: const RealityProbeResult(acid: '143'),
        userInfo: [
          RadUserInfo(clientIp: '10.0.0.8', error: ''),
          RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
        ],
      ),
      networkState: network,
      scheduler: scheduler,
    );

    await coordinator.start();
    network.connected = true;
    final result = await coordinator.networkChanged(connected: true);

    expect(result.status, AuthenticationStatus.online);
    expect(network.generation, 'network-2');
    expect(scheduler.cancelCalls, greaterThan(0));
    expect(scheduler.lastDelay, const Duration(seconds: 30));
  });

  test('无网络时不安排重试，等首个网络事件再检查', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final network = _FakeNetworkState(connected: false);
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: network,
      scheduler: scheduler,
    );

    final booted = await coordinator.start();

    expect(booted.status, AuthenticationStatus.offline);
    expect(scheduler.delays, isEmpty);
    expect(scheduler.hasPending, isFalse);
    expect(protocol.realityCalls, 0);

    network.connected = true;
    final recovered = await coordinator.networkChanged(connected: true);

    expect(recovered.status, AuthenticationStatus.online);
    expect(protocol.realityCalls, 1);
    expect(scheduler.lastDelay, const Duration(seconds: 30));
  });

  test('网络断开取消退避并进入离线，不发起新的认证探测', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143', isOnline: true),
      userInfo: _notAuthenticatedResponses(2),
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    final failing = await coordinator.start();
    expect(failing.status, AuthenticationStatus.failed);
    expect(scheduler.lastDelay, const Duration(seconds: 3));
    final realityCalls = protocol.realityCalls;
    final cancelCalls = scheduler.cancelCalls;

    final result = await coordinator.networkChanged(connected: false);

    expect(result.status, AuthenticationStatus.offline);
    expect(coordinator.state.status, AuthenticationStatus.offline);
    expect(scheduler.hasPending, isFalse);
    expect(scheduler.cancelCalls, cancelCalls + 1);
    expect(protocol.realityCalls, realityCalls);
  });

  test('网络事件在退避期间立即检查，不等退避周期', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143', isOnline: true),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      realityFailuresRemaining: 1,
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    expect(scheduler.lastDelay, const Duration(seconds: 3));

    final result = await coordinator.networkChanged(connected: true);

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.realityCalls, 2);
    expect(scheduler.lastDelay, const Duration(seconds: 30));
  });

  test('重复网络事件不产生并发认证', () async {
    final gate = Completer<void>();
    final recoveredLogin = Completer<void>();
    var loginCount = 0;
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      realityGate: gate,
      afterLogin: () {
        loginCount++;
        recoveredLogin.complete();
      },
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
    );

    final first = coordinator.check();
    await protocol.realityGateStarted.future;
    // 平台可能重复下发同一事件；网络世代已变，本轮作废，但重复事件只能合并成
    // 一次补跑，不能各自发起 Reality 或登录。
    unawaited(coordinator.networkChanged(connected: true));
    unawaited(coordinator.networkChanged(connected: true));
    unawaited(coordinator.networkChanged(connected: true));

    gate.complete();
    expect((await first).status, AuthenticationStatus.stale);
    await recoveredLogin.future;

    expect(loginCount, 1);
    expect(protocol.realityCalls, 2);
    expect(protocol.maxConcurrentRealityCalls, 1);
  });

  test('网络与服务器同时变化时只有最新世代能落盘', () async {
    final config = _FakeConfigSource(_config());
    final network = _FakeNetworkState();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: _notAuthenticatedResponses(2),
      afterLogin: () {
        // 登录期间既切换网络世代又改认证服务器：旧结果必须整体作废。
        network.invalidate();
        config.config = _config().copyWith(authServer: '10.129.1.2');
      },
    );
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: protocol,
      networkState: network,
      scheduler: _FakeAuthenticationScheduler(),
    );

    await coordinator.start();
    final stale = await coordinator.networkChanged(connected: true);

    expect(config.updates, isEmpty);
    expect(stale.status, isNot(AuthenticationStatus.online));
    expect(coordinator.state.status, isNot(AuthenticationStatus.online));
  });

  test('手动刷新立即检查并使用保存的 ACID', () async {
    final network = _FakeNetworkState(connected: false);
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config(autoAcid: false)),
      protocol: protocol,
      networkState: network,
      scheduler: _FakeAuthenticationScheduler(),
    );

    await coordinator.start();
    network.connected = true;
    final result = await coordinator.manualCheck();

    expect(result.status, AuthenticationStatus.online);
    expect(protocol.lastRealityGetAcid, isFalse);
    expect(protocol.loginParameters?.acid, '1');
  });

  test('Reality 异常释放单飞锁并允许下一轮执行', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
      realityFailuresRemaining: 1,
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    final first = await coordinator.start();
    expect(first.status, AuthenticationStatus.failed);
    expect(scheduler.lastDelay, const Duration(seconds: 3));

    await scheduler.fireLast();

    expect(protocol.realityCalls, 2);
    expect(coordinator.state.status, AuthenticationStatus.online);
    expect(scheduler.lastDelay, const Duration(seconds: 30));
  });

  test('Portal 假成功不会清零退避，只有在线确认成功才恢复周期', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143', isOnline: true),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    final first = await coordinator.start();
    expect(first.status, AuthenticationStatus.failed);
    expect(scheduler.lastDelay, const Duration(seconds: 3));

    await scheduler.fireLast();

    expect(coordinator.state.status, AuthenticationStatus.online);
    expect(scheduler.delays, const [
      Duration(seconds: 3),
      Duration(seconds: 30),
    ]);
  });

  test('停止监控释放调度、Portal 缓存和协议资源', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final network = _FakeNetworkState();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: network,
      scheduler: scheduler,
    );

    expect(coordinator.state.status, AuthenticationStatus.stopped);
    await coordinator.start();
    final resetCallsBeforeStop = protocol.resetCalls;
    await coordinator.stop();

    expect(coordinator.state.status, AuthenticationStatus.stopped);
    expect(scheduler.cancelCalls, greaterThan(0));
    expect(protocol.resetCalls, resetCallsBeforeStop + 1);
    expect(protocol.disposeCalls, 1);
    expect(network.generation, 'network-2');
  });

  test('停止后重新监控使用新的协议资源', () async {
    final firstProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final secondProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: firstProtocol,
      protocolFactory: () => secondProtocol,
      networkState: _FakeNetworkState(),
      scheduler: _FakeAuthenticationScheduler(),
    );

    await coordinator.start();
    await coordinator.stop();
    final result = await coordinator.start();

    expect(result.status, AuthenticationStatus.online, reason: result.message);
    expect(firstProtocol.disposeCalls, 1);
    expect(secondProtocol.realityCalls, 1);
  });

  test('未提供协议工厂时停止后不会复用已释放实例', () async {
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: _FakeAuthenticationScheduler(),
    );

    await coordinator.start();
    await coordinator.stop();
    final result = await coordinator.start();

    expect(result.status, AuthenticationStatus.stopped);
    expect(protocol.realityCalls, 1);
    expect(protocol.disposeCalls, 1);
  });

  test('注销后停止调度并释放认证资源', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    final success = await coordinator.logout();

    expect(success, isTrue);
    expect(protocol.logoutCalls, 1);
    expect(protocol.disposeCalls, 1);
    expect(scheduler.hasPending, isFalse);
    expect(coordinator.state.status, AuthenticationStatus.stopped);
  });

  test('配置变化取消旧调度，删除配置后保持停止', () async {
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    await coordinator.configurationChanged(hasConfig: false);

    expect(coordinator.state.status, AuthenticationStatus.stopped);
    expect(scheduler.hasPending, isFalse);
    expect(protocol.disposeCalls, 1);
  });

  test('认证服务器变化后使用新协议世代立即检查', () async {
    final firstProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final secondProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final config = _FakeConfigSource(_config());
    final coordinator = AuthenticationCoordinator(
      configSource: config,
      protocol: firstProtocol,
      protocolFactory: () => secondProtocol,
      networkState: _FakeNetworkState(),
      scheduler: _FakeAuthenticationScheduler(),
    );

    await coordinator.start();
    config.config = _config().copyWith(authServer: '10.129.1.2');
    final result = await coordinator.configurationChanged(hasConfig: true);

    expect(result.status, AuthenticationStatus.online);
    expect(firstProtocol.disposeCalls, 1);
    expect(secondProtocol.servers, ['10.129.1.2']);
  });

  test('停止后的有效网络变化会恢复监控并立即检查', () async {
    final firstProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final secondProtocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: [
        RadUserInfo(clientIp: '10.0.0.8', error: ''),
        RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
      ],
    );
    final scheduler = _FakeAuthenticationScheduler();
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: firstProtocol,
      protocolFactory: () => secondProtocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    await coordinator.start();
    await coordinator.stop();
    final result = await coordinator.networkChanged(connected: true);

    expect(result.status, AuthenticationStatus.online);
    expect(scheduler.hasPending, isTrue);
    expect(secondProtocol.realityCalls, 1);
  });

  test('停止会使慢 Reality 的旧网络世代失效', () async {
    final gate = Completer<void>();
    final scheduler = _FakeAuthenticationScheduler();
    final protocol = _FakeAuthenticationProtocol(
      realityResult: const RealityProbeResult(acid: '143'),
      userInfo: const [],
      realityGate: gate,
    );
    final coordinator = AuthenticationCoordinator(
      configSource: _FakeConfigSource(_config()),
      protocol: protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    );

    final check = coordinator.start();
    await protocol.realityStarted.future;
    final stop = coordinator.stop();
    gate.complete();
    final result = await check;
    await stop;

    expect(result.status, AuthenticationStatus.stale);
    expect(protocol.userInfoCalls, 0);
    expect(protocol.disposeCalls, 1);
    expect(scheduler.hasPending, isFalse);
    expect(coordinator.state.status, AuthenticationStatus.stopped);
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

/// 一律“未认证”的 Portal 响应序列：每轮检查消耗登录前后各一条。
///
/// 用它构造“已联网但认证失败”的场景，让退避只来自失败本身而不是没有网络。
List<RadUserInfo> _notAuthenticatedResponses(int attempts) {
  return List.generate(
    attempts * 2,
    (_) => RadUserInfo(clientIp: '10.0.0.8', error: ''),
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

class _FakeAuthenticationScheduler implements AuthenticationScheduler {
  final List<Duration> delays = [];
  ({Duration delay, FutureOr<void> Function() callback})? _pending;
  int cancelCalls = 0;

  Duration? get lastDelay => delays.isEmpty ? null : delays.last;

  bool get hasPending => _pending != null;

  @override
  void schedule(Duration delay, FutureOr<void> Function() callback) {
    delays.add(delay);
    _pending = (delay: delay, callback: callback);
  }

  Future<void> fireLast() async {
    final pending = _pending!;
    _pending = null;
    await Future<void>.sync(pending.callback);
  }

  @override
  void cancel() {
    _pending = null;
    cancelCalls++;
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
    this.realityGateCall = 1,
    this.realityFailuresRemaining = 0,
    this.afterLogin,
    this.loginErrorType,
  });

  final RealityProbeResult realityResult;
  final List<RadUserInfo> userInfo;
  final String? rootAcid;
  final bool loginSuccess;
  final String? detectedEnc;
  final Completer<void>? realityGate;
  final int realityGateCall;
  final Completer<void> realityGateStarted = Completer<void>();
  int realityFailuresRemaining;
  final void Function()? afterLogin;
  final LoginErrorType? loginErrorType;
  final List<String> servers = [];
  final List<bool> realityGetAcidCalls = [];
  final Completer<void> realityStarted = Completer<void>();
  int rootProbeCalls = 0;
  int realityCalls = 0;
  int maxConcurrentRealityCalls = 0;
  int userInfoCalls = 0;
  int logoutCalls = 0;
  int resetCalls = 0;
  int disposeCalls = 0;
  bool? lastRealityGetAcid;
  AuthParameters? loginParameters;

  int _userInfoIndex = 0;
  int _activeRealityCalls = 0;

  @override
  Future<RealityProbeResult> reality(
    String server, {
    bool getAcid = true,
  }) async {
    realityCalls++;
    if (realityCalls == 1) realityStarted.complete();
    lastRealityGetAcid = getAcid;
    realityGetAcidCalls.add(getAcid);
    servers.add(server);
    _activeRealityCalls++;
    if (_activeRealityCalls > maxConcurrentRealityCalls) {
      maxConcurrentRealityCalls = _activeRealityCalls;
    }
    try {
      if (realityFailuresRemaining > 0) {
        realityFailuresRemaining--;
        throw StateError('fixture failure');
      }
      if (realityCalls == realityGateCall && realityGate != null) {
        if (!realityGateStarted.isCompleted) realityGateStarted.complete();
        await realityGate!.future;
      }
      return realityResult;
    } finally {
      _activeRealityCalls--;
    }
  }

  @override
  Future<RadUserInfo> getUserInfo(String server) async {
    userInfoCalls++;
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
    logoutCalls++;
    return true;
  }

  @override
  void reset() {
    resetCalls++;
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}
