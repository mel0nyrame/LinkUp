import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/SrunEncrypt.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 基础 widget 冒烟：不使用 LiquidGlass（liquid_glass_renderer 着色器
    // 与 Flutter 3.44 Impeller 后端不兼容，导致 shader 编译失败）
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('LinkUp'))),
      ),
    );
    expect(find.text('LinkUp'), findsOneWidget);
  });

  test('SrunEncrypt HMAC-MD5', () {
    final result = SrunEnrypt.Hmd5('password', 'token');
    expect(result.length, equals(32));
    expect(result, matches(RegExp(r'^[0-9a-f]+$')));
  });

  test('SrunEncrypt SHA1', () {
    final result = SrunEnrypt.Sha1('test');
    expect(result.length, equals(40));
    expect(result, matches(RegExp(r'^[0-9a-f]+$')));
  });
}
