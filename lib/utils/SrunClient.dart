// Powered by Kimi
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/ChallengeResponse.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';

import 'dart:convert';

import 'package:LinkUp/utils/RadUserInfo.dart';

/// `/cgi-bin/rad_user_dm` 的应答。
///
/// 深澜的 DM 接口只回答请求是否被受理，不回答目标会话是否已断开；受理之后的确认
/// 不在这里做。失败时用 `ecode`、`error_msg` 和 `error` 给出原因，但三者都可能
/// 缺失，部署之间也不一致，所以不假设其中任何一个必然存在。
class DmResult {
  const DmResult({
    required this.accepted,
    this.error,
    this.ecode,
    this.errorMessage,
  });

  factory DmResult.fromJson(Map<String, dynamic> json) {
    return DmResult(
      accepted: json['error'] == 'ok',
      error: _text(json['error']),
      ecode: _text(json['ecode']),
      errorMessage: _text(json['error_msg']),
    );
  }

  /// 服务器是否受理了这次下线请求。
  final bool accepted;

  /// 原始 `error` 字段。成功时是 `ok`，失败时可能装错误码也可能装可读原因。
  final String? error;

  /// `ecode` 字段，形如 `E6502`。
  final String? ecode;

  /// `error_msg` 字段，服务器给的中文原因。
  final String? errorMessage;

  /// 面向人的一句话原因；服务器和本地都没给原因时为 null。
  ///
  /// 优先级按官方 `translate()` 的做法，`error_msg` 与 `ecode` 比 `error` 更具体。
  String? get reason {
    final code = ecode ?? (error == 'ok' ? null : error);
    final detail = errorMessage;
    if (code != null && detail != null) return '$code $detail';
    return detail ?? code;
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class SrunClient {
  String host;
  String get baseURL => "http://" + host + "/cgi-bin";
  String get urlUserInfo => baseURL + "/rad_user_info";
  String get urlChallenge => baseURL + "/get_challenge";
  String urlPortalForHost(String host) => "http://$host/cgi-bin/srun_portal";

  String get callback => "jQueryCallback";
  String get userAgent =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36";
  final http.Client _client;
  final Duration requestTimeout;

  SrunClient({
    http.Client? client,
    this.host = defaultAuthServer,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// 更新认证服务器地址
  void setHost(String newHost) {
    host = newHost;
    LogUtil.info('[SrunClient] 认证服务器地址已更新: $host');
  }

  // 从 JSONP 提取 JSON
  String _extractJsonFromJsonp(String jsonp, String callbackName) {
    final trimmed = jsonp.trim();
    final prefix = '$callbackName(';
    if (trimmed.startsWith(prefix) && trimmed.endsWith(')')) {
      return trimmed.substring(prefix.length, trimmed.length - 1);
    }

    final start = trimmed.indexOf('(');
    final end = trimmed.lastIndexOf(')');
    if (start >= 0 && end > start) {
      return trimmed.substring(start + 1, end);
    }
    throw const FormatException('Invalid JSONP format');
  }

  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout);
    } on TimeoutException {
      abort.complete();
      rethrow;
    }
  }

  // 获取 IP 和在线状态
  Future<RadUserInfo> getUserInfo() async {
    final params = {
      'callback': callback,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse(urlUserInfo).replace(queryParameters: params);

    LogUtil.info('[SrunClient] 请求用户信息: $urlUserInfo');

    try {
      final response = await _get(uri, {
        'User-Agent': userAgent,
        'Accept': 'text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01',
      });

      LogUtil.info('[SrunClient] 用户信息响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      // 解析 JSONP
      final jsonStr = _extractJsonFromJsonp(response.body, callback);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final userInfo = RadUserInfo.fromJson(jsonData);
      LogUtil.info('[SrunClient] 用户信息解析成功: online=${userInfo.isOnline}');
      return userInfo;
    } on FormatException catch (e) {
      LogUtil.error('[SrunClient] 解析用户信息失败', e);
      throw Exception('JSONP parse error: $e');
    } on http.ClientException catch (e) {
      LogUtil.error('[SrunClient] 获取用户信息网络错误', e);
      throw Exception('Network error: $e');
    } catch (e) {
      LogUtil.error('[SrunClient] 获取用户信息失败', e);
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

    final uri = Uri.parse(urlChallenge).replace(queryParameters: params);

    LogUtil.info('[SrunClient] 请求 Challenge');

    try {
      final response = await _get(uri, {
        'User-Agent': userAgent,
        'Accept': 'text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01',
      });

      LogUtil.info('[SrunClient] Challenge 响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      // 解析 JSONP: jQuery123({...})
      final jsonStr = _extractJsonFromJsonp(response.body, callback);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final challengeResp = ChallengeResponse.fromJson(jsonData);

      // 检查返回状态
      if (!challengeResp.isSuccess) {
        LogUtil.warning(
          '[SrunClient] 获取 Challenge 失败: ${challengeResp.error} - ${challengeResp.errorMsg}',
        );
        throw Exception(
          'Get challenge failed: ${challengeResp.error} - ${challengeResp.errorMsg}',
        );
      }

      // 检查 challenge 是否为空（登录前必须检查）
      if (challengeResp.challenge.isEmpty) {
        LogUtil.warning('[SrunClient] Challenge token 为空');
        throw Exception('Challenge token is empty');
      }

      LogUtil.info('[SrunClient] 获取 Challenge 成功');
      return challengeResp;
    } on FormatException catch (e) {
      LogUtil.error('[SrunClient] 解析 Challenge 响应失败', e);
      throw Exception('JSONP parse error: $e');
    } on http.ClientException catch (e) {
      LogUtil.error('[SrunClient] 获取 Challenge 网络错误', e);
      throw Exception('Network error: $e');
    } catch (e) {
      LogUtil.error('[SrunClient] 获取 Challenge 失败', e);
      throw Exception('Get challenge failed: $e');
    }
  }

  /// 发送 JSONP 请求并提取 callback 内的 JSON。
  ///
  /// 登录服务通过此方法复用注入的 HTTP client，避免认证流程退回全局
  /// [http.get] 或共享的可变客户端。
  Future<Map<String, dynamic>> requestJsonp(
    String url,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse(url).replace(queryParameters: params);
    final displayUri = uri.replace(
      queryParameters: Map<String, String>.from(
        uri.queryParameters.map(
          (key, value) => MapEntry(
            key,
            const {
                  'password',
                  'sign',
                  'username',
                  'info',
                  'chksum',
                  'ip',
                  'ac_id',
                }.contains(key)
                ? '****'
                : value,
          ),
        ),
      ),
    );
    LogUtil.info('[SrunClient] HTTP GET: $displayUri');

    try {
      final response = await _get(uri, {
        'User-Agent': userAgent,
        'Accept': 'text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01',
      });
      if (response.statusCode != 200) {
        throw Exception('HTTP error: ${response.statusCode}');
      }

      final callbackName = params['callback'] ?? callback;
      final jsonString = _extractJsonFromJsonp(response.body, callbackName);
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        throw const FormatException('JSONP payload is not an object');
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      rethrow;
    } on http.ClientException {
      rethrow;
    } catch (error) {
      throw Exception('Srun request failed: $error');
    }
  }

  // DM 注销 — 调用 /cgi-bin/rad_user_dm，签名格式与登录不同
  Future<DmResult> dmLogout({
    required String username,
    required String ip,
  }) async {
    final time = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    const unbind = 1;
    final signStr = '$time$username$ip$unbind$time';
    final sign = SrunEnrypt.Sha1(signStr);

    final params = {
      'callback': callback,
      'ip': ip,
      'username': username,
      'time': time.toString(),
      'unbind': unbind.toString(),
      'sign': sign,
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    };

    final uri = Uri.parse('$baseURL/rad_user_dm')
        .replace(queryParameters: params);
    LogUtil.info('[SrunClient] DM 注销请求');

    try {
      final response = await _get(uri, {'User-Agent': userAgent});
      if (response.statusCode != 200) {
        // 状态码本身不含凭据，可以原样带回，作为可诊断的原因。
        return DmResult(
          accepted: false,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }
      final jsonStr = _extractJsonFromJsonp(response.body, callback);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final result = DmResult.fromJson(jsonData);
      await LogUtil.info('[SrunClient] DM 注销响应已解析');
      if (!result.accepted) {
        // 只记服务器给的原因，不记 username / ip / sign。
        await LogUtil.warning(
          '[SrunClient] DM 注销被拒绝: ${result.reason ?? '服务器未给出原因'}',
        );
      }
      return result;
    } catch (e) {
      await LogUtil.error('[SrunClient] DM 注销失败', e);
      // 不把异常原文带进结果：ClientException 会带上完整查询串，里面有账号和签名。
      return const DmResult(accepted: false, errorMessage: '请求未完成');
    }
  }

  // 关闭客户端
  void dispose() {
    _client.close();
  }
}
