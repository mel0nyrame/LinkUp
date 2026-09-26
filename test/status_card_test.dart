import 'package:LinkUp/components/StatusCard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightweight_liquid_glass/lightweight_liquid_glass.dart';

/// 把状态卡放进滚动容器，模拟概况页的实际承载方式。
Widget _host(Statuscard card) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: card)),
  );
}

/// 状态圆点：脉冲只作用在这一层。
Finder _dot() => find.descendant(
  of: find.byType(Statuscard),
  matching: find.byType(Transform),
);

/// 圆点的实际缩放。`tester.getRect` 读的是 `RenderTransform` 自己的布局
/// 尺寸，不含它施加给子节点的矩阵，所以这里直接读矩阵。
double _dotScale(WidgetTester tester) =>
    tester.widget<Transform>(_dot()).transform.getMaxScaleOnAxis();

void main() {
  testWidgets('在线时显示已连接', (tester) async {
    await tester.pumpWidget(_host(const Statuscard(isOnline: true)));

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('未连接'), findsNothing);
  });

  testWidgets('离线时显示未连接与错误提示', (tester) async {
    await tester.pumpWidget(_host(const Statuscard(errorMsg: 'Portal 认证失败')));

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('Portal 认证失败'), findsOneWidget);
  });

  testWidgets('认证中显示当前 ACID 进度', (tester) async {
    await tester.pumpWidget(
      _host(const Statuscard(statusText: '未连接', detailText: '正在尝试 ACID: 143')),
    );

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('正在尝试 ACID: 143'), findsOneWidget);
  });

  testWidgets('长错误提示换行显示且不溢出', (tester) async {
    await tester.pumpWidget(
      _host(const Statuscard(errorMsg: 'Portal 返回错误，认证参数被拒绝，请稍后重试并检查账号配置是否完整')),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Portal 返回错误'), findsOneWidget);
  });

  testWidgets('状态卡用共用玻璃表面绘制，且不采样滚动背景', (tester) async {
    await tester.pumpWidget(_host(const Statuscard(isOnline: true)));

    // 状态卡和底部导航都用 GlassSurface 承载观感，观感本身无法从外部量出；
    // 两者在实现上唯一的差别是导航保留实时模糊，这一条可以从卡内是否出现
    // 背景采样看出来。
    expect(find.byType(GlassSurface), findsOneWidget);
    // 状态卡随概况页滚动，身后只有静态渐变：采样背景没有视觉收益，
    // 持续滑动却要重复读取背景。导航的实时模糊不应出现在状态卡内。
    expect(
      find.descendant(
        of: find.byType(Statuscard),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('状态圆点持续脉冲', (tester) async {
    await tester.pumpWidget(_host(const Statuscard(isOnline: true)));

    final double start = _dotScale(tester);
    await tester.pump(const Duration(milliseconds: 1200));
    final double middle = _dotScale(tester);

    expect(middle, isNot(closeTo(start, 0.01)));
  });
}
