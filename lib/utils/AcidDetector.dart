import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:LinkUp/utils/LogUtil.dart';

/// ACID 检测器 - 自动获取深澜认证系统的 ACID
/// 参考 BitSrunLoginGo 的实现
class AcidDetector {
  // 正则表达式
  static final RegExp _jsRedirectReg = RegExp(
    r'top\.self\.location\.href=[\x27\x22](.+?)[\x27\x22]',
    caseSensitive: false,
  );
  
  static final RegExp _metaRedirectReg = RegExp(
    r'<meta[^>]*http-equiv=[\x27\x22]refresh[\x27\x22][^>]*url=(.+?)[\s\x27\x22\>]',
    caseSensitive: false,
  );

  // 锁定在 <input> 标签内，避免被 HTML 中的 JS 字面量或注释干扰；
  // name 与 value 顺序任意，仅捕获 value 的值
  static final RegExp _acidInHtmlReg = RegExp(
    r'<input[^>]*\bname=[\x27\x22]ac_id[\x27\x22][^>]*\bvalue=[\x27\x22]([^\x27\x22]+)[\x27\x22]'
    r'|'
    r'<input[^>]*\bvalue=[\x27\x22]([^\x27\x22]+)[\x27\x22][^>]*\bname=[\x27\x22]ac_id[\x27\x22]',
    caseSensitive: false,
  );

  static final RegExp _ipInHtmlReg = RegExp(
    r'ip\s*:\s*[\x27\x22](.+?)[\x27\x22]',
    caseSensitive: false,
  );

  /// 多个检测入口地址（优先级排序）
  static const List<String> _detectUrls = [
    'http://www.msftconnecttest.com/connecttest.txt',  // Windows
    'http://captive.apple.com/hotspot-detect.html',     // Apple
    'http://connectivitycheck.gstatic.com/generate_204', // Android
    'http://detectportal.firefox.com/canonical.html',    // Firefox
    'http://www.baidu.com',                              // 通用 fallback
  ];

  /// 认证服务器基础地址
  final String baseUrl;

  /// 缓存的页面内容
  String? _cachedPage;
  String? _cachedPageUrl;

  AcidDetector({required this.baseUrl});

  /// 检测 ACID - 优先使用 Reality 模式
  Future<String?> detectAcid() async {
    LogUtil.info('[AcidDetector] 开始检测 ACID...');
    LogUtil.info('[AcidDetector] 认证服务器: $baseUrl');

    // 如果已经缓存了页面内容，直接从 HTML 查找
    if (_cachedPage != null) {
      LogUtil.info('[AcidDetector] 使用缓存的页面内容');
      return _detectFromCachedHtml();
    }

    try {
      // 阶段 1：跟随重定向链，从 URL 参数中查找 ac_id
      String? acid = await _detectFromRedirect();
      if (acid != null && acid.isNotEmpty) {
        LogUtil.info('[AcidDetector] 从 URL 参数检测到 ACID: $acid');
        return acid;
      }

      // 阶段 2：从 HTML 内容中查找 ac_id
      acid = await _detectFromCachedHtml();
      if (acid != null && acid.isNotEmpty) {
        LogUtil.info('[AcidDetector] 从 HTML 表单检测到 ACID: $acid');
        return acid;
      }

      LogUtil.warning('[AcidDetector] 无法检测到 ACID');
      return null;
    } catch (e, stackTrace) {
      LogUtil.error('[AcidDetector] 检测 ACID 失败', e, stackTrace);
      return null;
    }
  }

  /// Reality 模式 - 同时检测在线状态和 ACID
  /// 多个检测 URL 并发竞速：首个无错的结果胜出，整体延迟 ≤ 单个超时（5s）
  /// 若所有都失败，返回汇总错误
  Future<(String?, bool, String?)> reality({bool getAcid = true}) async {
    LogUtil.info('[AcidDetector] Reality 模式检测（并发 ${_detectUrls.length} 个地址）...');

    // 共享 client：first-success 时关闭它会取消所有 in-flight loser 的 socket，
    // 避免 5s timeout 内 4× orphan http.Client 浪费（mobile battery / radio）
    final sharedClient = http.Client();

    // 每个 URL 包装为 Future；并发竞速，最快的成功结果胜出
    final completer = Completer<(String?, bool, String?)>();
    int remaining = _detectUrls.length;
    final errors = <String>[];

    for (final detectUrl in _detectUrls) {
      // _realityWithUrl 内部已 try/catch 把所有异常包装为返回值，永不抛出，
      // 因此这里无需 .catchError
      _realityWithUrl(detectUrl, getAcid: getAcid, sharedClient: sharedClient).then((result) {
        final (_, _, err) = result;
        if (!completer.isCompleted) {
          if (err == null) {
            LogUtil.info('[AcidDetector] Reality 成功（来自 $detectUrl）: $result');
            completer.complete(result);
            return;
          }
          errors.add('$detectUrl: $err');
        }
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          LogUtil.error('[AcidDetector] 所有检测地址都失败');
          completer.complete((null, false, errors.join('; ')));
        }
      });
    }

    final result = await completer.future;
    // 关闭共享 client：close 后任何在飞 send() 都会立即抛 ClientException，
    // 已被 _followRedirect 内部 try/catch 捕获；_followRedirect 不会重复 close
    // （ownsClient=false），不会抛 StateError
    sharedClient.close();
    return result;
  }

  /// 使用指定 URL 进行 Reality 检测
  /// host 匹配仅作为「未被 Portal 拦截」的必要条件，还需要验证响应体是预期格式，
  /// 避免同域 captive portal 返回 HTML 被误判为在线
  /// sharedClient 用于让 reality() 在 first-success 时一次性关掉所有 in-flight request
  Future<(String?, bool, String?)> _realityWithUrl(
    String url, {
    bool getAcid = true,
    http.Client? sharedClient,
  }) async {
    try {
      final startUrl = Uri.parse(url);
      String? detectedAcid;
      bool isOnline = false;

      final (res, body, err) = await _followRedirect(
        startUrl,
        sharedClient: sharedClient,
        onNextAddr: (addr) {
          // 在重定向过程中捕获 acid
          if (getAcid) {
            detectedAcid = _extractAcidFromQuery(addr);
            if (detectedAcid != null) {
              LogUtil.info('[AcidDetector] Reality: URL 中捕获 ACID=$detectedAcid');
              _cachedPageUrl = addr.toString();
            }
          }
          // 不再用 host 匹配提前判定「在线」，由响应内容统一判定
          return false;
        },
      );

      if (err != null) {
        return (null, false, err);
      }

      // 缓存页面内容
      if (body != null) {
        _cachedPage = body;
      }

      // 判断是否在线：host 必须匹配，且响应体不含 portal 特征
      if (res != null && res.request != null) {
        final finalHost = res.request!.url.host;
        final hostMatches = finalHost == startUrl.host;
        final looksLikePortal = body != null && _looksLikePortal(body);
        isOnline = hostMatches && !looksLikePortal;
        if (hostMatches && looksLikePortal) {
          LogUtil.warning('[AcidDetector] Reality: host 匹配但响应像 portal 拦截，判定为离线');
        }
      }

      return (detectedAcid, isOnline, null);
    } catch (e) {
      return (null, false, e.toString());
    }
  }

  /// 检查响应体是否疑似深澜 portal 页面
  /// captive portal 同域 200 返回 HTML 时，body 中必含这些标记
  /// 多 marker 组合判定：_acidInHtmlReg 覆盖 input 隐藏表单，'srun_portal'/'login.html'
  /// 覆盖 portal URL 特征，'"ac_id"'（带引号字面量）和 'ac_id ='（无引号赋值）覆盖
  /// SPA 注入形式（如 <script>var ac_id = "5";</script> 或 var ac_id = 5;）
  static bool _looksLikePortal(String body) {
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();
    return _acidInHtmlReg.hasMatch(body) ||
        lower.contains('srun_portal') ||
        lower.contains('login.html') ||
        lower.contains('"ac_id"') ||
        lower.contains("'ac_id'") ||
        lower.contains('ac_id =') ||
        lower.contains('ac_id:');
  }

  /// 从重定向链检测 ACID（从 baseUrl 开始）
  Future<String?> _detectFromRedirect() async {
    LogUtil.info('[AcidDetector] 阶段 1: 从认证服务器重定向链检测...');

    try {
      final startUrl = Uri.parse(baseUrl);
      String? foundAcid;

      await _followRedirect(
        startUrl,
        onNextAddr: (addr) {
          final acid = _extractAcidFromQuery(addr);
          if (acid != null) {
            LogUtil.info('[AcidDetector] URL 中找到 ACID: $acid');
            foundAcid = acid;
            _cachedPageUrl = addr.toString();
            return true;
          }
          return false;
        },
      );

      return foundAcid;
    } catch (e) {
      LogUtil.error('[AcidDetector] 重定向链检测失败', e);
      return null;
    }
  }

  /// 从缓存的 HTML 中检测 ACID
  Future<String?> _detectFromCachedHtml() async {
    // 如果已经有缓存，直接解析
    if (_cachedPage != null) {
      return _extractAcidFromHtml(_cachedPage!);
    }

    // 否则请求登录页面
    LogUtil.info('[AcidDetector] 阶段 2: 从登录页面 HTML 检测...');

    try {
      final pageUrl = _cachedPageUrl ?? '$baseUrl/srun_portal_pc.php';
      LogUtil.info('[AcidDetector] 请求: $pageUrl');

      final response = await http.get(
        Uri.parse(pageUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 5));

      LogUtil.info('[AcidDetector] 响应: ${response.statusCode}');

      if (response.statusCode == 200) {
        _cachedPage = response.body;
        return _extractAcidFromHtml(_cachedPage!);
      } else {
        LogUtil.warning('[AcidDetector] 获取页面失败: ${response.statusCode}');
        return null;
      }
    } on SocketException catch (e) {
      LogUtil.error('[AcidDetector] 连接失败，认证服务器可能不可达', e);
      return null;
    } catch (e) {
      LogUtil.error('[AcidDetector] 请求页面失败', e);
      return null;
    }
  }

  /// 跟随重定向链
  /// sharedClient 用于让调用方（如 reality()）在 first-success 时统一释放 socket；
  /// 不传则本函数自建自管 client
  Future<(http.Response?, String?, String?)> _followRedirect(
    Uri startAddr, {
    required bool Function(Uri addr) onNextAddr,
    http.Client? sharedClient,
  }) async {
    final ownsClient = sharedClient == null;
    final client = sharedClient ?? http.Client();
    final visitedUris = <String>{};
    Uri currentAddr = startAddr;
    int redirectCount = 0;
    const maxRedirects = 10;

    try {
      while (redirectCount < maxRedirects) {
        final addrStr = currentAddr.toString();
        LogUtil.info('[AcidDetector] 请求[$redirectCount]: $addrStr');

        if (visitedUris.contains(addrStr)) {
          return (null, null, '循环重定向');
        }
        visitedUris.add(addrStr);

        http.Response response;
        try {
          final request = http.Request('GET', currentAddr);
          request.followRedirects = false;
          request.headers['User-Agent'] = _userAgent;

          final streamedResponse = await client.send(request)
              .timeout(const Duration(seconds: 5));
          response = await http.Response.fromStream(streamedResponse);
        } on SocketException catch (e) {
          return (null, null, '连接失败: ${e.message}');
        }

        LogUtil.info('[AcidDetector] 状态码: ${response.statusCode}');

        if (response.statusCode < 300) {
          // 2xx - 检查 JS/Meta 跳转
          final body = response.body;
          
          // JS 跳转
          final jsMatch = _jsRedirectReg.firstMatch(body);
          if (jsMatch != null) {
            final loc = jsMatch.group(1);
            if (loc != null && loc.isNotEmpty) {
              LogUtil.info('[AcidDetector] JS 跳转: $loc');
              currentAddr = _joinRedirectLocation(currentAddr, loc);
              redirectCount++;
              if (onNextAddr(currentAddr)) return (response, body, null);
              continue;
            }
          }
          
          // Meta 跳转
          final metaMatch = _metaRedirectReg.firstMatch(body);
          if (metaMatch != null) {
            final loc = metaMatch.group(1);
            if (loc != null && loc.isNotEmpty) {
              LogUtil.info('[AcidDetector] Meta 跳转: $loc');
              currentAddr = _joinRedirectLocation(currentAddr, loc);
              redirectCount++;
              if (onNextAddr(currentAddr)) return (response, body, null);
              continue;
            }
          }

          // 没有跳转
          return (response, body, null);
          
        } else if (response.statusCode < 400) {
          // 3xx 重定向
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) {
            LogUtil.info('[AcidDetector] ${response.statusCode} 跳转: $location');
            currentAddr = _joinRedirectLocation(currentAddr, location);
            redirectCount++;
            if (onNextAddr(currentAddr)) return (response, null, null);
          } else {
            return (null, null, '缺少 Location');
          }
        } else {
          // 4xx/5xx
          return (null, null, 'HTTP ${response.statusCode}');
        }
      }

      return (null, null, '重定向过多');
    } on http.ClientException catch (e) {
      // reality() 在 first-success 时 sharedClient.close() 触发 in-flight 抛
      // ClientException；归一为 "Connection closed (client shutdown)" 便于诊断
      // 区分是网络问题还是被 reality() 主流程关掉
      return (null, null, 'Connection closed (client shutdown)');
    } catch (e) {
      return (null, null, e.toString());
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// 解析重定向 URL
  Uri _joinRedirectLocation(Uri addr, String loc) {
    loc = loc.trim();
    
    if (loc.startsWith('http://') || loc.startsWith('https://')) {
      return Uri.parse(loc);
    }
    
    // 处理转义字符
    loc = loc.replaceAll(r'\/', '/');
    
    if (loc.startsWith('/')) {
      final qIndex = loc.indexOf('?');
      if (qIndex >= 0) {
        return addr.replace(
          path: loc.substring(0, qIndex),
          query: loc.substring(qIndex + 1),
        );
      } else {
        return addr.replace(path: loc, query: '');
      }
    } else {
      final basePath = addr.path;
      final newPath = basePath.endsWith('/')
          ? '$basePath$loc'
          : '${basePath.substring(0, basePath.lastIndexOf('/') + 1)}$loc';
      return addr.replace(path: newPath, query: '');
    }
  }

  String? _extractAcidFromQuery(Uri uri) {
    final acid = uri.queryParameters['ac_id'];
    if (acid != null && acid.isNotEmpty) return acid;
    return uri.queryParameters['acid'] ?? uri.queryParameters['Acid'];
  }

  // JS 字符串字面量形式的 ac_id（覆盖 SPA 注入 portal：ac_id 不在 <input> 而是
  // 在 <script>var ac_id = "5";</script> 这种 JS 字符串里）
  static final RegExp _acidInJsReg = RegExp(
    r'ac_id\s*[:=]\s*["\x27](\d+)["\x27]',
    caseSensitive: false,
  );

  String? _extractAcidFromHtml(String html) {
    // 1. 优先从 <input> 隐藏表单提取（_acidInHtmlReg 覆盖 name=ac_id / value=...）
    final match = _acidInHtmlReg.firstMatch(html);
    if (match != null) {
      // 正则有两个分支，匹配的 group 只有一个非空
      return match.group(1) ?? match.group(2);
    }
    // 2. Fallback：从 JS 字符串字面量提取 ac_id（如 <script>var ac_id="5"</script>）
    final jsMatch = _acidInJsReg.firstMatch(html);
    if (jsMatch != null) {
      return jsMatch.group(1);
    }
    return null;
  }

  void reset() {
    _cachedPage = null;
    _cachedPageUrl = null;
  }

  /// 自动检测加密版本号（参考 BitSrunLoginGo DetectEnc）
  /// 从登录页 HTML 中找到 portal JS 文件，提取 var enc = ...
  Future<String?> detectEnc() async {
    LogUtil.info('[AcidDetector] 开始检测 enc 版本...');

    try {
      // 确保有登录页内容缓存
      if (_cachedPage == null) {
        final pageUrl = _cachedPageUrl ?? '$baseUrl/srun_portal_pc.php';
        LogUtil.info('[AcidDetector] 请求登录页: $pageUrl');
        final response = await http.get(
          Uri.parse(pageUrl),
          headers: {'User-Agent': _userAgent},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          _cachedPage = response.body;
        } else {
          LogUtil.warning('[AcidDetector] 获取登录页失败: ${response.statusCode}');
          return null;
        }
      }

      // 从 HTML 中查找 portal JS 文件路径
      final jsReg = RegExp(
        r'<script src="\.?(.+[./]portal[0-9]*\.js)(\?.*)?">',
        caseSensitive: false,
      );
      final jsMatch = jsReg.firstMatch(_cachedPage!);
      if (jsMatch == null) {
        LogUtil.warning('[AcidDetector] 未找到 portal JS 文件');
        return null;
      }

      final jsPath = jsMatch.group(1)!;
      final jsUrl = Uri.parse(baseUrl).replace(path: jsPath);
      LogUtil.info('[AcidDetector] 请求 JS 文件: $jsUrl');

      final jsResponse = await http.get(
        jsUrl,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 5));

      if (jsResponse.statusCode != 200) {
        LogUtil.warning('[AcidDetector] 获取 JS 文件失败: ${jsResponse.statusCode}');
        return null;
      }

      // 从 JS 内容中提取 var enc = ...
      final encReg = RegExp(r'var enc = (.*?)[,;]');
      final encMatch = encReg.firstMatch(jsResponse.body);
      if (encMatch == null) {
        LogUtil.warning('[AcidDetector] JS 中未找到 enc 定义');
        return null;
      }

      final encStr = encMatch.group(1)!;
      // 处理字符串拼接: "srun" + "_" + "bx1" → "srun_bx1"
      final parts = encStr.split('+');
      final enc = parts
          .map((p) => p.trim().replaceAll(RegExp(r"""^['"]|['"]$"""), ''))
          .join();
      LogUtil.info('[AcidDetector] 检测到 enc: $enc');
      return enc;
    } catch (e, stackTrace) {
      LogUtil.error('[AcidDetector] 检测 enc 失败', e, stackTrace);
      return null;
    }
  }

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
}
