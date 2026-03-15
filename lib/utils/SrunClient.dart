// Powered by Kimi
import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'dart:convert';
import 'package:LinkUp/utils/RadUserInfo.dart';

class SrunClient {
  String host = "10.129.1.1";
  String get baseURL => "http://" + host + "/cgi-bin";
  String get urlUserInfo => baseURL + "/rad_user_info";
  String get urlChallenge => baseURL + "/get_challenge";
  String get urlPortal => baseURL + "/srun_portal";

  String get callback => "jQueryCallback";
  String get userAgent =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36";
  String get type => "1";
  String get n => "200";
  String get enc => "srun_bx1";

  final http.Client _client;

  SrunClient({http.Client? client}) : _client = client ?? http.Client();

  // 从 JSONP 提取 JSON
  String _extractJsonFromJsonp(String jsonp, String callbackName) {
    final prefix = '$callbackName(';
    if (!jsonp.startsWith(prefix)) {
      throw FormatException('Invalid JSONP format');
    }
    if (!jsonp.endsWith(')')) {
      throw FormatException('Invalid JSONP ending');
    }
    return jsonp.substring(prefix.length, jsonp.length - 1);
  }

  // 获取 IP 和在线状态
  Future<RadUserInfo> getUserInfo() async {
    final params = {
      'callback': callback,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse(
      urlUserInfo,
    ).replace(queryParameters: params);

    try {
      final response = await _client.get(
        uri,
        headers: {'User-Agent': userAgent},
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      // 解析 JSONP
      final jsonStr = _extractJsonFromJsonp(response.body, callback);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      return RadUserInfo.fromJson(jsonData);
    } on FormatException catch (e) {
      throw Exception('JSONP parse error: $e');
    } on http.ClientException catch (e) {
      throw Exception('Network error: $e');
    } catch (e) {
      throw Exception('Get user info failed: $e');
    }
  }

  Future<ChallengeResponse> getChallenge({
    required String username,
    required String ip,
  }) async {
    
    final params = {
      'callback': callback,
      'username': username,
      'ip': ip,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse(urlChallenge).replace(
      queryParameters: params,
    );

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': userAgent,
          'Accept': 'text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      // 解析 JSONP: jQuery123({...})
      final jsonStr = _extractJsonFromJsonp(response.body, callback);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final challengeResp = ChallengeResponse.fromJson(jsonData);
      
      // 检查返回状态
      if (!challengeResp.isSuccess) {
        throw Exception('Get challenge failed: ${challengeResp.error} - ${challengeResp.errorMsg}');
      }

      // 检查 challenge 是否为空（登录前必须检查）
      if (challengeResp.challenge.isEmpty) {
        throw Exception('Challenge token is empty');
      }

      return challengeResp;

    } on FormatException catch (e) {
      throw Exception('JSONP parse error: $e');
    } on http.ClientException catch (e) {
      throw Exception('Network error: $e');
    } catch (e) {
      throw Exception('Get challenge failed: $e');
    }
  }

  // 检查是否在线
  Future<bool> checkOnline() async {
    try {
      final info = await getUserInfo();
      return info.isOnline;
    } catch (e) {
      return false;
    }
  }

  // 关闭客户端
  void dispose() {
    _client.close();
  }
}
