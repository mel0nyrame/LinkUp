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

  static final RegExp _acidInHtmlReg = RegExp(
    r'[\x27\x22]ac_id[\x27\x22].*?value=[\x27\x22](.+?)[\x27\x22]',
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
  Future<(String?, bool, String?)> reality({bool getAcid = true}) async {
    LogUtil.info('[AcidDetector] Reality 模式检测...');

    // 尝试多个检测地址
    for (final detectUrl in _detectUrls) {
      LogUtil.info('[AcidDetector] 尝试检测地址: $detectUrl');
      
      try {
        final result = await _realityWithUrl(detectUrl, getAcid: getAcid);
        final (acid, isOnline, err) = result;
        
        if (err == null) {
          LogUtil.info('[AcidDetector] Reality 成功: 在线=$isOnline, ACID=$acid');
          return result;
        } else {
          LogUtil.warning('[AcidDetector] 检测地址 $detectUrl 失败: $err');
        }
      } catch (e) {
        LogUtil.warning('[AcidDetector] 检测地址 $detectUrl 异常: $e');
      }
    }

    LogUtil.error('[AcidDetector] 所有检测地址都失败');
    return (null, false, '所有检测地址都失败');
  }

  /// 使用指定 URL 进行 Reality 检测
  Future<(String?, bool, String?)> _realityWithUrl(String url, {bool getAcid = true}) async {
    try {
      final startUrl = Uri.parse(url);
      String? detectedAcid;
      bool isOnline = false;

      final (res, body, err) = await _followRedirect(
        startUrl,
        onNextAddr: (addr) {
          // 如果回到原地址，说明已在线
          if (addr.host == startUrl.host) {
            LogUtil.info('[AcidDetector] Reality: 已在线 (host 匹配)');
            isOnline = true;
            return true;
          }
          
          // 在重定向过程中捕获 acid
          if (getAcid) {
            detectedAcid = _extractAcidFromQuery(addr);
            if (detectedAcid != null) {
              LogUtil.info('[AcidDetector] Reality: URL 中捕获 ACID=$detectedAcid');
              _cachedPageUrl = addr.toString();
            }
          }
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

      // 判断是否在线
      if (res != null && res.request != null) {
        final finalHost = res.request!.url.host;
        isOnline = finalHost == startUrl.host;
      }

      return (detectedAcid, isOnline, null);
    } catch (e) {
      return (null, false, e.toString());
    }
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
  Future<(http.Response?, String?, String?)> _followRedirect(
    Uri startAddr, {
    required bool Function(Uri addr) onNextAddr,
  }) async {
    final client = http.Client();
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
    } catch (e) {
      return (null, null, e.toString());
    } finally {
      client.close();
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

  String? _extractAcidFromHtml(String html) {
    final match = _acidInHtmlReg.firstMatch(html);
    return match?.group(1);
  }

  void reset() {
    _cachedPage = null;
    _cachedPageUrl = null;
  }

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
}
