import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/AuthParameters.dart';
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 登录错误类型枚举
enum LoginErrorType {
  success, // 登录成功
  networkError, // 网络错误
  httpError, // HTTP 错误
  parseError, // 解析错误
  authFailed, // 认证失败（账号密码错误）
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
  final String? detailedMessage; // 详细错误说明
  final LoginErrorType errorType;
  final Map<String, dynamic>? rawData; // 原始响应数据
  final String? res; // 服务器返回的 res 字段

  LoginResult({
    required this.success,
    required this.message,
    this.detailedMessage,
    this.errorType = LoginErrorType.unknown,
    this.rawData,
    this.res,
  });

  /// 获取用户友好的错误提示
  String get userFriendlyMessage {
    if (success) return '登录成功';

    StringBuffer sb = StringBuffer();
    sb.writeln(message);

    if (detailedMessage != null && detailedMessage!.isNotEmpty) {
      sb.writeln('\n详细说明: $detailedMessage');
    }

    // 根据错误类型给出建议
    switch (errorType) {
      case LoginErrorType.authFailed:
        sb.writeln('\n💡 建议: 请检查账号和密码是否正确');
        break;
      case LoginErrorType.alreadyOnline:
        sb.writeln('\n💡 建议: 您已经登录，可以直接使用网络');
        break;
      case LoginErrorType.acIdError:
        sb.writeln('\n💡 建议: 请尝试修改 ACID 值 (常见值: 1, 2, 5, 11, 15)');
        break;
      case LoginErrorType.ipNotAllowed:
        sb.writeln('\n💡 建议: 当前 IP 不允许登录，请检查网络连接');
        break;
      case LoginErrorType.networkError:
        sb.writeln('\n💡 建议: 请检查网络连接是否正常');
        break;
      case LoginErrorType.serverError:
        sb.writeln('\n💡 建议: 认证服务器异常，请稍后再试');
        break;
      case LoginErrorType.challengeExpired:
        sb.writeln('\n💡 建议: 认证令牌过期，请重新尝试');
        break;
      default:
        break;
    }

    return sb.toString();
  }

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
  static LoginErrorType _analyzeErrorType(
    String error,
    String errorMsg,
    String res,
  ) {
    final msgLower = errorMsg.toLowerCase();
    final resLower = res.toLowerCase();

    // 注意：alreadyOnline 检测已移至 login 成功路径 (error == 'ok' 时先判断)，
    // _analyzeErrorType 仅在失败分支被调用，已不可能进入 error == 'ok' 的分支

    // 账号密码错误 - 包含常见错误码
    if (msgLower.contains('password') ||
        msgLower.contains('账号') ||
        msgLower.contains('密码') ||
        msgLower.contains('account') ||
        msgLower.contains('username') ||
        resLower.contains('password') ||
        res.contains('E2901') || // 密码错误或账号不存在
        res.contains('E2902') || // 账号不存在或已停用
        res.contains('E2553') || // 密码错误（加密方式不对）
        res.contains('E2606')) {
      // 用户被禁用
      return LoginErrorType.authFailed;
    }

    // 账号欠费/流量用尽
    if (res.contains('E2905') || // 账号已欠费停机
        res.contains('E3001')) {
      // 流量或时长已用尽
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

  /// 获取详细错误说明
  /// 与 Go 代码中的 getFriendlyErrorMessage 对应
  static String? _getDetailedExplanation(
    LoginErrorType type,
    String errorMsg,
    String res,
  ) {
    switch (type) {
      case LoginErrorType.authFailed:
        if (res.contains('E2901')) {
          return '错误代码 E2901: 密码错误或账号不存在。请检查：\n1. 学号/工号是否输入正确\n2. 密码是否输入正确（注意大小写）\n3. 如果忘记密码，请联系网络中心重置';
        } else if (res.contains('E2902')) {
          return '错误代码 E2902: 账号不存在或已停用。请联系网络中心确认账号状态。';
        } else if (res.contains('E2905')) {
          return '错误代码 E2905: 账号已欠费停机。请前往网络中心充值。';
        } else if (res.contains('E2553')) {
          return '错误代码 E2553: 密码错误（可能是加密方式不对）。请检查密码是否正确，或联系网络中心。';
        } else if (res.contains('E2606')) {
          return '错误代码 E2606: 用户被禁用。请联系网络中心解除禁用状态。';
        } else if (res.contains('E3001')) {
          return '错误代码 E3001: 流量或时长已用尽。请前往网络中心充值或购买流量包。';
        }
        return '账号或密码验证失败。请确认输入的账号密码正确无误。';

      case LoginErrorType.alreadyOnline:
        return '该账号已经在其他设备上登录，或当前设备已在线。';

      case LoginErrorType.acIdError:
        return 'ACID（接入点 ID）配置不正确。不同的网络环境需要不同的 ACID 值：\n• 校园无线网通常使用 1 或 2\n• 有线网络可能使用 5、11 或 15\n请尝试切换不同的 ACID 值。';

      case LoginErrorType.ipNotAllowed:
        if (res.contains('E2821')) {
          return '错误代码 E2821: IP 不在线。请检查网络连接是否正常。';
        } else if (res.contains('E2833')) {
          return '错误代码 E2833: IP 已经被占用。该 IP 地址已被其他设备使用，请稍后再试。';
        }
        return '当前 IP 地址不允许认证。可能原因：\n1. 您不在校园网络范围内\n2. IP 地址获取异常\n3. 该 IP 段未开通认证服务';

      case LoginErrorType.challengeExpired:
        return '认证令牌已过期。这通常是由于网络延迟导致的，请重新尝试登录。';

      case LoginErrorType.serverError:
        if (res.contains('E2602')) {
          return '错误代码 E2602: 认证设备响应超时。可能是服务器负载过高，建议稍后再试。';
        }
        return '认证服务器暂时不可用。可能原因：\n1. 服务器维护中\n2. 服务器负载过高\n建议稍后再试，或联系网络中心咨询。';

      case LoginErrorType.networkError:
        return '无法连接到认证服务器。请检查：\n1. 是否已连接到校园网 WiFi\n2. 网络信号是否稳定\n3. 认证服务器地址是否正确';

      case LoginErrorType.parseError:
        return '服务器返回了非预期格式的数据。可能原因：\n1. 网络不稳定导致响应截断\n2. 认证服务器异常\n建议稍后重试或检查认证服务器地址是否正确';

      default:
        // 尝试从 res 中解析错误码
        if (res.isNotEmpty && res.startsWith('E')) {
          return '错误代码: $res。这是深澜认证系统的错误，建议联系学校网络中心咨询具体原因。';
        }
        return null;
    }
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
          detailedMessage: '无法解析服务器返回的数据，可能是服务器返回了非标准格式的响应。',
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
          rawData: result,
          res: res,
        );
      }

      // 检查登录结果
      // error == 'ok' 表示成功，或者 suc_msg == 'login_ok' 表示成功
      if (error == 'ok' || sucMsg == 'login_ok') {
        return LoginResult(
          success: true,
          message: '登录成功',
          errorType: LoginErrorType.success,
          rawData: result,
          res: res,
        );
      } else {
        // 登录失败，分析错误类型
        final errorType = _analyzeErrorType(error, errorMsg, res);
        final detailedMessage = _getDetailedExplanation(
          errorType,
          errorMsg,
          res,
        );

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
          detailedMessage: detailedMessage,
          errorType: errorType,
          rawData: result,
          res: res,
        );
      }
    } on FormatException catch (e) {
      LogUtil.error('登录响应格式错误', e);
      return LoginResult(
        success: false,
        message: '响应格式错误: $e',
        detailedMessage: '服务器返回的数据格式不正确，可能是网络不稳定导致的。',
        errorType: LoginErrorType.parseError,
      );
    } on http.ClientException catch (e) {
      LogUtil.error('登录网络错误', e);
      return LoginResult(
        success: false,
        message: '网络错误: $e',
        detailedMessage:
            '无法连接到认证服务器，请检查：\n1. 是否已连接到校园网 WiFi\n2. 网络信号是否稳定\n3. 认证服务器地址是否正确',
        errorType: LoginErrorType.networkError,
      );
    } catch (e, stackTrace) {
      LogUtil.error('登录异常', e, stackTrace);
      return LoginResult(
        success: false,
        message: '登录异常: $e',
        detailedMessage: '发生了未预期的错误，请尝试重新登录或重启应用。',
        errorType: LoginErrorType.unknown,
      );
    }
  }

  /// DM 注销 — 使用 /cgi-bin/rad_user_dm 端点。
  /// 签名格式 sha1(time + username + ip + 1 + time)，与登录加密链完全不同。
  Future<bool> dmLogout({required String username, required String ip}) async {
    try {
      final result = await client.dmLogout(username: username, ip: ip);
      LogUtil.info('DM 注销结果: $result');
      return result;
    } catch (e, stackTrace) {
      LogUtil.error('DM 注销异常', e, stackTrace);
      return false;
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
