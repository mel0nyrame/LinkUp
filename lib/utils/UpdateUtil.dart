import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;
  final bool isForceUpdate;
  final int? buildNumber;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    this.isForceUpdate = false,
    this.buildNumber,
  });
}

class UpdateUtil {
  static const String owner = 'mel0nyrame';
  static const String repo = 'LinkUp';

  static final Dio _dio = Dio();

  /// 从 tag 中提取语义化版本号，支持多种格式：
  ///   release-v1.0.3 → 1.0.3
  ///   v1.0.3        → 1.0.3
  ///   1.0.3         → 1.0.3
  static String? _extractVersion(String tag) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tag);
    return match?.group(1);
  }

  /// 检查更新 — 通过 GitHub API 查询最新 Release
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 请求 GitHub Release API
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          // 私有仓库需要 Personal Access Token
          // 'Authorization': 'token YOUR_GITHUB_TOKEN',
        },
      );

      if (response.statusCode == 404) {
        print('检查更新: 仓库不存在或为私有仓库');
        return null;
      }

      if (response.statusCode == 403) {
        print('检查更新: API 限流或被禁止');
        return null;
      }

      if (response.statusCode != 200) {
        print('检查更新失败: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final tag = data['tag_name'] as String?;
      if (tag == null) {
        print('检查更新: Release 中没有 tag_name');
        return null;
      }

      final latestVersion = _extractVersion(tag);
      if (latestVersion == null) {
        print('检查更新: 无法从 tag "$tag" 提取版本号');
        return null;
      }

      // 查找 APK 下载地址
      String? downloadUrl;
      if (Platform.isAndroid) {
        // 优先从 assets 中找 .apk 文件
        final assets = data['assets'] as List?;
        if (assets != null && assets.isNotEmpty) {
          final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
                (a) => (a['name'] as String?)?.endsWith('.apk') == true,
                orElse: () => <String, dynamic>{},
              );
          downloadUrl = apkAsset['browser_download_url'] as String?;
        }
        // 回退：按已知命名规则构造下载链接
        downloadUrl ??=
            'https://github.com/$owner/$repo/releases/download/$tag/app-release.apk';
      } else if (Platform.isIOS) {
        downloadUrl = data['html_url'] as String?;
      }

      if (downloadUrl == null) {
        print('检查更新: 未找到下载地址');
        return null;
      }

      if (_shouldUpdate(currentVersion, latestVersion)) {
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          changelog: (data['body'] as String?) ?? '暂无更新说明',
        );
      }

      return null; // 已是最新版本
    } catch (e) {
      print('检查更新异常: $e');
      return null;
    }
  }

  /// 语义化版本比较，current < latest 返回 true
  static bool _shouldUpdate(String current, String latest) {
    try {
      final cp = current.split('.').map(int.parse).toList();
      final lp = latest.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final c = i < cp.length ? cp[i] : 0;
        final l = i < lp.length ? lp[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      // 版本号解析失败，保守处理：不提示更新
      return false;
    }
  }

  /// 下载并安装 APK（仅 Android）
  static Future<bool> downloadAndInstall(
      String url, Function(double) onProgress) async {
    if (!Platform.isAndroid) {
      await launchUrl(Uri.parse(url));
      return true;
    }

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/app_update.apk';

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) onProgress(received / total);
        },
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      final result = await OpenFilex.open(savePath);
      return result.type == ResultType.done;
    } catch (e) {
      print('下载失败: $e');
      return false;
    }
  }

  /// 跳转到浏览器下载
  static Future<void> openReleasePage() async {
    final url = 'https://github.com/$owner/$repo/releases/latest';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
