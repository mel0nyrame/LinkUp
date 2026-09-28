import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsHome.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';

void main() {
  testWidgets('Windows 主窗口启动后显示 Release 版本与更新内容', (tester) async {
    final updateInfo = UpdateInfo(
      version: '1.12.0',
      downloadUrl: 'https://example.com/LinkUp-Setup-1.12.0.exe',
      changelog: '修复与改进',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsHome(
          initialState: const AuthRuntimeState.stopped(),
          states: const Stream<AuthRuntimeState>.empty(),
          onManualCheck: () async {},
          checkForUpdatesOnStartup: true,
          updateChecker: () async => updateInfo,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 1.12.0'), findsOneWidget);
    expect(find.text('修复与改进'), findsOneWidget);
  });
}
