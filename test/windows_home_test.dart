import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsHome.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SecretStore.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/WindowsAutoStart.dart';

const _windowsAutoStartChannel = MethodChannel(
  WindowsAutoStartClient.channelName,
);

class _MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    values.clear();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _MemoryConfigFileStore implements ConfigFileStore {
  String? content;

  @override
  Future<void> delete() async {
    content = null;
  }

  @override
  Future<bool> exists() async => content != null;

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String value) async {
    content = value;
  }
}

class _WindowTestConfigManager extends ConfigManager {
  _WindowTestConfigManager({
    required this.configFileStore,
    required this.secretStore,
    required this.onNotify,
  }) : super(
         repository: ConfigRepository(
           pathProvider: () async => 'unused-test-path',
           secretStore: secretStore,
           fileStore: configFileStore,
         ),
         writeConfiguredHint: (_) async {},
         notifyRuntime: onNotify,
       );

  final _MemoryConfigFileStore configFileStore;
  final _MemorySecretStore secretStore;
  final Future<void> Function() onNotify;

  var saveCalls = 0;
  var updateCalls = 0;
  var deleteCalls = 0;

  @override
  Future<AuthConfigFacts?> loadFacts() async {
    final content = configFileStore.content;
    if (content == null) return null;
    return AuthConfigFacts.fromJson(
      Map<String, dynamic>.from(jsonDecode(content) as Map),
    );
  }

  @override
  Future<bool> save(AuthConfig config) async {
    saveCalls++;
    if (config.username.isEmpty || config.password.isEmpty) return false;
    secretStore.values[ConfigRepository.passwordSecretKey] = config.password;
    configFileStore.content = jsonEncode(config.toJson());
    await onNotify();
    return true;
  }

  @override
  Future<bool> update(
    ConfigUpdate update, {
    bool Function()? canPersist,
  }) async {
    updateCalls++;
    final content = configFileStore.content;
    if (content == null) return false;
    final current = Map<String, dynamic>.from(jsonDecode(content) as Map);
    if (update.username != null) current['username'] = update.username!.trim();
    if (update.acid != null) current['acid'] = update.acid!.trim();
    if (update.autoAcid != null) current['auto_acid'] = update.autoAcid;
    if (update.authServer != null) {
      current['auth_server'] = update.authServer!.trim().isEmpty
          ? defaultAuthServer
          : update.authServer!.trim();
    }
    if (update.userType != null) current['user_type'] = update.userType!.trim();
    if (update.password != null) {
      secretStore.values[ConfigRepository.passwordSecretKey] = update.password!;
    }
    configFileStore.content = jsonEncode(current);
    await onNotify();
    return true;
  }

  @override
  Future<bool> delete() async {
    deleteCalls++;
    configFileStore.content = null;
    secretStore.values.clear();
    await onNotify();
    return true;
  }
}

String _testSecret() => String.fromCharCodes(
  List<int>.generate(24, (_) => 65 + Random.secure().nextInt(26)),
);

AuthRuntimeState _onlineDeviceState({
  bool includeDeviceDetail = true,
  bool includeOtherDevice = true,
  bool includeCurrentAddress = true,
}) {
  final devices = <String, Map<String, String>>{
    'current': <String, String>{'ip': '192.0.2.10', 'os_name': 'Windows'},
    if (includeOtherDevice)
      'other': <String, String>{'ip': '192.0.2.20', 'os_name': 'Android'},
  };
  return AuthRuntimeState(
    status: AuthenticationStatus.online,
    userInfo: RadUserInfo(
      error: 'ok',
      clientIp: includeCurrentAddress ? '192.0.2.10' : '',
      onlineIp: includeCurrentAddress ? '192.0.2.10' : '',
      onlineDeviceTotal: includeOtherDevice ? '2' : '1',
      onlineDeviceDetailRaw: includeDeviceDetail ? jsonEncode(devices) : null,
    ),
  );
}

void _useWindowsOperationViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<String> _showKickFeedback(
  WidgetTester tester,
  DmKickResult result,
) async {
  _useWindowsOperationViewport(tester);
  var manualChecks = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: WindowsHome(
        initialState: _onlineDeviceState(),
        states: const Stream<AuthRuntimeState>.empty(),
        onManualCheck: () async => manualChecks++,
        onKickDevice: (_) async => result,
      ),
    ),
  );
  await tester.ensureVisible(find.text('踢下线'));
  await tester.tap(find.text('踢下线'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认踢'));
  await tester.pumpAndSettle();

  final message =
      tester.widget<SnackBar>(find.byType(SnackBar)).content as Text;
  final value = message.data ?? '';
  expect(manualChecks, result.outcome == DmOutcome.kicked ? 1 : 0);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  return value;
}

Future<String> _showLogoutFeedback(WidgetTester tester, DmResult result) async {
  _useWindowsOperationViewport(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: WindowsHome(
        initialState: _onlineDeviceState(),
        states: const Stream<AuthRuntimeState>.empty(),
        onManualCheck: () async {},
        onLogout: () async => result,
      ),
    ),
  );
  await tester.ensureVisible(find.text('注销当前连接'));
  await tester.tap(find.text('注销当前连接'));
  await tester.pumpAndSettle();
  expect(find.text('确认注销'), findsNWidgets(2));
  await tester.tap(find.text('确认注销').last);
  await tester.pumpAndSettle();

  final message =
      tester.widget<SnackBar>(find.byType(SnackBar)).content as Text;
  final value = message.data ?? '';
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  return value;
}

Finder _textInput(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

void main() {
  late _MemoryConfigFileStore configFileStore;
  late _MemorySecretStore secretStore;
  late _WindowTestConfigManager configuration;
  var runtimeNotifications = 0;

  setUp(() {
    configFileStore = _MemoryConfigFileStore();
    secretStore = _MemorySecretStore();
    runtimeNotifications = 0;
    configuration = _WindowTestConfigManager(
      configFileStore: configFileStore,
      secretStore: secretStore,
      onNotify: () async => runtimeNotifications++,
    );
  });

  testWidgets('手动检查命令与协调器状态显示在 Windows 首屏', (tester) async {
    final states = StreamController<AuthRuntimeState>.broadcast();
    addTearDown(states.close);
    var checks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState.stopped(),
          states: states.stream,
          onManualCheck: () async => checks++,
        ),
      ),
    );

    await tester.tap(find.text('立即检查'));
    await tester.pump();
    expect(checks, 1);

    states.add(const AuthRuntimeState(status: AuthenticationStatus.checking));
    await tester.pump();
    expect(find.text('正在检查'), findsOneWidget);

    states.add(const AuthRuntimeState(status: AuthenticationStatus.online));
    await tester.pump();
    expect(find.text('已连接'), findsOneWidget);
  });

  testWidgets('完整窗口只展示已确认的在线数据和设备明细', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: AuthRuntimeState(
            status: AuthenticationStatus.online,
            userInfo: RadUserInfo(
              error: 'ok',
              clientIp: '192.0.2.10',
              onlineIp: '',
              allBytes: 1024 * 1024,
              sumBytes: 2 * 1024 * 1024,
              sumSeconds: 3600,
              onlineDeviceTotal: '1',
              onlineDeviceDetailRaw:
                  '{"device":{"ip":"192.0.2.10","os_name":"Windows"}}',
            ),
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('192.0.2.10'), findsNWidgets(2));
    expect(find.text('1.00 MB'), findsOneWidget);
    expect(find.text('1 小时 0 分'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('本机'), findsOneWidget);
  });

  testWidgets('无在线确认时网络指标显示明确空状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.checking,
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );

    expect(find.text('正在检查'), findsOneWidget);
    expect(find.text('在线确认后显示'), findsWidgets);
    expect(find.text('已在线'), findsNothing);
  });

  testWidgets('在线数据缺少字段时显示空状态而不是零值', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: AuthRuntimeState(
            status: AuthenticationStatus.online,
            userInfo: RadUserInfo.fromJson(const <String, dynamic>{
              'error': 'ok',
              'client_ip': '192.0.2.11',
            }),
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('192.0.2.11'), findsOneWidget);
    expect(find.text('暂无数据'), findsNWidgets(4));
    expect(find.text('认证服务器未提供此项数据'), findsNWidgets(4));
    expect(find.text('0 B'), findsNothing);
  });

  testWidgets('服务端明确返回零值时仍显示零', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: AuthRuntimeState(
            status: AuthenticationStatus.online,
            userInfo: RadUserInfo.fromJson(const <String, dynamic>{
              'error': 'ok',
              'client_ip': '192.0.2.12',
              'all_bytes': 0,
              'sum_bytes': 0,
              'sum_seconds': 0,
              'online_device_total': '0',
            }),
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );

    expect(find.text('0 B'), findsNWidgets(2));
    expect(find.text('0 分钟'), findsOneWidget);
    expect(find.text('0 台'), findsOneWidget);
    expect(find.text('认证服务器未提供此项数据'), findsNothing);
  });

  testWidgets('离线或缺少设备明细时不展示可操作设备', (tester) async {
    final states = StreamController<AuthRuntimeState>.broadcast();
    addTearDown(states.close);
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.offline,
          ),
          states: states.stream,
          onManualCheck: () async {},
          onLogout: () async => const DmResult(accepted: true),
          onKickDevice: (_) async => const DmKickResult(DmOutcome.kicked),
        ),
      ),
    );

    expect(find.text('踢下线'), findsNothing);
    expect(find.text('注销当前连接'), findsNothing);
    expect(find.text('本机'), findsNothing);

    states.add(_onlineDeviceState(includeDeviceDetail: false));
    await tester.pump();

    expect(find.text('注销当前连接'), findsOneWidget);
    expect(find.text('踢下线'), findsNothing);
    expect(find.text('认证已确认，服务端暂未提供设备明细。'), findsOneWidget);

    states.add(_onlineDeviceState(includeCurrentAddress: false));
    await tester.pump();

    expect(find.text('本机'), findsNothing);
    expect(find.text('踢下线'), findsNothing);
    expect(find.text('无法识别本机设备，已隐藏踢下线操作。'), findsOneWidget);
  });

  testWidgets('标记本机并在确认后踢设备，确认成功后刷新列表', (tester) async {
    _useWindowsOperationViewport(tester);
    final states = StreamController<AuthRuntimeState>.broadcast();
    addTearDown(states.close);
    final kickedAddresses = <String>[];
    var manualChecks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: _onlineDeviceState(),
          states: states.stream,
          onManualCheck: () async {
            manualChecks++;
            states.add(_onlineDeviceState(includeOtherDevice: false));
          },
          onKickDevice: (address) async {
            kickedAddresses.add(address);
            return const DmKickResult(DmOutcome.kicked);
          },
        ),
      ),
    );

    expect(find.text('本机'), findsOneWidget);
    expect(find.text('踢下线'), findsOneWidget);
    await tester.tap(find.text('踢下线'));
    await tester.pumpAndSettle();
    expect(find.text('确认踢设备'), findsOneWidget);
    expect(kickedAddresses, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(kickedAddresses, isEmpty);

    await tester.tap(find.text('踢下线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认踢'));
    await tester.pumpAndSettle();

    expect(kickedAddresses, <String>['192.0.2.20']);
    expect(manualChecks, 1);
    expect(find.text('已踢掉 192.0.2.20'), findsOneWidget);
    expect(find.text('192.0.2.20'), findsNothing);
    expect(find.text('本机'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('踢设备的受理和拒绝提示不声称已踢掉', (tester) async {
    expect(
      await _showKickFeedback(tester, const DmKickResult(DmOutcome.accepted)),
      '已要求 192.0.2.20 下线，但未能确认它已断开',
    );
    expect(
      await _showKickFeedback(
        tester,
        const DmKickResult(DmOutcome.rejected, 'E6504: 设备不在线'),
      ),
      '踢人失败：E6504: 设备不在线',
    );
  });

  testWidgets('注销当前连接需要确认并区分受理和拒绝', (tester) async {
    _useWindowsOperationViewport(tester);
    var logoutCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: _onlineDeviceState(),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          onLogout: () async {
            logoutCalls++;
            return const DmResult(accepted: true);
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('注销当前连接'));
    await tester.tap(find.text('注销当前连接'));
    await tester.pumpAndSettle();
    expect(find.text('确认注销'), findsNWidgets(2));
    expect(logoutCalls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(logoutCalls, 0);
    await tester.tap(find.text('注销当前连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认注销').last);
    await tester.pumpAndSettle();
    expect(logoutCalls, 1);
    expect(find.text('已要求注销'), findsOneWidget);
    expect(find.text('已成功注销'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(
      await _showLogoutFeedback(
        tester,
        const DmResult(accepted: false, errorMessage: '账号不存在'),
      ),
      '注销失败：账号不存在',
    );
  });

  testWidgets('Windows 设置保存账号和网络参数并支持修改、删除', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final username = 'user-${DateTime.now().microsecondsSinceEpoch}';
    final updatedUsername = '$username-updated';
    final password = _testSecret();
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState.stopped(),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('账号与网络').first);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    expect(find.text('账号信息'), findsOneWidget);
    await tester.enterText(_textInput('windows-username'), username);
    await tester.enterText(_textInput('windows-password'), password);
    final acidSwitch = find.descendant(
      of: find.byKey(const ValueKey('windows-auto-acid')),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(acidSwitch).value, isTrue);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('windows-password')),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isTrue,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('windows-username')))
          .controller!
          .text,
      username,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('windows-password')))
          .controller!
          .text,
      isNotEmpty,
    );
    final saveConfiguration = find.byKey(
      const ValueKey('windows-save-configuration'),
    );
    await tester.ensureVisible(saveConfiguration);
    await tester.tap(saveConfiguration);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(configuration.saveCalls, 1);
    expect(configFileStore.content, isNotNull);

    var storedConfig =
        jsonDecode(configFileStore.content!) as Map<String, dynamic>;
    expect(storedConfig.containsKey('password'), isFalse);
    expect(storedConfig['username'], username);
    expect(storedConfig['acid'], '143');
    expect(storedConfig['auto_acid'], isTrue);
    expect(storedConfig['auth_server'], defaultAuthServer);
    expect(secretStore.values[ConfigRepository.passwordSecretKey], password);
    expect(runtimeNotifications, 1);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('windows-password')))
          .controller!
          .text,
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('windows-auto-acid')));
    await tester.pumpAndSettle();
    await tester.enterText(_textInput('windows-acid'), '7');
    await tester.enterText(_textInput('windows-auth-server'), '192.0.2.20');
    await tester.enterText(_textInput('windows-username'), updatedUsername);
    await tester.ensureVisible(saveConfiguration);
    await tester.tap(saveConfiguration);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    storedConfig = jsonDecode(configFileStore.content!) as Map<String, dynamic>;
    expect(storedConfig['username'], updatedUsername);
    expect(storedConfig['acid'], '7');
    expect(storedConfig['auto_acid'], isFalse);
    expect(storedConfig['auth_server'], '192.0.2.20');
    expect(secretStore.values[ConfigRepository.passwordSecretKey], password);
    expect(configuration.updateCalls, 1);
    expect(runtimeNotifications, 2);

    final deleteConfiguration = find.byKey(
      const ValueKey('windows-delete-configuration'),
    );
    await tester.ensureVisible(deleteConfiguration);
    await tester.tap(deleteConfiguration);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除配置').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(configuration.deleteCalls, 1);
    expect(configFileStore.content, isNull);
    expect(secretStore.values, isEmpty);
    expect(runtimeNotifications, 3);
  });

  testWidgets('Windows 登录自启开关读写系统启动项', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var startupEnabled = false;
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_windowsAutoStartChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case WindowsAutoStartClient.methodGetEnabled:
          return startupEnabled;
        case WindowsAutoStartClient.methodSetEnabled:
          startupEnabled = call.arguments as bool;
          return null;
      }
      fail('Unexpected startup method: ${call.method}');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(_windowsAutoStartChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState.stopped(),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          configuration: configuration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('账号与网络').first);
    await tester.pumpAndSettle();

    final autoStartTile = find.byKey(const ValueKey('windows-auto-start'));
    await tester.ensureVisible(autoStartTile);
    expect(tester.widget<SwitchListTile>(autoStartTile).value, isFalse);
    await tester.tap(autoStartTile);
    await tester.pumpAndSettle();

    expect(startupEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(autoStartTile).value, isTrue);
    await tester.tap(autoStartTile);
    await tester.pumpAndSettle();
    expect(startupEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(autoStartTile).value, isFalse);
    expect(calls.map((call) => call.method), <String>[
      WindowsAutoStartClient.methodGetEnabled,
      WindowsAutoStartClient.methodSetEnabled,
      WindowsAutoStartClient.methodGetEnabled,
      WindowsAutoStartClient.methodSetEnabled,
      WindowsAutoStartClient.methodGetEnabled,
    ]);
  });
}
