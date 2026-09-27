import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixtureChallenge = List.filled(9, 'c').join();

/// 包成 JSONP 的 UTF-8 响应。
///
/// [http.Response] 的 String 构造按 Latin-1 编码，装不下深澜返回的中文原因；带
/// charset 的字节响应才和真实服务器一致。
http.Response _utf8Response(String json) => http.Response.bytes(
  utf8.encode('jQueryCallback($json)'),
  200,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SrunClient 解析用户信息和 Challenge 的 JSONP callback', () async {
    final client = SrunClient(
      host: '10.0.0.1',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/rad_user_info')) {
          return http.Response(
            '  jQueryCallback({"error":"ok","client_ip":"10.0.0.8"})  ',
            200,
          );
        }
        return http.Response(
          'otherCallback({"challenge":"$_fixtureChallenge","client_ip":"10.0.0.8","ecode":0,"error":"ok"})',
          200,
        );
      }),
    );

    final userInfo = await client.getUserInfo();
    final challenge = await client.getChallenge(
      username: _fixtureUsername,
      ip: '10.0.0.8',
    );

    expect(userInfo.isOnline, isTrue);
    expect(userInfo.clientIp, '10.0.0.8');
    expect(challenge.challenge == _fixtureChallenge, isTrue);
    expect(challenge.isSuccess, isTrue);
  });

  test('DM 下线请求把目标 IP、unbind 和协议签名发到 rad_user_dm', () async {
    Uri? requested;
    final client = SrunClient(
      host: '10.0.0.1',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('jQueryCallback({"error":"ok"})', 200);
      }),
    );

    final result = await client.dmLogout(
      username: '2021000100000',
      ip: '10.0.0.9',
    );

    expect(result.accepted, isTrue);
    expect(requested!.path, '/cgi-bin/rad_user_dm');
    final query = requested!.queryParameters;
    expect(query['ip'], '10.0.0.9');
    expect(query['username'], '2021000100000');
    expect(query['unbind'], '1');
    // 签名是 time+username+ip+unbind+time 的无分隔符拼接；摘要算法本身由
    // test/srun_login_request_test.dart 的外部向量固定，这里只固定拼接形状。
    expect(
      query['sign'],
      SrunEnrypt.Sha1('${query['time']}202100010000010.0.0.91${query['time']}'),
    );
  });

  test('DM 下线响应不是 ok 时判为未受理', () async {
    final client = SrunClient(
      host: '10.0.0.1',
      client: MockClient((_) async {
        return _utf8Response(
          '{"error":"E6502","ecode":"E6502","error_msg":"该 IP 不在在线设备表中"}',
        );
      }),
    );

    final result = await client.dmLogout(
      username: '2021000100000',
      ip: '10.0.0.9',
    );

    expect(result.accepted, isFalse);
    expect(result.error, 'E6502');
    expect(result.ecode, 'E6502');
    expect(result.errorMessage, '该 IP 不在在线设备表中');
  });

  test('DM 下线响应缺少 error_msg 时退回到 error 字段作为原因', () async {
    // 部分部署把可读原因塞在 error 里而不是 error_msg，丢掉就等于没诊断信息。
    final client = SrunClient(
      host: '10.0.0.1',
      client: MockClient((_) async => _utf8Response('{"error":"E6504"}')),
    );

    final result = await client.dmLogout(
      username: '2021000100000',
      ip: '10.0.0.9',
    );

    expect(result.accepted, isFalse);
    expect(result.reason, 'E6504');
  });

  test('认证服务器无响应时在期限内结束检查', () async {
    var aborted = false;
    final client = SrunClient(
      host: '10.0.0.1',
      requestTimeout: const Duration(milliseconds: 20),
      client: MockClient.streaming((request, _) async {
        if (request is http.AbortableRequest) {
          request.abortTrigger!.then((_) => aborted = true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.StreamedResponse(Stream.value(<int>[]), 200);
      }),
    );

    final finished = client.getUserInfo().then(
      (_) => true,
      onError: (_) => true,
    );
    expect(
      await finished.timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => false,
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(aborted, isTrue);
  });
}
