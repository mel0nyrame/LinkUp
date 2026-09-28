import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/WindowsAutoStart.dart';

void main() {
  test('Windows 登录自启桥接、后台窗口和安装交付保持一致', () {
    final nativeMain = File('windows/runner/main.cpp').readAsStringSync();
    final nativeWindow = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();
    final installer = File('windows/installer/LinkUp.iss').readAsStringSync();
    final ci = File('.github/workflows/ci.yml').readAsStringSync();

    expect(nativeWindow, contains(WindowsAutoStartClient.channelName));
    expect(
      nativeWindow,
      contains('"${WindowsAutoStartClient.methodGetEnabled}"'),
    );
    expect(
      nativeWindow,
      contains('"${WindowsAutoStartClient.methodSetEnabled}"'),
    );
    expect(
      nativeWindow,
      contains('Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run'),
    );
    expect(nativeWindow, contains('RegSetValueExW'));
    expect(nativeWindow, contains('RegDeleteValueW'));
    expect(nativeMain, contains('"--background"'));
    expect(nativeMain, contains('FlutterWindow window(project, start_hidden)'));
    expect(nativeWindow, contains('if (!start_hidden_) this->Show();'));

    expect(installer, contains('AppId=LinkUp.mel0nyrame'));
    expect(installer, contains('ArchitecturesAllowed=x64'));
    expect(
      installer,
      contains('DefaultDirName={localappdata}\\Programs\\{#AppName}'),
    );
    expect(
      installer,
      contains('Flags: ignoreversion recursesubdirs createallsubdirs'),
    );
    expect(installer, contains('[UninstallRun]'));
    expect(installer, contains('RemoveLinkUpAutoStart'));

    expect(ci, contains('flutter build windows --release'));
    expect(ci, contains('connectivity_plus_plugin.dll'));
    expect(ci, contains('flutter_secure_storage_windows_plugin.dll'));
    expect(ci, contains('url_launcher_windows_plugin.dll'));
    expect(ci, contains(r'--define=AppVersion=$version'));
    expect(ci, contains('Verify installer install, upgrade, and uninstall'));
    expect(ci, contains('actions/upload-artifact@v7'));
    expect(ci, contains('name: linkup-windows-installer'));
    expect(ci, contains('if-no-files-found: error'));
  });
}
