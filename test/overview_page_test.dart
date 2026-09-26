import 'package:LinkUp/page/OverViewPage.dart';
import 'package:LinkUp/components/StatusCard.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WiFi 断开后显示明确状态且不保留旧在线信息', (tester) async {
    final status = ValueNotifier(
      const AuthRuntimeState(
        status: AuthenticationStatus.offline,
        isOnline: false,
        message: 'WiFi 未连接',
        reason: AuthenticationReason.wifiUnavailable,
      ),
    );
    final userInfo = ValueNotifier<RadUserInfo?>(
      RadUserInfo(clientIp: '10.0.0.8', onlineIp: '10.0.0.8', error: 'ok'),
    );
    final operation = ValueNotifier<OverviewOperation>((
      loading: false,
      message: null,
    ));
    addTearDown(status.dispose);
    addTearDown(userInfo.dispose);
    addTearDown(operation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OverviewPage(
          status: status,
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
