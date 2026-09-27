import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/authRuntimeMain.dart';
import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/RuntimeContract.g.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixturePassword = List.filled(8, 'p').join();
final _fixtureChallenge = List.filled(9, 'c').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('认证运行时宿主桥', () {
    test('服务启动后把协调器状态发布给宿主', () async {
      final host = _FakeAuthRuntimeHost();
      final controller = _onlineController(host: host);

      controller.subscribe();
      await controller.execute(AuthRuntimeController.commandStart);
      await _pump();

      expect(
        host.states.map((state) => state.status),
        containsAllInOrder(<AuthenticationStatus>[
          AuthenticationStatus.stopped,
          AuthenticationStatus.online,
        ]),
        reason: '启动前先发布当前状态，启动后发布在线状态',
      );
      expect(host.ready, isFalse, reason: '就绪通知由入口单独发布');
    });

    test('就绪通知发出时命令处理器已能接收消息', () async {
      final host = _FakeAuthRuntimeHost();
      final controller = _onlineController(host: host);
      addTearDown(resetAuthRuntimeForTest);
      ByteData? reply;
      host.onReady = () async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              MethodChannelAuthRuntimeHost.hostChannelName,
              const StandardMethodCodec().encodeMethodCall(MethodCall('probe')),
              (response) => reply = response,
            );
      };

      await startAuthRuntimeController(controller);

      expect(host.ready, isTrue);
      expect(reply, isNotNull);
      expect(const StandardMethodCodec().decodeEnvelope(reply!), isNull);
    });

    test('停止命令取消调度并释放协议资源', () async {
      final host = _FakeAuthRuntimeHost();
      final scheduler = _FakeAuthenticationScheduler();
      final protocol = _FakeProtocol();
      final controller = _controller(
        host: host,
        scheduler: scheduler,
        protocol: protocol,
      );

      await controller.execute(AuthRuntimeController.commandStart);
      expect(scheduler.lastDelay, const Duration(seconds: 30));
      expect(protocol.disposeCalls, 0);

      await controller.execute(AuthRuntimeController.commandStop);

      expect(scheduler.hasPending, isFalse);
      expect(protocol.disposeCalls, 1);
      expect(controller.coordinator.state.status, AuthenticationStatus.stopped);
    });

    test('注销和踢设备命令把结果回传给宿主', () async {
      final host = _FakeAuthRuntimeHost();
      final protocol = _FakeProtocol();
      final controller = _onlineController(host: host, protocol: protocol);
      await controller.execute(AuthRuntimeController.commandStart);

      final logout = await controller.execute(
        AuthRuntimeController.commandLogout,
      );
      final kicked = await controller.execute(
        AuthRuntimeController.commandKickDevice,
        <String, Object?>{'ip': '10.0.0.9'},
      );
      final rejected = await controller.execute(
        AuthRuntimeController.commandKickDevice,
        <String, Object?>{'ip': ''},
      );

      // 过桥的是结果包：状态按枚举名字走，序号会随成员增删改绑。
      expect(logout, <String, Object?>{'status': 'accepted'});
      // 这个替身没有在线设备表，复查拿不到判据，因此未确认。
      expect(kicked, <String, Object?>{'status': 'accepted'});
      expect(protocol.kickedIps, <String>['10.0.0.8', '10.0.0.9']);
      expect(rejected, <String, Object?>{
        'status': 'rejected',
        'reason': '目标地址为空',
      });
    });

    test('配置变化命令在删除配置后保持停止', () async {
      final host = _FakeAuthRuntimeHost();
      final scheduler = _FakeAuthenticationScheduler();
      final protocol = _FakeProtocol();
      final config = _FakeConfigSource();
      final controller = _controller(
        host: host,
        scheduler: scheduler,
        protocol: protocol,
        configSource: config,
      );

      await controller.execute(AuthRuntimeController.commandStart);
      config.config = null;
      await controller.execute(
        AuthRuntimeController.commandConfigurationChanged,
      );

      expect(scheduler.hasPending, isFalse);
      expect(protocol.disposeCalls, 1);
      expect(controller.coordinator.state.status, AuthenticationStatus.stopped);
    });

    test('停止后待执行的任务不会重新发起认证', () async {
      final host = _FakeAuthRuntimeHost();
      final scheduler = _FakeAuthenticationScheduler();
      final protocol = _FakeProtocol();
      final controller = _controller(
        host: host,
        scheduler: scheduler,
        protocol: protocol,
      );

      controller.subscribe();
      await controller.execute(AuthRuntimeController.commandStart);
      final pending = scheduler.takePending();
      await controller.execute(AuthRuntimeController.commandStop);
      final publishedAfterStop = host.states.length;

      await pending!();

      expect(protocol.realityCalls, 1, reason: '停止前的那次调度不得再发起探测');
      expect(scheduler.hasPending, isFalse);
      expect(host.states, hasLength(publishedAfterStop));
      expect(controller.coordinator.state.status, AuthenticationStatus.stopped);
    });
  });

  group('常驻通知内容', () {
    test('可操作错误原因在跨语言快照中保持类型', () {
      const state = AuthRuntimeState(
        status: AuthenticationStatus.failed,
        reason: AuthenticationReason.invalidCredentials,
        message: '登录失败',
      );
      final restored = AuthRuntimeState.fromMap(state.toMap());

      expect(restored.reason, AuthenticationReason.invalidCredentials);
      expect(restored.presentation.title, '账号验证失败');
      expect(restored.presentation.needsAction, isTrue);
      expect(notificationContentFor(restored).text, '请在设置中检查账号和密码');
    });

    test('欠费、停用和设备数限制提供对应处理指引', () {
      for (final (reason, hint) in [
        (AuthenticationReason.paymentRequired, '请充值或购买流量包后重试'),
        (AuthenticationReason.accountUnavailable, '请联系校园网络中心'),
        (AuthenticationReason.deviceLimit, '请先下线其他设备后重试'),
      ]) {
        final restored = AuthRuntimeState.fromMap(
          AuthRuntimeState(
            status: AuthenticationStatus.failed,
            reason: reason,
          ).toMap(),
        );
        expect(restored.reason, reason);
        expect(restored.presentation.actionHint, hint);
        expect(notificationContentFor(restored).text, hint);
      }
    });

    test('跨语言在线布尔值不覆盖状态枚举的判定', () {
      final snapshot = AuthRuntimeState.fromMap({
        RuntimeContract.keyStatus: AuthenticationStatus.offline.name,
        RuntimeContract.keyIsOnline: true,
      });
      expect(snapshot.isOnline, isFalse);
      expect(snapshot.toMap()[RuntimeContract.keyIsOnline], isFalse);
    });

    test('协调器状态变化映射为持续可见的认证状态文案', () {
      expect(
        notificationContentFor(
          const AuthRuntimeState(status: AuthenticationStatus.online),
        ).text,
        '已连接到校园网',
      );
      expect(
        notificationContentFor(
          const AuthRuntimeState(status: AuthenticationStatus.alreadyOnline),
        ).text,
        '已连接到校园网',
      );
      expect(
        notificationContentFor(
          const AuthRuntimeState(status: AuthenticationStatus.checking),
        ).text,
        '正在检查网络状态…',
      );
      expect(
        notificationContentFor(
          const AuthRuntimeState(status: AuthenticationStatus.authenticating),
        ).text,
        '正在认证校园网…',
      );
      expect(
        notificationContentFor(
          const AuthRuntimeState(
            status: AuthenticationStatus.offline,
            message: 'WiFi 未连接',
          ),
        ).text,
        'WiFi 未连接',
      );
      expect(
        notificationContentFor(
          const AuthRuntimeState(
            status: AuthenticationStatus.backingOff,
            retryAfterSeconds: 6,
          ),
        ).text,
        '认证未完成，6 秒后重试',
      );
      expect(
        notificationContentFor(const AuthRuntimeState.stopped()).text,
        '后台认证已停止',
      );
    });

    test('通知不包含账号、认证参数、用户信息或协议材料', () {
      final state = AuthRuntimeState.fromCoordinatorState(
        AuthenticationState(
          status: AuthenticationStatus.online,
          message: '登录成功',
          parameters: AuthParameters(
            server: '10.129.1.1',
            username: _fixtureUsername,
            ip: '10.0.0.8',
            acid: '143',
          ),
          userInfo: RadUserInfo(
            clientIp: '10.0.0.8',
            userName: _fixtureUsername,
            realName: '测试用户',
            sumBytes: 1024,
          ),
        ),
      );

      final content = notificationContentFor(state);
      final published = state.toMap().toString();

      for (final secret in <String>[
        _fixtureUsername,
        '10.0.0.8',
        '143',
        '10.129.1.1',
        '测试用户',
        'srun_bx1',
      ]) {
        expect(
          content.text,
          isNot(contains(secret)),
          reason: '通知文本泄漏了 $secret',
        );
        expect(
          content.title,
          isNot(contains(secret)),
          reason: '通知标题泄漏了 $secret',
        );
      }
      expect(content.text, isNot(contains(_fixturePassword)));
      expect(content.text, isNot(contains(_fixtureChallenge)));
      expect(published, isNot(contains(_fixturePassword)));
      expect(published, isNot(contains(_fixtureChallenge)));
    });
  });

  group('UI 命令路由', () {
    late MethodChannel uiChannel;
    late _FakeUiHost host;
    late List<MethodCall> calls;

    setUp(() {
      uiChannel = const MethodChannel(AuthRuntimeClient.uiChannelName);
      calls = <MethodCall>[];
      host = _FakeUiHost();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(uiChannel, (call) async {
            calls.add(call);
            return host.handle(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(uiChannel, null);
    });

    test('attach 取回最近一次发布的状态', () async {
      host.latest = const AuthRuntimeState(
        status: AuthenticationStatus.online,
        acid: '143',
      ).toMap();
      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      final states = <AuthRuntimeState>[];
      client.states.listen(states.add);

      await client.attach();
      await _pump();

      expect(states.single.status, AuthenticationStatus.online);
      expect(states.single.isOnline, isTrue);
      expect(states.single.acid, '143');
      expect(host.clients, hasLength(1));
    });

    test('手动检查、注销和踢设备命令原样路由到宿主', () async {
      host.commandResults
        ..[AuthRuntimeController.commandManualCheck] = true
        ..[AuthRuntimeController.commandKickDevice] = <String, Object?>{
          RuntimeContract.keyStatus: DmOutcome.kicked.name,
          RuntimeContract.keyReason: null,
        }
        ..[AuthRuntimeController.commandConfigurationChanged] = true;
      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      await client.attach();

      // start/manualCheck/configurationChanged 不回传结果，只有注销与踢设备带回值。
      await client.manualCheck();
      final loggedOut = await client.logout();
      final kicked = await client.kickDevice('10.0.0.9');
      await client.configurationChanged();

      expect(loggedOut.accepted, isFalse);
      expect(kicked.outcome, DmOutcome.kicked);
      expect(
        calls
            .where(
              (call) =>
                  call.method == 'command' || call.method == 'fireCommand',
            )
            .map((call) => call.arguments),
        <Object?>[
          <String, Object?>{
            'name': AuthRuntimeController.commandManualCheck,
            'args': null,
          },
          <String, Object?>{
            'name': AuthRuntimeController.commandLogout,
            'args': null,
          },
          <String, Object?>{
            'name': AuthRuntimeController.commandKickDevice,
            'args': <String, Object?>{'ip': '10.0.0.9'},
          },
          <String, Object?>{
            'name': AuthRuntimeController.commandConfigurationChanged,
            'args': null,
          },
        ],
      );
      expect(calls.where((call) => call.method == 'fireCommand'), hasLength(2));
    });

    test('踢设备回传无法识别的结果时降级为未确认而不是失败', () async {
      // 契约漂移的表现是收到一个不认识的值。此时既不能声称踢掉了，也不能断言
      // 服务器拒绝了请求，只能报未确认。
      host.commandResults[AuthRuntimeController.commandKickDevice] =
          'retired_outcome';
      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      await client.attach();

      final outcome = await client.kickDevice('10.0.0.9');

      expect(outcome.outcome, DmOutcome.accepted);
    });

    test('运行时通道失败与业务失败分别返回', () async {
      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      await client.attach();

      expect((await client.logout()).accepted, isFalse);
      host.commandError = PlatformException(code: 'runtime_gone');
      await expectLater(
        client.logout(),
        throwsA(isA<AuthRuntimeUnavailableException>()),
      );
      await expectLater(
        client.kickDevice('10.0.0.9'),
        throwsA(isA<AuthRuntimeUnavailableException>()),
      );
    });

    test('宿主推送的状态进入 UI 状态流', () async {
      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      final states = <AuthRuntimeState>[];
      client.states.listen(states.add);
      await client.attach();

      await _pushState(
        uiChannel,
        const AuthRuntimeState(
          status: AuthenticationStatus.authenticating,
          message: '正在登录...',
        ).toMap(),
      );

      expect(states.single.status, AuthenticationStatus.authenticating);
      expect(states.single.message, '正在登录...');
    });
  });

  group('Activity 生命周期与后台运行时', () {
    test('Activity 销毁后运行时继续监控，重新绑定恢复最新状态', () async {
      final runtimeHost = _FakeAuthRuntimeHost();
      final scheduler = _FakeAuthenticationScheduler();
      final protocol = _FakeProtocol();
      final controller = _controller(
        host: runtimeHost,
        scheduler: scheduler,
        protocol: protocol,
      );
      controller.subscribe();
      await _pump();

      final uiChannel = const MethodChannel(AuthRuntimeClient.uiChannelName);
      final bridge = _FakePlatformBridge(controller, runtimeHost);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(uiChannel, bridge.handle);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(uiChannel, null);
      });

      final visible = AuthRuntimeClient(channel: uiChannel);
      addTearDown(visible.dispose);
      final visibleStates = <AuthRuntimeState>[];
      visible.states.listen(visibleStates.add);
      await visible.attach();
      await _pump();
      expect(visibleStates.single.status, AuthenticationStatus.stopped);

      await controller.execute(AuthRuntimeController.commandStart);
      await _pump();
      expect(visibleStates.last.status, AuthenticationStatus.online);

      // Activity 销毁：取消订阅后运行时继续调度和认证。
      await visible.detach();
      expect(bridge.clients, isEmpty);
      final disposeCallsAfterDetach = protocol.disposeCalls;

      await scheduler.fireLast();
      expect(protocol.realityCalls, 2);
      expect(protocol.disposeCalls, disposeCallsAfterDetach);
      expect(scheduler.hasPending, isTrue);

      // UI 重建：重新绑定立即拿到最新状态。
      final restored = AuthRuntimeClient(channel: uiChannel);
      addTearDown(restored.dispose);
      final restoredStates = <AuthRuntimeState>[];
      restored.states.listen(restoredStates.add);
      await restored.attach();
      await _pump();

      expect(restoredStates.single.isOnline, isTrue);
      expect(restoredStates.single.status, isNot(AuthenticationStatus.stopped));
    });

    test('关闭保留后台运行后停止调度并释放运行时资源', () async {
      final runtimeHost = _FakeAuthRuntimeHost();
      final scheduler = _FakeAuthenticationScheduler();
      final protocol = _FakeProtocol();
      final controller = _controller(
        host: runtimeHost,
        scheduler: scheduler,
        protocol: protocol,
      );
      controller.subscribe();
      await _pump();

      final uiChannel = const MethodChannel(AuthRuntimeClient.uiChannelName);
      final bridge = _FakePlatformBridge(controller, runtimeHost);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(uiChannel, bridge.handle);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(uiChannel, null);
      });

      final client = AuthRuntimeClient(channel: uiChannel);
      addTearDown(client.dispose);
      await client.attach();
      await controller.execute(AuthRuntimeController.commandStart);
      await _pump();

      expect(scheduler.hasPending, isTrue);

      // 关闭“保留后台运行”：UI 侧命令必须真正停掉调度并释放协议资源。
      final stopped = await bridge.handleStop();

      expect(stopped, isNull);
      expect(scheduler.hasPending, isFalse);
      expect(protocol.disposeCalls, 1);
      expect(runtimeHost.states.last.status, AuthenticationStatus.stopped);
    });
  });
}

Future<void> _pump() => pumpEventQueue();

Future<void> _pushState(
  MethodChannel channel,
  Map<String, Object?> payload,
) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onState', payload),
        ),
        (ByteData? _) {},
      );
}

AuthRuntimeController _onlineController({
  required _FakeAuthRuntimeHost host,
  _FakeProtocol? protocol,
}) {
  return _controller(
    host: host,
    scheduler: _FakeAuthenticationScheduler(),
    protocol: protocol ?? _FakeProtocol(),
  );
}

AuthRuntimeController _controller({
  required _FakeAuthRuntimeHost host,
  required _FakeAuthenticationScheduler scheduler,
  required _FakeProtocol protocol,
  _FakeConfigSource? configSource,
}) {
  return AuthRuntimeController(
    coordinator: AuthenticationCoordinator(
      configSource: configSource ?? _FakeConfigSource(),
      protocol: protocol,
      protocolFactory: () => protocol,
      networkState: _FakeNetworkState(),
      scheduler: scheduler,
    ),
    host: host,
  );
}

class _FakeAuthRuntimeHost implements AuthRuntimeHost {
  final List<AuthRuntimeState> states = <AuthRuntimeState>[];
  bool ready = false;
  Future<void> Function()? onReady;

  /// 模拟 Kotlin 侧 `AuthRuntimeBridge` 的状态转发：已注册客户端时推送到 UI 通道。
  void Function(AuthRuntimeState state)? onState;

  @override
  Future<void> publishReady() async {
    ready = true;
    await onReady?.call();
  }

  @override
  Future<void> publishState(AuthRuntimeState state) async {
    states.add(state);
    onState?.call(state);
  }
}

/// 模拟 Kotlin 侧 `MainActivity` 的 UI 通道，只记录命令并回放配置好的结果。
class _FakeUiHost {
  Map<String, Object?>? latest;
  final List<String> clients = <String>[];
  final Map<String, Object?> commandResults = <String, Object?>{};
  Object? commandError;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'attach':
        clients.add('ui');
        return latest;
      case 'detach':
        clients.remove('ui');
        return null;
      case 'command':
      case 'fireCommand':
        if (call.method == 'command' && commandError != null) {
          throw commandError!;
        }
        final args = call.arguments;
        if (args is! Map) return null;
        final name = args['name'];
        if (name is! String) return null;
        return commandResults[name];
      default:
        return null;
    }
  }
}

/// 模拟 Kotlin 侧 `AuthRuntimeBridge` 与 `MainActivity` 的 UI 通道语义。
class _FakePlatformBridge {
  _FakePlatformBridge(this.controller, this.host);

  final AuthRuntimeController controller;
  final _FakeAuthRuntimeHost host;
  final Set<String> clients = <String>{};
  static const MethodChannel _channel = MethodChannel(
    AuthRuntimeClient.uiChannelName,
  );

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'attach':
        clients.add('ui');
        host.onState = (state) =>
            unawaited(_pushState(_channel, state.toMap()));
        final latest = host.states.isEmpty ? null : host.states.last;
        return latest?.toMap();
      case 'detach':
        clients.remove('ui');
        host.onState = null;
        return null;
      case 'command':
      case 'fireCommand':
        final args = call.arguments;
        if (args is! Map) return null;
        final name = args['name'];
        if (name is! String) return null;
        final raw = args['args'];
        return controller.execute(
          name,
          raw is Map ? Map<String, Object?>.from(raw) : null,
        );
      default:
        return null;
    }
  }

  Future<Object?> handleStop() async {
    return controller.execute(AuthRuntimeController.commandStop);
  }
}

class _FakeConfigSource extends AuthenticationConfigSource {
  AuthConfig? config = AuthConfig(
    username: _fixtureUsername,
    password: _fixturePassword,
    acid: '143',
    autoAcid: true,
    authServer: '10.129.1.1',
    userType: '',
  );

  @override
  Future<AuthConfig?> load() async => config;

  @override
  Future<bool> update(
    ConfigUpdate update, {
    bool Function()? canPersist,
  }) async {
    if (canPersist != null && !canPersist()) return false;
    return true;
  }
}

class _FakeNetworkState implements AuthenticationNetworkState {
  int value = 1;

  @override
  String get generation => 'network-$value';

  @override
  Future<bool> isConnected() async => true;

  @override
  void invalidate() {
    value++;
  }
}

class _FakeAuthenticationScheduler implements AuthenticationScheduler {
  final List<Duration> delays = <Duration>[];
  ({Duration delay, FutureOr<void> Function() callback})? _pending;

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

  /// 取出当前待执行的回调但不触发它，用于验证取消后该回调不再生效。
  FutureOr<void> Function()? takePending() {
    final pending = _pending;
    return pending?.callback;
  }

  @override
  void cancel() {
    _pending = null;
  }
}

class _FakeProtocol implements AuthenticationProtocol {
  int realityCalls = 0;
  int logoutCalls = 0;
  int resetCalls = 0;
  int disposeCalls = 0;
  final List<String> loggedOutIps = <String>[];
  bool _online = false;
  int _userInfoCalls = 0;

  List<String> get kickedIps => loggedOutIps;

  @override
  Future<RealityProbeResult> reality(
    String server, {
    bool getAcid = true,
  }) async {
    realityCalls++;
    return const RealityProbeResult(acid: '143');
  }

  @override
  Future<RadUserInfo> getUserInfo(String server) async {
    _userInfoCalls++;
    if (_online || _userInfoCalls > 1) {
      return RadUserInfo(
        clientIp: '10.0.0.8',
        onlineIp: '10.0.0.8',
        error: 'ok',
      );
    }
    return RadUserInfo(clientIp: '10.0.0.8', onlineIp: '', error: '');
  }

  @override
  Future<ChallengeResponse> getChallenge({
    required String server,
    required String username,
    required String ip,
  }) async {
    return ChallengeResponse.fromJson(<String, Object?>{
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
    _online = true;
    return LoginResult(
      success: true,
      message: '登录成功',
      errorType: LoginErrorType.success,
    );
  }

  @override
  Future<String?> detectAcid(String server) async => null;

  @override
  Future<DmResult> logout({
    required String server,
    required String username,
    required String ip,
  }) async {
    logoutCalls++;
    loggedOutIps.add(ip);
    _online = false;
    _userInfoCalls = 0;
    return const DmResult(accepted: true);
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
