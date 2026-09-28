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
}
