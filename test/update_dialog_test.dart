import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/components/UpdateDialog.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';

void main() {
  testWidgets('更新下载失败后可以重试，成功启动后关闭对话框', (tester) async {
    var attempts = 0;
    var dismissed = false;
    final updateInfo = UpdateInfo(
      version: '1.12.0',
      downloadUrl: 'https://example.com/LinkUp-Setup-1.12.0.exe',
      changelog: '修复与改进',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (dialogContext) => UpdateDialog(
                    updateInfo: updateInfo,
                    onDismiss: () {
                      dismissed = true;
                      Navigator.pop(dialogContext);
                    },
                    downloadAndInstall: (_, _) async => ++attempts > 1,
                  ),
                );
              },
              child: const Text('打开更新'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(find.text('下载失败，请检查网络后重试，或在浏览器中手动下载。'), findsOneWidget);
    expect(find.text('重试下载'), findsOneWidget);

    await tester.tap(find.text('重试下载'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(dismissed, isTrue);
    expect(find.text('发现新版本 1.12.0'), findsNothing);
  });
}
