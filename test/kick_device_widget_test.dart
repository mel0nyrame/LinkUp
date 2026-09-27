import 'dart:async';
import 'dart:convert';

import 'package:LinkUp/main.dart';
import 'package:LinkUp/navigation/MainNavigation.dart';
import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SystemSettingsUtil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_liquid_glass/lightweight_liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 被踢的设备。本机是 10.0.0.9，所以列表里 10.0.0.8 那一行才会显示「踢」。
const _targetIp = '10.0.0.8';

RadUserInfo _userInfo() => RadUserInfo.fromJson({
  'error': 'ok',
  'user_name': List.filled(8, 'u').join(),
  'client_ip': '10.0.0.9',
  'online_ip': '10.0.0.9',
  'online_device_total': '2',
  'online_device_detail': jsonEncode({
    '101': {
      'class_name': 'PC',
      'ip': '10.0.0.9',
      'os_name': 'macOS',
      'rad_online_id': '101',
    },
    '102': {
      'class_name': 'Phone',
      'ip': _targetIp,
      'os_name': 'Android',
      'rad_online_id': '102',
    },
  }),
});

class _FakeAuthRuntimeClient extends AuthRuntimeClient {
  _FakeAuthRuntimeClient(this._kickResult);

  final DmKickResult _kickResult;
  final _states = StreamController<AuthRuntimeState>.broadcast();

  int manualCheckCalls = 0;
  final kickedIps = <String>[];

  @override
  Stream<AuthRuntimeState> get states => _states.stream;

  void emit(AuthRuntimeState state) => _states.add(state);

  @override
  Future<void> attach() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => _states.close();

  @override
  Future<void> manualCheck() async {
    manualCheckCalls++;
  }

  @override
  Future<DmKickResult> kickDevice(String ip) async {
    kickedIps.add(ip);
    return _kickResult;
  }
}

/// 真实 MainNavigator 里有两处 GlassSurface（Hero 状态卡和底部导航），它们的实时
/// 模糊每帧都排新帧，所以这里只能用定长 pump，不能用 pumpAndSettle。
Future<void> _pumpFrames(WidgetTester tester, [int frames = 3]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// 把画布拉高到能同时放下概况页、设置页和底部浮动导航，让「踢」按钮落在导航条
/// 之上；默认 800x600 时它被底部玻璃导航盖住，点不中。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 收尾冲掉「页面加载后延迟 2 秒查更新」的定时器。测试体结束前必须调它：残留
/// Timer 会让框架断言失败，而且这个检查跑在 tearDown 之前。
Future<void> _flushMainNavigator(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

/// 踢被踢的那一行，读下用户看到的提示文案和颜色。
Future<({String message, Color? color})> _kickAndReadSnackBar(
  WidgetTester tester,
  _FakeAuthRuntimeClient client, {
  required int expectedRefreshes,
}) async {
  await tester.pumpWidget(MaterialApp(home: MainNavigator(client: client)));
  client.emit(
    AuthRuntimeState(
      status: AuthenticationStatus.online,
      userInfo: _userInfo(),
      acid: 'test-acid',
    ),
  );
  await _pumpFrames(tester);

  await tester.tap(find.text('踢'));
  await _pumpFrames(tester);
  expect(find.text('确认踢设备'), findsOneWidget);

  await tester.tap(find.text('确认踢'));
  await _pumpFrames(tester);

  final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
  final message = (snackBar.content as Text).data ?? '';
  await _settleAfterKick(tester, client, expectedRefreshes);
  await _flushMainNavigator(tester);
  return (message: message, color: snackBar.backgroundColor);
}

/// 踢完到刷新之间隔着一次真实的日志写盘（`LogUtil` 走文件 I/O，只有离开 fake-async
/// 才推进），而它排在刷新之前。固定睡眠在整套测试连跑时会偶发不够——机器一忙，写盘
/// 还没落地就被断言看成了「没刷新」——所以改成有界轮询。
///
/// [expectedRefreshes] 大于 0 时转到刷新真的发生为止；等于 0 时不等待，但仍跑满
/// [quietRounds] 轮，好让「本不该刷新却晚到」的刷新也暴露出来。
Future<void> _settleAfterKick(
  WidgetTester tester,
  _FakeAuthRuntimeClient client,
  int expectedRefreshes, {
  int maxRounds = 60,
  int quietRounds = 8,
}) async {
  for (var round = 0; round < maxRounds; round++) {
    if (expectedRefreshes > 0 && client.manualCheckCalls >= expectedRefreshes) {
      return;
    }
    await _tick(tester);
  }
  if (expectedRefreshes > 0) {
    fail(
      '轮询 $maxRounds 轮后仍未发生刷新：'
      'manualCheckCalls=${client.manualCheckCalls}，期望 $expectedRefreshes',
    );
  }
  for (var round = 0; round < quietRounds; round++) {
    await _tick(tester);
  }
}

Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await _pumpFrames(tester, 1);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SystemSettingsUtil.resetForTest();
  });

  testWidgets('踢成功后提示已踢掉，并重新拉一次设备列表', (tester) async {
    _useTallSurface(tester);
    final client = _FakeAuthRuntimeClient(const DmKickResult(DmOutcome.kicked));
    final result = await _kickAndReadSnackBar(
      tester,
      client,
      expectedRefreshes: 1,
    );

    expect(result.message, '已踢掉 $_targetIp');
    expect(result.color, MyApp.iosGreen);
    expect(client.kickedIps, <String>[_targetIp]);
    // 复查是靠「目标不在设备表里」判定的，那一行刚消失，本地这份还是旧的。
    expect(client.manualCheckCalls, 1);
  });

  testWidgets('服务器受理但没确认断开时如实说未能确认，且不重新拉列表', (tester) async {
    _useTallSurface(tester);
    final client = _FakeAuthRuntimeClient(
      const DmKickResult(DmOutcome.accepted),
    );
    final result = await _kickAndReadSnackBar(
      tester,
      client,
      expectedRefreshes: 0,
    );

    expect(result.message, '已要求 $_targetIp 下线，但未能确认它已断开');
    expect(result.color, MyApp.iosOrange);
    expect(client.kickedIps, <String>[_targetIp]);
    // 目标大概率还在表里，这时候刷新只会让用户看到一样的列表。
    expect(client.manualCheckCalls, 0);
  });

  testWidgets('服务器拒绝时把给出的原因带进提示', (tester) async {
    _useTallSurface(tester);
    final client = _FakeAuthRuntimeClient(
      const DmKickResult(DmOutcome.rejected, 'E6504: 该 IP 不在在线设备表中'),
    );
    final result = await _kickAndReadSnackBar(
      tester,
      client,
      expectedRefreshes: 0,
    );

    expect(result.message, '踢人失败：E6504: 该 IP 不在在线设备表中');
    expect(result.color, MyApp.iosRed);
    expect(client.manualCheckCalls, 0);
  });

  testWidgets('服务器拒绝但没给原因时退回固定文案', (tester) async {
    _useTallSurface(tester);
    final client = _FakeAuthRuntimeClient(
      const DmKickResult(DmOutcome.rejected),
    );
    final result = await _kickAndReadSnackBar(
      tester,
      client,
      expectedRefreshes: 0,
    );

    expect(result.message, '踢人失败：服务器返回错误');
    expect(result.color, MyApp.iosRed);
    expect(client.manualCheckCalls, 0);
  });

  testWidgets('设置页的 ListTile 不再触发背景被遮住的框架断言', (tester) async {
    _useTallSurface(tester);
    final client = _FakeAuthRuntimeClient(const DmKickResult(DmOutcome.kicked));
    await tester.pumpWidget(MaterialApp(home: MainNavigator(client: client)));
    client.emit(
      AuthRuntimeState(
        status: AuthenticationStatus.online,
        userInfo: _userInfo(),
        acid: 'test-acid',
      ),
    );
    await _pumpFrames(tester);

    // 切到设置页。ListTile 一旦被包在自带背景色的 DecoratedBox 里，框架就会报
    // 「背景或墨迹可能被遮住」，测试随之失败，所以这里断言四个入口都建出来了
    // 就等于守住这个回归。
    final nav = tester.getRect(find.byType(GlassSurface).last);
    await tester.tapAt(Offset(nav.right - 24, nav.center.dy));
    await _pumpFrames(tester);

    expect(find.text('保留后台运行'), findsOneWidget);
    expect(find.text('开机自启动'), findsOneWidget);
    expect(find.text('自动获取 ACID'), findsOneWidget);
    expect(find.text('查看日志文件'), findsOneWidget);
    await _flushMainNavigator(tester);
  });
}
