import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/UpdateUtil.dart';

void main() {
  final release = <String, dynamic>{
    'tag_name': 'release-v1.12.0',
    'body': '修复与改进',
    'assets': [
      {
        'name': 'app-release.apk',
        'browser_download_url': 'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/app-release.apk',
      },
      {
        'name': 'LinkUp-Setup-1.12.0.exe',
        'browser_download_url': 'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/LinkUp-Setup-1.12.0.exe',
      },
      {
        'name': 'linkup.apk',
        'browser_download_url': 'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/linkup.apk',
      },
    ],
  };

  test('版本升级时分别选取 Android APK 与 Windows 安装包', () {
    final androidUpdate = UpdateUtil.updateInfoForRelease(
      currentVersion: '1.11.0',
      release: release,
      platform: UpdatePlatform.android,
    );
    final windowsUpdate = UpdateUtil.updateInfoForRelease(
      currentVersion: '1.11.0',
      release: release,
      platform: UpdatePlatform.windows,
    );

    expect(androidUpdate?.version, '1.12.0');
    expect(androidUpdate?.changelog, '修复与改进');
    expect(
      androidUpdate?.downloadUrl,
      'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/linkup.apk',
    );
    expect(windowsUpdate?.version, '1.12.0');
    expect(
      windowsUpdate?.downloadUrl,
      'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/LinkUp-Setup-1.12.0.exe',
    );
    expect(
      UpdateUtil.downloadFileName(
        version: windowsUpdate!.version,
        platform: UpdatePlatform.windows,
      ),
      'LinkUp-Setup-1.12.0.exe',
    );
    expect(
      UpdateUtil.downloadFileName(
        version: androidUpdate!.version,
        platform: UpdatePlatform.android,
      ),
      'app_update.apk',
    );
  });

  test('Windows 缺少匹配的安装器时不回退到 APK', () {
    final releaseWithoutInstaller = Map<String, dynamic>.from(release)
      ..['assets'] = [
        {
          'name': 'LinkUp-Setup-1.11.0.exe',
          'browser_download_url': 'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/LinkUp-Setup-1.11.0.exe',
        },
        release['assets'][0],
        release['assets'][2],
      ];

    expect(
      UpdateUtil.updateInfoForRelease(
        currentVersion: '1.11.0',
        release: releaseWithoutInstaller,
        platform: UpdatePlatform.windows,
      ),
      isNull,
    );
  });

  test('Android 缺少资产时回退到 Release 的 linkup.apk 路径', () {
    final releaseWithoutAssets = Map<String, dynamic>.from(release)
      ..['assets'] = const [];

    final update = UpdateUtil.updateInfoForRelease(
      currentVersion: '1.11.0',
      release: releaseWithoutAssets,
      platform: UpdatePlatform.android,
    );

    expect(
      update?.downloadUrl,
      'https://github.com/mel0nyrame/LinkUp/releases/download/release-v1.12.0/linkup.apk',
    );
  });

  test('当前版本不低于 Release 版本时不提示更新', () {
    expect(
      UpdateUtil.updateInfoForRelease(
        currentVersion: '1.12.0',
        release: release,
        platform: UpdatePlatform.windows,
      ),
      isNull,
    );
  });
}
