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
  // GitHub 仓库信息
  static const String owner = 'mel0nyrame'; // 修改为你的
  static const String repo = 'LinkUp'; // 修改为你的
  
  static final Dio _dio = Dio();

  /// 检查更新
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      // 调用 GitHub API
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          // 'Authorization': 'token YOUR_GITHUB_TOKEN', // 私有仓库需要
        },
      );

      if (response.statusCode != 200) {
        print('检查更新失败: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final latestVersion = data['tag_name'].toString().replaceFirst('v', '');
      final assets = data['assets'] as List;
      
      // 查找 APK 文件（Android）
      String? downloadUrl;
      if (Platform.isAndroid) {
        final apkAsset = assets.firstWhere(
          (asset) => asset['name'].toString().endsWith('.apk'),
          orElse: () => null,
        );
        downloadUrl = apkAsset?['browser_download_url'];
      } 
      // iOS 通常跳转到 App Store 或使用 TestFlight
      else if (Platform.isIOS) {
        // 如果有 ipa 或跳转链接
        downloadUrl = data['html_url']; // 跳转到 release 页面
      }

      if (downloadUrl == null) {
        print('未找到安装包');
        return null;
      }

      // 版本比较（支持 1.0.0 格式）
      if (_shouldUpdate(currentVersion, latestVersion)) {
        return UpdateInfo(
          version: latestVersion,
          downloadUrl: downloadUrl,
          changelog: data['body'] ?? '暂无更新说明',
          isForceUpdate: false, // 可以根据 tag 或 release 名判断
        );
      }

      return null; // 已是最新
    } catch (e) {
      print('检查更新错误: $e');
      return null;
    }
  }

  /// 语义化版本比较（current < latest 则返回 true）
  static bool _shouldUpdate(String current, String latest) {
    final currentParts = current.split('.').map(int.parse).toList();
    final latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;
      
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// 下载并安装 APK（仅 Android）
  static Future<bool> downloadAndInstall(String url, Function(double) onProgress) async {
    if (!Platform.isAndroid) {
      // iOS 跳转到 Safari 下载
      await launchUrl(Uri.parse(url));
      return true;
    }

    try {
      // 获取下载路径
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/app_update.apk';

      // 下载
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );

      // 安装 APK
      final result = await OpenFilex.open(savePath);
      return result.type == ResultType.done;
    } catch (e) {
      print('下载失败: $e');
      return false;
    }
  }

  /// 跳转到浏览器下载（备用方案）
  static Future<void> openReleasePage() async {
    final url = 'https://github.com/$owner/$repo/releases/latest';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}

