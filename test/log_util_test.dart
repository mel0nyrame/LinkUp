import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/LogUtil.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linkup-log-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    await LogUtil.resetForTest();
  });

  tearDown(() async {
    await LogUtil.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('日志入口移除认证参数与异常内容', () async {
    await LogUtil.info(
      '请求 https://example.test/login?username=alice&password=secret',
    );
    await LogUtil.error('token:secret2', Exception('secret3'));

    final content = await LogUtil.readLog();
    expect(content, contains('[URL_QUERY_REDACTED]'));
    expect(content, contains('token=[REDACTED]'));
    expect(content, isNot(contains('alice')));
    expect(content, isNot(contains('secret')));
    expect(content, contains('异常类型: _Exception'));
  });

  test('日志文件超过上限后保留尾部', () async {
    await LogUtil.info('A' * (1024 * 1024));
    final path = await LogUtil.getLogFilePath();
    expect(path, isNotNull);
    expect(await File(path!).length(), lessThanOrEqualTo(1024 * 1024));
    expect(await LogUtil.readLog(), contains('AAAA'));
  });
}
