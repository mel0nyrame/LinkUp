import 'dart:async';

import 'package:LinkUp/navigation/MainNavigation.dart';
import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeState.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_liquid_glass/lightweight_liquid_glass.dart';

class _FakeAuthRuntimeClient extends AuthRuntimeClient {
  final _states = StreamController<AuthRuntimeState>.broadcast();

  @override
  Stream<AuthRuntimeState> get states => _states.stream;

  void emit(AuthRuntimeState state) => _states.add(state);

  @override
  Future<void> attach() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => _states.close();
}

void main() {
  testWidgets('认证状态推送不重建导航和隐藏设置页', (tester) async {
    final client = _FakeAuthRuntimeClient();
    var overviewBuilds = 0;
    var settingsBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigator.test(
          client: client,
          pages: [
            Builder(
              builder: (context) {
                overviewBuilds++;
                return const Text('概况内容');
              },
            ),
            Builder(
              builder: (context) {
                settingsBuilds++;
                return const Text('设置内容');
              },
            ),
          ],
        ),
      ),
    );
    final beforeOverview = overviewBuilds;
    final beforeSettings = settingsBuilds;

    client.emit(const AuthRuntimeState(status: AuthenticationStatus.checking));
    await tester.pump();

    expect(overviewBuilds, beforeOverview);
    expect(settingsBuilds, beforeSettings);
    expect(
      TickerMode.valuesOf(
        tester.element(find.text('设置内容', skipOffstage: false)),
      ).enabled,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('底部导航在概况和设置间切换并保留选中状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigator.test(
          client: _FakeAuthRuntimeClient(),
          pages: const [
            Center(child: Text('概况内容')),
            Center(child: Text('设置内容')),
          ],
        ),
      ),
    );

    expect(find.text('概况内容'), findsOneWidget);
    expect(find.text('设置内容'), findsNothing);
    expect(find.text('概况'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    final navigation = tester.getRect(find.byType(GlassSurface));
    await tester.tapAt(Offset(navigation.right - 24, navigation.center.dy));
    await tester.pump();

    expect(find.text('设置内容'), findsOneWidget);
    expect(find.text('概况内容'), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.speed_outlined), findsOneWidget);

    await tester.tapAt(Offset(navigation.left + 24, navigation.center.dy));
    await tester.pump();

    expect(find.text('概况内容'), findsOneWidget);
    expect(find.text('设置内容'), findsNothing);
    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
