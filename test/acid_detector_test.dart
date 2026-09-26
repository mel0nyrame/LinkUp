import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:LinkUp/utils/AcidDetector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reality 优先使用拦截重定向中的 index ACID', () async {
    final detector = AcidDetector(
      baseUrl: 'http://server',
      client: MockClient((request) async {
        if (request.url.host != 'server') {
          return http.Response(
            '',
            302,
            headers: {'location': 'http://server/index_143.html'},
            request: request,
          );
        }
        if (request.url.path == '/index_143.html') {
          return http.Response(
            "<script>top.self.location.href='/srun_portal_pc?ac_id=1'</script>",
            200,
            request: request,
          );
        }
        return http.Response('<html>srun_portal</html>', 200, request: request);
      }),
    );

    final (acid, _, error) = await detector.reality();
    expect(error, isNull);
    expect(acid, '143');
  });

  test('根目录探测识别 index 页面路径中的 ACID', () async {
    final detector = AcidDetector(
      baseUrl: 'http://server',
      client: MockClient((request) async {
        return http.Response(
          '',
          302,
          headers: {'location': 'http://server/index_143.html'},
          request: request,
        );
      }),
    );

    expect(await detector.detectAcid(), '143');
  });

  test('AcidDetector 使用注入 HTTP client，reset 后不复用旧 Portal 页面', () async {
    final requests = <Uri>[];
    final detector = AcidDetector(
      baseUrl: 'http://server/cgi-bin',
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/srun_portal_pc.php')) {
          return http.Response('<input name="ac_id" value="143">', 200);
        }
        return http.Response('<html></html>', 200);
      }),
    );

    expect(await detector.detectAcid(), '143');
    final firstPageRequestCount = requests
        .where((uri) => uri.path.endsWith('/srun_portal_pc.php'))
        .length;

    detector.reset();
    expect(await detector.detectAcid(), '143');
    final secondPageRequestCount = requests
        .where((uri) => uri.path.endsWith('/srun_portal_pc.php'))
        .length;

    expect(firstPageRequestCount, 1);
    expect(secondPageRequestCount, 2);
  });

  test('reset 后旧的在途页面响应不会写回新缓存', () async {
    final firstPage = Completer<http.Response>();
    final firstPageRequested = Completer<void>();
    var pageCalls = 0;
    final detector = AcidDetector(
      baseUrl: 'http://server/cgi-bin',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/srun_portal_pc.php')) {
          pageCalls++;
          if (pageCalls == 1) {
            firstPageRequested.complete();
            return firstPage.future;
          }
          return http.Response('<input name="ac_id" value="143">', 200);
        }
        return http.Response('<html></html>', 200);
      }),
    );

    final oldAttempt = detector.detectAcid();
    await firstPageRequested.future;
    detector.reset();
    firstPage.complete(http.Response('<input name="ac_id" value="1">', 200));

    expect(await oldAttempt, isNull);
    expect(await detector.detectAcid(), '143');
  });
}
