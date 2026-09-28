import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:LinkUp/utils/LogUtil.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;
  final bool isForceUpdate;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    this.isForceUpdate = false,
  });
}

enum UpdatePlatform { android, windows, ios, other }

class UpdateUtil {
  static const String owner = 'mel0nyrame';
  static const String repo = 'LinkUp';

  static final Dio _dio = Dio();

  static UpdatePlatform get _platform {
    if (Platform.isWindows) return UpdatePlatform.windows;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isIOS) return UpdatePlatform.ios;
    return UpdatePlatform.other;
  }

  /// 从 tag 中提取语义化版本号，支持多种格式：
  ///   release-v1.0.3 → 1.0.3
  ///   v1.0.3        → 1.0.3
  ///   1.0.3         → 1.0.3
  static String? _extractVersion(String tag) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tag);
    return match?.group(1);
  }

  @visibleForTesting
  static String downloadFileName({
    required String version,
    required UpdatePlatform platform,
  }) {
    return switch (platform) {
      UpdatePlatform.android => 'app_update.apk',
      UpdatePlatform.windows => 'LinkUp-Setup-$version.exe',
      _ => throw ArgumentError.value(platform, 'platform'),
    };
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
        await LogUtil.warning('检查更新: 仓库不存在或为私有仓库');
        return null;
      }

      if (response.statusCode == 403) {
        await LogUtil.warning('检查更新: API 限流或被禁止');
        return null;
      }

      if (response.statusCode != 200) {
        await LogUtil.warning('检查更新失败: HTTP ${response.statusCode}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        await LogUtil.warning('检查更新: Release 响应格式无效');
        return null;
      }

      final tag = decoded['tag_name'] as String?;
      if (tag == null) {
        await LogUtil.warning('检查更新: Release 中没有 tag_name');
        return null;
      }

      final latestVersion = _extractVersion(tag);
      if (latestVersion == null) {
        await LogUtil.warning('检查更新: 无法从 Release tag 提取版本号');
        return null;
      }

      final updateInfo = updateInfoForRelease(
        currentVersion: currentVersion,
        release: decoded,
        platform: _platform,
      );
      if (updateInfo == null && _shouldUpdate(currentVersion, latestVersion)) {
        await LogUtil.warning('检查更新: Release 中没有当前平台的安装包');
      }
      return updateInfo;
    } catch (error, stackTrace) {
      await LogUtil.error('检查更新异常', error, stackTrace);
      return null;
    }
  }

  @visibleForTesting
  static UpdateInfo? updateInfoForRelease({
    required String currentVersion,
    required Map<String, dynamic> release,
    required UpdatePlatform platform,
  }) {
    final tag = release['tag_name'] as String?;
    if (tag == null) return null;

    final latestVersion = _extractVersion(tag);
    if (latestVersion == null ||
        !_shouldUpdate(currentVersion, latestVersion)) {
      return null;
    }

    final downloadUrl = _downloadUrlForRelease(
      release: release,
      tag: tag,
      version: latestVersion,
      platform: platform,
    );
    if (downloadUrl == null) return null;

    return UpdateInfo(
      version: latestVersion,
      downloadUrl: downloadUrl,
      changelog: (release['body'] as String?) ?? '暂无更新说明',
    );
  }

  static String? _downloadUrlForRelease({
    required Map<String, dynamic> release,
    required String tag,
    required String version,
    required UpdatePlatform platform,
  }) {
    final assets = release['assets'];

    String? assetUrl(String name) {
      if (assets is! List) return null;
      for (final asset in assets) {
        if (asset is Map && asset['name'] == name) {
          return asset['browser_download_url'] as String?;
        }
      }
      return null;
    }

    switch (platform) {
      case UpdatePlatform.android:
        final linkupApk = assetUrl('linkup.apk');
        if (linkupApk != null) return linkupApk;
        if (assets is List) {
          for (final asset in assets) {
            if (asset is Map &&
                (asset['name'] as String?)?.toLowerCase().endsWith('.apk') ==
                    true) {
              final url = asset['browser_download_url'] as String?;
              if (url != null) return url;
            }
          }
        }
        return 'https://github.com/$owner/$repo/releases/download/$tag/linkup.apk';
      case UpdatePlatform.windows:
        return assetUrl('LinkUp-Setup-$version.exe');
      case UpdatePlatform.ios:
        return release['html_url'] as String?;
      case UpdatePlatform.other:
        return null;
    }
  }

  /// 语义化版本比较，current < latest 返回 true
  /// 容忍非数字组件（pre-release 后缀、4 段版本号）：用 int.tryParse 缺位补 0
  /// 不需要 try/catch（int.tryParse 返回 null 而非抛异常）
  static bool _shouldUpdate(String current, String latest) {
    final cp = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final lp = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    // 取最大段数，缺位以 0 补齐，避免 1.0 vs 1.0.1 误判
    final maxLen = cp.length > lp.length ? cp.length : lp.length;
    for (int i = 0; i < maxLen; i++) {
      final c = i < cp.length ? cp[i] : 0;
      final l = i < lp.length ? lp[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// 下载并启动更新包。Windows 安装器保持交互模式，由安装程序处理升级。
  static Future<bool> downloadAndInstall(
    UpdateInfo updateInfo,
    Function(double) onProgress,
  ) async {
    if (Platform.isWindows) {
      return _downloadAndStartWindowsInstaller(updateInfo, onProgress);
    }

    if (!Platform.isAndroid) {
      try {
        return await launchUrl(Uri.parse(updateInfo.downloadUrl));
      } catch (error, stackTrace) {
        await LogUtil.error('打开更新下载页面失败', error, stackTrace);
        return false;
      }
    }

    try {
      final dir = await getTemporaryDirectory();
      final savePath =
          '${dir.path}/${downloadFileName(version: updateInfo.version, platform: UpdatePlatform.android)}';

      await _dio.download(
        updateInfo.downloadUrl,
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
    } catch (error, stackTrace) {
      await LogUtil.error('下载失败', error, stackTrace);
      return false;
    }
  }

  static Future<bool> _downloadAndStartWindowsInstaller(
    UpdateInfo updateInfo,
    Function(double) onProgress,
  ) async {
    final client = HttpClient();
    try {
      final dir = await getTemporaryDirectory();
      final installer = File(
        '${dir.path}/${downloadFileName(version: updateInfo.version, platform: UpdatePlatform.windows)}',
      );
      final request = await client.getUrl(Uri.parse(updateInfo.downloadUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Windows 安装包下载失败：HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final output = installer.openWrite();
      try {
        await for (final chunk in response) {
          output.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
        await output.flush();
      } finally {
        await output.close();
      }

      if (total >= 0 && received != total) {
        throw HttpException('Windows 安装包下载不完整');
      }

      await Process.start(
        installer.path,
        const [],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (error, stackTrace) {
      await LogUtil.error('Windows 更新下载或启动安装程序失败', error, stackTrace);
      return false;
    } finally {
      client.close(force: true);
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
