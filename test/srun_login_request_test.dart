import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixturePassword = List.filled(8, 'p').join();
final _fixtureChallenge = List.filled(9, 'c').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sha1 按 Latin-1 字节摘要并输出小写十六进制', () {
    // 期望值由仓库外的 `printf '%s' <串> | sha1sum` 独立算出，不复用被测实现推导。
    expect(SrunEnrypt.Sha1('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
    // 深澜 DM 签名的输入串：time+username+ip+unbind+time，无分隔符。
    expect(
      SrunEnrypt.Sha1('1700000000202100010000010.0.0.91700000000'),
      'bbf4b0ba15687ff31329b161005a229b9b8db681',
    );
  });

  test('SrunLogin 使用实例 HTTP client，并从同一组参数构造登录字段', () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      return http.Response(
        'testCallback({"error":"ok","res":"login_ok"})',
        200,
      );
    });
    final srunClient = SrunClient(client: httpClient, host: '10.0.0.1');
    final login = SrunLogin(client: srunClient);

    final result = await login.login(
      parameters: AuthParameters(
        server: '10.0.0.1',
        username: _fixtureUsername,
        ip: '10.0.0.8',
        acid: '143',
        enc: 'srun_bx2',
        n: '201',
        type: '7',
        callback: 'testCallback',
      ),
      password: _fixturePassword,
      challenge: _fixtureChallenge,
    );

    expect(result.success, isTrue);
    expect(requests, hasLength(1));
    final query = requests.single.url.queryParameters;
    expect(query['callback'], 'testCallback');
    expect(query['username'] == _fixtureUsername, isTrue);
    expect(query['ac_id'], '143');
    expect(query['ip'], '10.0.0.8');
    expect(query['n'], '201');
    expect(query['type'], '7');
    expect(query['os'], 'Windows 10');
    expect(query['name'], 'windows');
    expect(query['double_stack'], '0');
    expect(query['password']?.startsWith('{MD5}'), isTrue);
    expect(query['info']?.startsWith('{SRBX1}'), isTrue);
    final expectedChecksum = SrunEnrypt.Sha1(
      '$_fixtureChallenge$_fixtureUsername'
      '$_fixtureChallenge${SrunEnrypt.Hmd5(_fixturePassword, _fixtureChallenge)}'
      '$_fixtureChallenge${query['ac_id']}'
      '$_fixtureChallenge${query['ip']}'
      '$_fixtureChallenge${query['n']}'
      '$_fixtureChallenge${query['type']}'
      '$_fixtureChallenge${query['info']}',
    );
    expect(query['chksum'], expectedChecksum);

    expect(
      SrunInfo(
        username: _fixtureUsername,
        password: _fixturePassword,
        ip: '10.0.0.8',
        acid: '143',
        encVer: 'srun_bx2',
      ).encVer,
      'srun_bx1',
    );
    expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(query['chksum'] ?? ''), isTrue);
  });

  test('SrunLogin 实例不共享可变认证服务器状态', () {
    final first = SrunLogin(
      client: SrunClient(
        client: MockClient(
          (_) async => http.Response('jQueryCallback({})', 200),
        ),
        host: '10.0.0.1',
      ),
    );
    final second = SrunLogin(
      client: SrunClient(
        client: MockClient(
          (_) async => http.Response('jQueryCallback({})', 200),
        ),
        host: '10.0.0.2',
      ),
    );

    first.client.setHost('10.0.0.9');

    expect(first.client.host, '10.0.0.9');
    expect(second.client.host, '10.0.0.2');
  });

  test('SrunClient 默认服务器跟随配置常量', () {
    final client = SrunClient(
      client: MockClient((_) async => http.Response('testCallback({})', 200)),
    );
    expect(client.host, defaultAuthServer);
    client.dispose();
  });

  test('Portal 错误分类保留可操作原因', () async {
    for (final (response, expected) in [
      (
        '{"error":"fail","error_msg":"","res":"E2901"}',
        LoginErrorType.authFailed,
      ),
      (
        '{"error":"fail","error_msg":"invalid ac_id","res":""}',
        LoginErrorType.acIdError,
      ),
      for (final code in ['E2905', 'E3001'])
        (
          '{"error":"fail","error_msg":"","res":"$code"}',
          LoginErrorType.paymentRequired,
        ),
      (
        '{"error":"fail","error_msg":"账号欠费","res":"E2905"}',
        LoginErrorType.paymentRequired,
      ),
      for (final code in ['E2902', 'E2606'])
        (
          '{"error":"fail","error_msg":"","res":"$code"}',
          LoginErrorType.accountUnavailable,
        ),
      (
        '{"error":"fail","error_msg":"账号已停用","res":"E2902"}',
        LoginErrorType.accountUnavailable,
      ),
      (
        '{"error":"fail","error_msg":"","res":"E2620"}',
        LoginErrorType.deviceLimit,
      ),
    ]) {
      final login = SrunLogin(
        client: SrunClient(
          client: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode('testCallback($response)'),
              200,
              headers: {'content-type': 'text/javascript; charset=utf-8'},
            ),
          ),
          host: '10.0.0.1',
        ),
      );
      final result = await login.login(
        parameters: AuthParameters(
          server: '10.0.0.1',
          username: _fixtureUsername,
          ip: '10.0.0.8',
          acid: '143',
          callback: 'testCallback',
        ),
        password: _fixturePassword,
        challenge: _fixtureChallenge,
      );

      expect(result.success, isFalse);
      expect(
        result.errorType,
        expected,
        reason: '$response → ${result.message}',
      );
    }
  });
}
