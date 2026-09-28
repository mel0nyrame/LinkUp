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
    await LogUtil.info('{"password":"json-secret","username": "json-user"}');
    await LogUtil.error('token:secret2', Exception('secret3'));

    final content = await LogUtil.readLog();
    expect(content, contains('[URL_QUERY_REDACTED]'));
    expect(content, contains('token=[REDACTED]'));
    expect(content, contains('"password":"[REDACTED]"'));
    expect(content, contains('"username": "[REDACTED]"'));
    expect(content, isNot(contains('alice')));
    expect(content, isNot(contains('secret')));
    expect(content, isNot(contains('json-user')));
    expect(content, contains('异常类型: _Exception'));
  });

  test('日志文件超过上限后保留尾部', () async {
    await LogUtil.info('A' * (1024 * 1024));
    final path = await LogUtil.getLogFilePath();
    expect(path, isNotNull);
    expect(await File(path!).length(), lessThanOrEqualTo(1024 * 1024));
    expect(await LogUtil.readLog(), contains('AAAA'));
  });

  test('清理与后续写入按调用顺序执行', () async {
    await LogUtil.info('清理前的记录');

    final clearing = LogUtil.clear();
    final writing = LogUtil.info('清理后的记录');
    await Future.wait([clearing, writing]);

    final content = await LogUtil.readLog();
    expect(content, isNot(contains('清理前的记录')));
    expect(content, contains('清理后的记录'));
  });

  test('读取失败时向界面抛出通用错误，不包含路径', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'path-unavailable'),
        );

    await expectLater(LogUtil.readLogOrThrow(), throwsA(isA<StateError>()));
  });

  test('清空失败会反馈错误且不阻塞后续日志写入', () async {
    await LogUtil.info('清空前记录');
    final path = await LogUtil.getLogFilePath();
    expect(path, isNotNull);

    await File(path!).delete();
    await Directory(path).create();
    await expectLater(
      LogUtil.clearOrThrow(),
      throwsA(isA<FileSystemException>()),
    );

    await Directory(path).delete();
    await File(path).create();
    await LogUtil.info('恢复后的记录');
    expect(await LogUtil.readLog(), contains('恢复后的记录'));
  });
}
