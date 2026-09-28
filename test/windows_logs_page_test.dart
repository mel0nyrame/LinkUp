import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsLogsPage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<String> Function() readLog,
    required Future<void> Function() clearLogs,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowsLogsPage(readLog: readLog, clearLogs: clearLogs),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空日志有明确状态且禁用复制与清空', (tester) async {
    await pumpPage(tester, readLog: () async => '', clearLogs: () async {});

    expect(find.text('日志文件为空'), findsOneWidget);
    expect(find.text('暂无日志记录'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('日志读取失败显示重试入口', (tester) async {
    await pumpPage(
      tester,
      readLog: () async => throw const FileSystemException('unavailable'),
      clearLogs: () async {},
    );

    expect(find.text('读取日志失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('复制与清空成功时分别反馈结果', (tester) async {
    const logs = '[INFO] Windows diagnostics';
    String? copiedText;
    var cleared = false;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });

    await pumpPage(
      tester,
      readLog: () async => logs,
      clearLogs: () async {
        cleared = true;
      },
    );
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    expect(copiedText, logs);
    expect(find.text('日志已复制到剪贴板'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空日志'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
    expect(find.text('日志已清空'), findsOneWidget);
    expect(find.text('日志文件为空'), findsOneWidget);
  });

  testWidgets('复制和清空失败分别显示错误反馈', (tester) async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard-unavailable');
      }
      return null;
    });

    await pumpPage(
      tester,
      readLog: () async => 'Windows diagnostics',
      clearLogs: () async => throw const FileSystemException('unavailable'),
    );
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('复制日志失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空日志'));
    await tester.pumpAndSettle();

    expect(find.text('清空日志失败，请重试'), findsOneWidget);
  });
}
