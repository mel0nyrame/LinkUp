import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/SrunClient.dart';
import 'package:LinkUp/utils/SrunEncrypt.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 登录错误类型枚举
enum LoginErrorType {
  success,           // 登录成功
  networkError,      // 网络错误
  httpError,         // HTTP 错误
  parseError,        // 解析错误
  authFailed,        // 认证失败（账号密码错误）
  alreadyOnline,     // 已经在线
  ipNotAllowed,      // IP 不允许
  acIdError,         // ACID 错误
  challengeExpired,  // Challenge 过期
  serverError,       // 服务器错误
  unknown,           // 未知错误
}

/// 登录结果类
class LoginResult {
  final bool success;
  final String message;
  final String? detailedMessage;  // 详细错误说明
  final LoginErrorType errorType;
  final Map<String, dynamic>? rawData;  // 原始响应数据
  final String? res;  // 服务器返回的 res 字段

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
        sb.writeln('\n💡 建议: 请尝试修改 ACID 值（常见值: 1, 2, 5, 11, 15）');
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
  static SrunClient client = SrunClient();

  /// 根据服务器返回的错误信息分析错误类型
  /// 参考 Go 代码中的错误码映射
  static LoginErrorType _analyzeErrorType(String error, String errorMsg, String res) {
    final errorLower = error.toLowerCase();
    final msgLower = errorMsg.toLowerCase();
    final resLower = res.toLowerCase();
    
    // 已经在线
    if (errorLower.contains('ok') && (resLower.contains('login_ok') || resLower.contains('already'))) {
      return LoginErrorType.alreadyOnline;
    }
    
    // 账号密码错误 - 包含常见错误码
    if (msgLower.contains('password') || 
        msgLower.contains('账号') || 
        msgLower.contains('密码') ||
        msgLower.contains('account') ||
        msgLower.contains('username') ||
        resLower.contains('password') ||
        res.contains('E2901') ||  // 密码错误或账号不存在
        res.contains('E2902') ||  // 账号不存在或已停用
        res.contains('E2553') ||  // 密码错误（加密方式不对）
        res.contains('E2606')) {  // 用户被禁用
      return LoginErrorType.authFailed;
    }
    
    // 账号欠费/流量用尽
    if (res.contains('E2905') ||  // 账号已欠费停机
        res.contains('E3001')) {  // 流量或时长已用尽
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
        res.contains('E2821') ||  // IP 不在线
        res.contains('E2833')) {  // IP 已经被占用
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
        res.contains('E2602')) {  // 认证设备响应超时
      return LoginErrorType.serverError;
    }
    
    return LoginErrorType.unknown;
  }

  /// 获取详细错误说明
  /// 与 Go 代码中的 getFriendlyErrorMessage 对应
  static String? _getDetailedExplanation(LoginErrorType type, String errorMsg, String res) {
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
        
      default:
        // 尝试从 res 中解析错误码
        if (res.isNotEmpty && res.startsWith('E')) {
          return '错误代码: $res。这是深澜认证系统的错误，建议联系学校网络中心咨询具体原因。';
        }
        return null;
    }
  }

  static Future<LoginResult> srucPortalLogin(
    String username,
    String password,
    String acid,
    String token,
    String ip,
  ) async {
    try {
      String hmd5Password = SrunEnrypt.Hmd5(password, token);

      SrunInfo infoObj = SrunInfo(
        username: username,
        password: password,
        ip: ip,
        acid: acid,
      );

      Object info = SrunEnrypt.getInfo(infoObj.toJson(), token);

      String chkStr = SrunEnrypt.Chkstr(
        token,
        username,
        hmd5Password,
        acid,
        ip,
        client.n,
        client.enc,
        info.toString(),
      );

      String chkSum = SrunEnrypt.Sha1(chkStr);

      String currentTime = DateTime.now().millisecondsSinceEpoch.toString();

      final params = {
        'action': 'login',
        'callback': client.callback,
        'username': username,
        'password': '{MD5}$hmd5Password',
        'os': 'Windows 10',
        'name': 'Windows',
        'double_stack': '0',
        'chksum': chkSum,
        'info': info,
        'ac_id': acid,
        'ip': ip,
        'n': client.n,
        'type': client.type,
        '_': currentTime,
      };

      final uri = Uri.parse(client.urlPortal).replace(
        queryParameters: params,
      );

      LogUtil.info('登录请求 URL: $uri');

      final response = await http.get(
        uri,
        headers: {'User-Agent': client.userAgent},
      );

      LogUtil.info('登录响应状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        return LoginResult(
          success: false,
          message: 'HTTP 请求失败: ${response.statusCode}',
          detailedMessage: '服务器返回了非 200 状态码，可能是认证服务器暂时不可用。',
          errorType: LoginErrorType.httpError,
        );
      }

      // 解析 JSONP 响应
      final responseBody = response.body;
      LogUtil.info('登录响应: $responseBody');

      // 从 JSONP 中提取 JSON
      final jsonResult = _extractJsonFromJsonp(responseBody, client.callback);
      if (jsonResult == null) {
        return LoginResult(
          success: false,
          message: '解析响应失败',
          detailedMessage: '无法解析服务器返回的数据，可能是服务器返回了非标准格式的响应。',
          errorType: LoginErrorType.parseError,
          rawData: {'response': responseBody},
        );
      }

      // 解析结果
      final error = jsonResult['error'] as String? ?? '';
      final errorMsg = jsonResult['error_msg'] as String? ?? '';
      final sucMsg = jsonResult['suc_msg'] as String? ?? '';
      final res = jsonResult['res'] as String? ?? '';

      LogUtil.info(
        '解析结果: error=$error, errorMsg=$errorMsg, sucMsg=$sucMsg, res=$res',
      );

      // 检查登录结果
      // error == 'ok' 表示成功，或者 suc_msg == 'login_ok' 表示成功
      if (error == 'ok' || sucMsg == 'login_ok') {
        return LoginResult(
          success: true,
          message: '登录成功',
          errorType: LoginErrorType.success,
          rawData: jsonResult,
          res: res,
        );
      } else {
        // 登录失败，分析错误类型
        final errorType = _analyzeErrorType(error, errorMsg, res);
        final detailedMessage = _getDetailedExplanation(errorType, errorMsg, res);
        
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
          rawData: jsonResult,
          res: res,
        );
      }
    } on FormatException catch (e) {
      return LoginResult(
        success: false,
        message: '响应格式错误: $e',
        detailedMessage: '服务器返回的数据格式不正确，可能是网络不稳定导致的。',
        errorType: LoginErrorType.parseError,
      );
    } on http.ClientException catch (e) {
      return LoginResult(
        success: false,
        message: '网络错误: $e',
        detailedMessage: '无法连接到认证服务器，请检查：\n1. 是否已连接到校园网 WiFi\n2. 网络信号是否稳定\n3. 认证服务器地址是否正确',
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

  /// 从 JSONP 响应中提取 JSON 数据
  static Map<String, dynamic>? _extractJsonFromJsonp(
    String jsonp,
    String callbackName,
  ) {
    try {
      final prefix = '$callbackName(';
      if (!jsonp.startsWith(prefix)) {
        LogUtil.warning('JSONP 格式错误: 不以 $prefix 开头');
        return null;
      }
      if (!jsonp.endsWith(')')) {
        LogUtil.warning('JSONP 格式错误: 不以 ) 结尾');
        return null;
      }
      final jsonStr = jsonp.substring(prefix.length, jsonp.length - 1);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      LogUtil.error('解析 JSONP 失败', e);
      return null;
    }
  }
}
