import 'package:http/http.dart' as http;

import 'package:LinkUp/utils/AcidDetector.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunLogin.dart';

/// 生产协议适配器。所有 Srun 请求都通过同一组实例依赖，不使用静态客户端。
class SrunAuthenticationProtocol implements AuthenticationProtocol {
  SrunAuthenticationProtocol({
    http.Client? httpClient,
    String initialServer = '10.129.1.1',
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _server = initialServer {
    _client = SrunClient(client: _httpClient, host: initialServer);
    _login = SrunLogin(client: _client);
    _detector = AcidDetector(baseUrl: _client.baseURL, client: _httpClient);
  }

  final http.Client _httpClient;
  final bool _ownsHttpClient;
  late final SrunClient _client;
  late final SrunLogin _login;
  late AcidDetector _detector;
  String _server;

  void _useServer(String server) {
    if (_server == server && _detector.baseUrl == _client.baseURL) return;
    _server = server;
    _client.setHost(server);
    _detector = AcidDetector(baseUrl: _client.baseURL, client: _httpClient);
  }

  @override
  Future<RealityProbeResult> reality(
    String server, {
    bool getAcid = true,
  }) async {
    _useServer(server);
    final (acid, isOnline, error) = await _detector.reality(getAcid: getAcid);
    return RealityProbeResult(acid: acid, isOnline: isOnline, error: error);
  }

  @override
  Future<RadUserInfo> getUserInfo(String server) async {
    _useServer(server);
    return _client.getUserInfo();
  }

  @override
  Future<ChallengeResponse> getChallenge({
    required String server,
    required String username,
    required String ip,
  }) async {
    _useServer(server);
    return _client.getChallenge(username: username, ip: ip);
  }

  @override
  Future<LoginResult> login({
    required String server,
    required AuthParameters parameters,
    required String password,
    required String challenge,
  }) async {
    _useServer(server);
    return _login.login(
      parameters: parameters,
      password: password,
      challenge: challenge,
    );
  }

  @override
  Future<String?> detectAcid(String server) async {
    _useServer(server);
    return _detector.detectAcid();
  }

  @override
  Future<String?> detectEnc(String server) async {
    _useServer(server);
    return _detector.detectEnc();
  }

  @override
  Future<bool> logout({
    required String server,
    required String username,
    required String ip,
  }) async {
    _useServer(server);
    return _login.dmLogout(username: username, ip: ip);
  }

  @override
  void reset() {
    _detector.reset();
  }

  @override
  void dispose() {
    if (_ownsHttpClient) _client.dispose();
  }
}
