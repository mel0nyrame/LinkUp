import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:LinkUp/components/FirstSetupDialog.dart';
import 'package:LinkUp/page/AuthWrapperPage.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('“配置存在”提示是三态，键缺失时没有可信事实', () async {
    await _loadPreferences();
    expect(
      SystemSettingsUtil.getAccountConfiguredHint(),
      isNull,
      reason: '偏好里没有这个键时不许猜成 false，否则首次配置会被跳过',
    );

    await _loadPreferences(accountConfigured: true);
    expect(SystemSettingsUtil.getAccountConfiguredHint(), isTrue);

    await _loadPreferences(accountConfigured: false);
    expect(SystemSettingsUtil.getAccountConfiguredHint(), isFalse);
  });

  testWidgets('提示为已配置时首帧就是概况内容，不出现加载圈', (tester) async {
    await _loadPreferences(accountConfigured: true);
    final check = _ControllableCheck();

    await tester.pumpWidget(_subject(check.call));

    expect(find.text('概况内容'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '加载圈不算首次实际内容',
    );

    check.complete(true);
    await tester.pump();

    expect(find.byType(FirstSetupDialog), findsNothing);
  });

  testWidgets('提示缺失时维持加载圈，真实检查确认后呈现概况内容', (tester) async {
    await _loadPreferences();
    final check = _ControllableCheck();

    await tester.pumpWidget(_subject(check.call));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('概况内容'), findsNothing);

    check.complete(true);
    await tester.pump();

    expect(find.text('概况内容'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FirstSetupDialog), findsNothing);
  });

  testWidgets('提示过期时纠正回首次配置并弹出配置对话框', (tester) async {
    await _loadPreferences(accountConfigured: true);
    final check = _ControllableCheck();

    await tester.pumpWidget(_subject(check.call));

    expect(find.text('概况内容'), findsOneWidget);

    // 配置文件已经被删掉，提示不再作数。
    check.complete(false);
    await tester.pump();
    await tester.pump();

    expect(
      find.text('首次启动配置中...'),
      findsOneWidget,
      reason: '真实检查说没有配置，停在概况页就是假装已配置',
    );
    expect(find.text('概况内容'), findsNothing);
    expect(find.byType(FirstSetupDialog), findsOneWidget);
  });

  testWidgets('提示为未配置时首帧呈现首次配置内容并弹出对话框', (tester) async {
    await _loadPreferences(accountConfigured: false);
    final check = _ControllableCheck();

    await tester.pumpWidget(_subject(check.call));

    expect(find.text('首次启动配置中...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    check.complete(false);
    await tester.pump();
    await tester.pump();

    expect(find.byType(FirstSetupDialog), findsOneWidget);
  });
}

Widget _subject(Future<bool> Function() check) => MaterialApp(
  home: AuthWrapperPage(configExists: check, child: const Text('概况内容')),
);

/// 让用例自己决定权威检查什么时候回来、回来什么结果。
///
/// 首屏判定要同时覆盖“提示”和“真实检查”两个来源，只有把检查卡在手里，
/// 才能分别断言首帧呈现的内容和纠正之后呈现的内容。
class _ControllableCheck {
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> call() => _completer.future;

  void complete(bool exists) => _completer.complete(exists);
}

/// 用给定的“配置存在”提示重建偏好并让 [SystemSettingsUtil] 重新加载。
///
/// `SystemSettingsUtil` 缓存了 `SharedPreferences` 实例，而
/// `setMockInitialValues` 只换掉底层存储；不重新 `init()` 的话，同步 getter 会
/// 继续读到上一个用例残留的实例。
Future<void> _loadPreferences({bool? accountConfigured}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'account_configured': ?accountConfigured,
  });
  await SystemSettingsUtil.init();
}
