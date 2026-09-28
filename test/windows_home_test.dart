import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsHome.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';

void main() {
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

  testWidgets('托盘浮层展示实际认证状态和通用 Wi-Fi 状态', (tester) async {
    tester.view.physicalSize = const Size(380, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final states = StreamController<AuthRuntimeState>.broadcast();
    addTearDown(states.close);
    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.checking,
          ),
          states: states.stream,
          compact: true,
          wifiConnected: true,
          monitoringEnabled: true,
          onManualCheck: () async {},
        ),
      ),
    );

    expect(find.text('正在检查'), findsOneWidget);
    expect(find.text('Wi-Fi 已连接'), findsOneWidget);
    expect(find.text('正在监控'), findsOneWidget);
    expect(find.text('已在线'), findsNothing);

    states.add(const AuthRuntimeState(status: AuthenticationStatus.online));
    await tester.pump();
    expect(find.text('已连接'), findsOneWidget);
  });

  testWidgets('没有读取到 Wi-Fi 时只显示通用离线提示', (tester) async {
    tester.view.physicalSize = const Size(380, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.offline,
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          compact: true,
          onManualCheck: () async {},
        ),
      ),
    );

    expect(find.text('未连接 Wi-Fi'), findsOneWidget);
    expect(find.textContaining('SSID'), findsNothing);
  });

  testWidgets('托盘浮层在较矮的逻辑视口中可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(380, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.offline,
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          compact: true,
          onManualCheck: () async {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('立即检查'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('立即检查'), findsOneWidget);
  });

  testWidgets('未配置账号时浮层给出下一步，不提示自动重试', (tester) async {
    tester.view.physicalSize = const Size(380, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState(
            status: AuthenticationStatus.failed,
            reason: AuthenticationReason.missingConfig,
          ),
          states: const Stream<AuthRuntimeState>.empty(),
          compact: true,
          onManualCheck: () async {},
        ),
      ),
    );

    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('请在设置中填写账号和密码'), findsOneWidget);
    expect(find.text('认证未完成，将自动重试'), findsNothing);
  });
}
