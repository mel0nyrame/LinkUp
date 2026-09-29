import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsPopupApp.dart';
import 'package:LinkUp/page/WindowsStatusPopup.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('浮层状态只投影真实认证结果与必要的下一步', () {
    final scenarios = <(AuthRuntimeState, String, String)>[
      (
        const AuthRuntimeState(
          status: AuthenticationStatus.failed,
          reason: AuthenticationReason.missingConfig,
        ),
        '未配置',
        '请在设置中填写账号和密码',
      ),
      (
        const AuthRuntimeState(status: AuthenticationStatus.offline),
        '等待 Wi-Fi',
        '等待 Wi-Fi',
      ),
      (
        const AuthRuntimeState(status: AuthenticationStatus.checking),
        '正在检查',
        '正在检查',
      ),
      (
        const AuthRuntimeState(status: AuthenticationStatus.authenticating),
        '正在认证',
        '正在认证',
      ),
      (
        const AuthRuntimeState(status: AuthenticationStatus.online),
        '已连接',
        '已确认在线',
      ),
      (
        const AuthRuntimeState(
          status: AuthenticationStatus.failed,
          reason: AuthenticationReason.invalidCredentials,
        ),
        '账号验证失败',
        '请在设置中检查账号和密码',
      ),
      (
        const AuthRuntimeState(status: AuthenticationStatus.failed),
        '认证失败',
        '认证未完成，将自动重试',
      ),
    ];

    for (final (runtime, title, nextStep) in scenarios) {
      final state = WindowsPopupState.fromRuntime(
        runtime,
        wifiConnected: true,
        wifiName: null,
        monitoringEnabled: true,
      );
      expect(state.title, title);
      expect('${state.detail} ${state.authentication}', contains(nextStep));
      expect(state.wifi, 'Wi-Fi 已连接，名称不可用');
      if (!runtime.isOnline) {
        expect(state.authentication, isNot('已确认在线'));
      }
      expect(WindowsPopupState.fromMap(state.toMap()).title, title);
    }
  });

  test('浮层快照不转发运行时自由文本和在线设备资料', () {
    final snapshot = WindowsPopupState.fromRuntime(
      const AuthRuntimeState(
        status: AuthenticationStatus.failed,
        message: '服务端返回的详情不应进入浮层',
      ),
      wifiConnected: true,
      wifiName: null,
      monitoringEnabled: true,
    ).toMap();

    expect(snapshot.keys.toSet(), <String>{
      'title',
      'detail',
      'wifi',
      'authentication',
      'monitoring',
      'tone',
    });
    expect(snapshot.values.join(' '), isNot(contains('服务端返回的详情')));
  });

  testWidgets('独立浮层显示 A 状态区和 B 简短信息行，并能操作', (tester) async {
    tester.view.physicalSize = const Size(380, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var checks = 0;
    var details = 0;
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsStatusPopup(
          state: WindowsPopupState.fromRuntime(
            const AuthRuntimeState(
              status: AuthenticationStatus.failed,
              reason: AuthenticationReason.missingConfig,
            ),
            wifiConnected: true,
            wifiName: 'Campus Wi-Fi',
            monitoringEnabled: false,
          ),
          onManualCheck: () => checks++,
          onOpenDetails: () => details++,
          onClose: () => closes++,
        ),
      ),
    );

    expect(find.text('未配置'), findsNWidgets(2));
    expect(find.text('请在设置中填写账号和密码'), findsOneWidget);
    expect(find.text('Campus Wi-Fi'), findsOneWidget);
    expect(find.text('未监控'), findsOneWidget);
    expect(find.text('详细信息'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('立即检查'));
    await tester.tap(find.text('详细信息'));
    await tester.tap(find.byTooltip('关闭浮层'));
    expect((checks, details, closes), (1, 1, 1));
  });

  testWidgets('较矮浮层可滚动到操作区', (tester) async {
    tester.view.physicalSize = const Size(380, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsStatusPopup(
          state: WindowsPopupState.fromRuntime(
            const AuthRuntimeState(status: AuthenticationStatus.offline),
            wifiConnected: false,
            wifiName: null,
            monitoringEnabled: true,
          ),
          onManualCheck: () {},
          onOpenDetails: () {},
          onClose: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('详细信息'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('详细信息'), findsOneWidget);
  });

  testWidgets('浮层 UI isolate 收取快照并把按钮命令交还主运行时', (tester) async {
    tester.view.physicalSize = const Size(380, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel(WindowsPopupApp.channelName);
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == WindowsPopupApp.methodGetState) {
        return WindowsPopupState.fromRuntime(
          const AuthRuntimeState(status: AuthenticationStatus.checking),
          wifiConnected: true,
          wifiName: null,
          monitoringEnabled: true,
        ).toMap();
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const WindowsPopupApp());
    await tester.pumpAndSettle();
    expect(calls, contains(WindowsPopupApp.methodReady));
    expect(find.text('正在检查'), findsNWidgets(2));
    expect(find.text('Wi-Fi 已连接，名称不可用'), findsOneWidget);

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(WindowsPopupApp.methodUpdateState, <String, Object?>{
          'title': '已连接',
          'detail': '已确认连接校园网',
          'wifi': 'Campus Wi-Fi',
          'authentication': '已确认在线',
          'monitoring': '正在监控',
          'tone': 'online',
        }),
      ),
      (_) {},
    );
    await tester.pump();
    expect(find.text('已确认在线'), findsOneWidget);
    await tester.tap(find.text('立即检查'));
    await tester.tap(find.text('详细信息'));
    expect(
      calls,
      containsAllInOrder(['getState', 'manualCheck', 'openDetails']),
    );
  });
}
