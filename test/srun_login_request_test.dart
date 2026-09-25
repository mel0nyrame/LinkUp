import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

final _fixtureUsername = List.filled(8, 'u').join();
final _fixturePassword = List.filled(8, 'p').join();
final _fixtureChallenge = List.filled(9, 'c').join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(query['password']?.startsWith('{MD5}'), isTrue);
    expect(query['info']?.startsWith('{SRBX1}'), isTrue);

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
}
