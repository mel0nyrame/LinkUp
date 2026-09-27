import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 登录错误类型枚举
enum LoginErrorType {
  success, // 登录成功
  networkError, // 网络错误
  parseError, // 解析错误
  authFailed, // 认证失败（账号密码错误）
  accountUnavailable, // 账号停用或被禁用
  paymentRequired, // 欠费或流量用尽
  deviceLimit, // 同时在线设备数超限
  alreadyOnline, // 已经在线
  ipNotAllowed, // IP 不允许
  acIdError, // ACID 错误
  challengeExpired, // Challenge 过期
  serverError, // 服务器错误
  unknown, // 未知错误
}

/// 登录结果类
class LoginResult {
  final bool success;
  final String message;
  final LoginErrorType errorType;

  LoginResult({
    required this.success,
    required this.message,
    this.errorType = LoginErrorType.unknown,
  });

  @override
  String toString() {
    return 'LoginResult(success: $success, message: $message, type: $errorType)';
  }
}

class SrunLogin {
  SrunLogin({SrunClient? client, http.Client? httpClient})
    : client = client ?? SrunClient(client: httpClient);

  final SrunClient client;

  /// 根据服务器返回的错误信息分析错误类型
  /// 参考 Go 代码中的错误码映射
  static LoginErrorType _analyzeErrorType(String errorMsg, String res) {
    final msgLower = errorMsg.toLowerCase();
    final resLower = res.toLowerCase();

    // 注意：alreadyOnline 检测已移至 login 成功路径 (error == 'ok' 时先判断)，
    // _analyzeErrorType 仅在失败分支被调用，已不可能进入 error == 'ok' 的分支

    if (res.contains('E2905') ||
        res.contains('E3001') ||
        msgLower.contains('欠费') ||
        msgLower.contains('流量用尽') ||
        msgLower.contains('时长用尽')) {
      return LoginErrorType.paymentRequired;
    }

    if (res.contains('E2902') || res.contains('E2606')) {
      return LoginErrorType.accountUnavailable;
    }

    if (res.contains('E2620')) {
      return LoginErrorType.deviceLimit;
    }

    // 账号密码错误 - 包含常见错误码
    if (msgLower.contains('password') ||
        msgLower.contains('账号') ||
        msgLower.contains('密码') ||
        msgLower.contains('account') ||
        msgLower.contains('username') ||
        resLower.contains('password') ||
        res.contains('E2901') || // 密码错误或账号不存在
        res.contains('E2553')) {
      return LoginErrorType.authFailed;
    }

    // ACID 错误
    if (msgLower.contains('acid') ||
        msgLower.contains('ac_id') ||
        resLower.contains('acid')) {
      return LoginErrorType.acIdError;
    }

    // IP 相关错误
    if (msgLower.contains('ip') ||
        resLower.contains('ip') ||
        res.contains('E2821') || // IP 不在线
        res.contains('E2833')) {
      // IP 已经被占用
      return LoginErrorType.ipNotAllowed;
    }

    // Challenge 过期
    if (msgLower.contains('challenge') ||
        msgLower.contains('token') ||
        msgLower.contains('过期') ||
        msgLower.contains('expire')) {
      return LoginErrorType.challengeExpired;
    }

    // 服务器错误
    if (msgLower.contains('server') ||
        msgLower.contains('服务器') ||
        msgLower.contains('busy') ||
        msgLower.contains('繁忙') ||
        res.contains('E2602')) {
      // 认证设备响应超时
      return LoginErrorType.serverError;
    }

    return LoginErrorType.unknown;
  }

  Future<LoginResult> login({
    required AuthParameters parameters,
    required String password,
    required String challenge,
  }) {
    return _loginInternal(parameters, password, challenge);
  }

  Future<LoginResult> _loginInternal(
    AuthParameters parameters,
    String password,
    String challenge,
  ) async {
    try {
      final hmd5Password = SrunEnrypt.Hmd5(password, challenge);

      final infoObj = SrunInfo(
        username: parameters.username,
        password: password,
        ip: parameters.ip,
        acid: parameters.acid,
        encVer: parameters.enc,
      );

      final info = SrunEnrypt.getInfo(
        infoObj.toJson(),
        challenge,
        prefix: parameters.protocolPrefix,
      );

      final chkStr = SrunEnrypt.Chkstr(
        challenge,
        parameters.username,
        hmd5Password,
        parameters.acid,
        parameters.ip,
        parameters.n,
        parameters.type,
        info,
      );

      final chkSum = SrunEnrypt.Sha1(chkStr);
      final currentTime = DateTime.now().millisecondsSinceEpoch.toString();

      final params = {
        'action': 'login',
        'callback': parameters.callback,
        'username': parameters.username,
        // 仅支持 MD5 密码方案；OTP 短信验证码登录暂未实现。
        'password': '{MD5}$hmd5Password',
        'os': 'Windows 10',
        'name': 'windows',
        'double_stack': '0',
        'chksum': chkSum,
        'info': info,
        'ac_id': parameters.acid,
        'ip': parameters.ip,
        'n': parameters.n,
        'type': parameters.type,
        '_': currentTime,
      };

      LogUtil.info('发送登录请求');

      // 使用 doRequest 发送请求并解析响应
      final result = await doRequest<Map<String, dynamic>>(
        client.urlPortalForHost(parameters.server),
        params,
        <String, dynamic>{},
      );

      LogUtil.info('登录响应已解析');

      // doRequest 返回的是解析后的 Map，如果为 null 表示解析失败
      if (result == null) {
        return LoginResult(
          success: false,
          message: '解析响应失败',
          errorType: LoginErrorType.parseError,
        );
      }

      // 解析结果
      final error = result['error'] as String? ?? '';
      final errorMsg = result['error_msg'] as String? ?? '';
      final sucMsg = result['suc_msg'] as String? ?? '';
      final res = result['res'] as String? ?? '';

      LogUtil.info('登录响应字段已解析');

      final resLower = res.toLowerCase();

      // 已经在线 — error == 'ok' 但 res 指示本次登录是冗余操作。
      // 必须先于通用成功检查，否则会被误归类为普通 success
      if (error == 'ok' &&
          (resLower.contains('login_ok') ||
              resLower.contains('already_online'))) {
        return LoginResult(
          success: true,
          message: '已经在线，无需重复登录',
          errorType: LoginErrorType.alreadyOnline,
        );
      }

      // 检查登录结果
      // error == 'ok' 表示成功，或者 suc_msg == 'login_ok' 表示成功
      if (error == 'ok' || sucMsg == 'login_ok') {
        return LoginResult(
          success: true,
          message: '登录成功',
          errorType: LoginErrorType.success,
        );
      } else {
        // 登录失败，分析错误类型
        final errorType = _analyzeErrorType(errorMsg, res);
        // 构建错误信息
        String failMessage = errorMsg.isNotEmpty ? errorMsg : error;
        if (failMessage.isEmpty) {
          failMessage = '未知错误';
        }
        if (res.isNotEmpty && !failMessage.contains(res)) {
          failMessage += ' ($res)';
        }

        return LoginResult(
          success: false,
          message: failMessage,
          errorType: errorType,
        );
      }
    } on FormatException catch (e) {
      LogUtil.error('登录响应格式错误', e);
      return LoginResult(
        success: false,
        message: '响应格式错误: $e',
        errorType: LoginErrorType.parseError,
      );
    } on http.ClientException catch (e) {
      LogUtil.error('登录网络错误', e);
      return LoginResult(
        success: false,
        message: '网络错误: $e',
        errorType: LoginErrorType.networkError,
      );
    } catch (e, stackTrace) {
      LogUtil.error('登录异常', e, stackTrace);
      return LoginResult(
        success: false,
        message: '登录异常: $e',
        errorType: LoginErrorType.unknown,
      );
    }
  }

  /// DM 注销 — 使用 /cgi-bin/rad_user_dm 端点。
  /// 签名格式 sha1(time + username + ip + 1 + time)，与登录加密链完全不同。
  Future<DmResult> dmLogout({
    required String username,
    required String ip,
  }) async {
    try {
      final result = await client.dmLogout(username: username, ip: ip);
      // 注销自己和踢别人共用这个端点，日志必须带目标地址才分得清是哪一次。
      await LogUtil.info(
        'DM 注销 $ip 结果: ${result.accepted ? '已受理' : result.reason ?? '被拒绝'}',
      );
      return result;
    } catch (e, stackTrace) {
      await LogUtil.error('DM 注销 $ip 异常', e, stackTrace);
      return const DmResult(accepted: false, errorMessage: '请求未完成');
    }
  }

  Future<T?> doRequest<T>(
    String uri,
    Map<String, Object>? params,
    T? target, [
    void Function(T target, dynamic json)? filler,
  ]) async {
    final stringParams = <String, String>{
      for (final entry in (params ?? const <String, Object>{}).entries)
        entry.key: entry.value.toString(),
    };
    final json = await client.requestJsonp(uri, stringParams);
    if (target == null) return null;

    if (filler != null) {
      filler(target, json);
      return target;
    }

    if (target is Map) {
      target.addAll(json.cast<String, dynamic>());
      return target;
    }

    return json as T?;
  }
}
