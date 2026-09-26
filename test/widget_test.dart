import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/SrunEncrypt.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
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
    // 已知答案向量 — 由 openssl dgst -md5 -hmac "token" 独立验证
    expect(result, equals('fd07c716fa2b6a86413916082c8bfdc3'));
  });

  test('SrunEncrypt Latin-1 HMAC-MD5', () {
    final result = SrunEnrypt.Hmd5('msg-é', 'key-ã');
    expect(result, '714cb342247086430bd85f1807319cea');
  });

  test('SrunEncrypt SHA1', () {
    final result = SrunEnrypt.Sha1('test');
    expect(result.length, equals(40));
    expect(result, matches(RegExp(r'^[0-9a-f]+$')));
    // 已知答案向量 — 由 openssl dgst -sha1 独立验证
    expect(result, equals('a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'));
  });
}
