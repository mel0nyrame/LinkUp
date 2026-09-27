import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/components/StatusCard.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('账号验证失败时显示可操作提示', (tester) async {
    final status = ValueNotifier(
      const AuthRuntimeState(
        status: AuthenticationStatus.failed,
        reason: AuthenticationReason.invalidCredentials,
        message: '登录失败',
      ),
    );
    final acid = ValueNotifier<String?>(null);
    final online = ValueNotifier(false);
    final userInfo = ValueNotifier<RadUserInfo?>(null);
    final operation = ValueNotifier<OverviewOperation>((
      loading: false,
      message: null,
    ));
    addTearDown(status.dispose);
    addTearDown(acid.dispose);
    addTearDown(online.dispose);
    addTearDown(userInfo.dispose);
    addTearDown(operation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OverviewPage(
          status: status,
          acid: acid,
          online: online,
          userInfo: userInfo,
          operation: operation,
        ),
      ),
    );

    expect(find.text('请在设置中检查账号和密码'), findsOneWidget);
  });

  testWidgets('ACID 更新只刷新探测行', (tester) async {
    final status = ValueNotifier(
      const AuthRuntimeState(status: AuthenticationStatus.checking),
    );
    final acid = ValueNotifier<String?>('143');
    final online = ValueNotifier(false);
    final userInfo = ValueNotifier<RadUserInfo?>(null);
    final operation = ValueNotifier<OverviewOperation>((
      loading: false,
      message: null,
    ));
    addTearDown(status.dispose);
    addTearDown(acid.dispose);
    addTearDown(online.dispose);
    addTearDown(userInfo.dispose);
    addTearDown(operation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OverviewPage(
          status: status,
          acid: acid,
          online: online,
          userInfo: userInfo,
          operation: operation,
        ),
      ),
    );
    final cardBefore = tester.widget<Statuscard>(find.byType(Statuscard));

    acid.value = '7';
    await tester.pump();

    expect(find.text('正在尝试 ACID: 7'), findsOneWidget);
    expect(
      tester.widget<Statuscard>(find.byType(Statuscard)),
      same(cardBefore),
    );
  });

  testWidgets('WiFi 断开后显示明确状态且不保留旧在线信息', (tester) async {
    final status = ValueNotifier(
      const AuthRuntimeState(
        status: AuthenticationStatus.offline,
        message: 'WiFi 未连接',
        reason: AuthenticationReason.wifiUnavailable,
      ),
    );
    final userInfo = ValueNotifier<RadUserInfo?>(
      RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
    );
    final acid = ValueNotifier<String?>(null);
    final online = ValueNotifier(false);
    final operation = ValueNotifier<OverviewOperation>((
      loading: false,
      message: null,
    ));
    addTearDown(status.dispose);
    addTearDown(userInfo.dispose);
    addTearDown(acid.dispose);
    addTearDown(online.dispose);
    addTearDown(operation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OverviewPage(
          status: status,
          acid: acid,
          online: online,
          userInfo: userInfo,
          operation: operation,
        ),
      ),
    );

    expect(
      tester.widget<Statuscard>(find.byType(Statuscard)).statusText,
      'WiFi 未连接',
    );
    expect(find.text('10.0.0.8'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
