import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixtureChallenge = List.filled(9, 'c').join();

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

    final accepted = await client.dmLogout(
      username: '2021000100000',
      ip: '10.0.0.9',
    );

    expect(accepted, isTrue);
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
        return http.Response(
          'jQueryCallback({"error":"some_parameter_error"})',
          200,
        );
      }),
    );

    expect(
      await client.dmLogout(username: '2021000100000', ip: '10.0.0.9'),
      isFalse,
    );
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
