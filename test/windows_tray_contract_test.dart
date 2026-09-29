import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/page/WindowsPopupApp.dart';
import 'package:LinkUp/utils/WindowsTray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows 托盘通道与单实例、窗口生命周期接线一致', () {
    final nativeWindow = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();
    final nativeMain = File('windows/runner/main.cpp').readAsStringSync();
    final nativeWindowHeader = File('windows/runner/win32_window.h')
        .readAsStringSync();
    final nativePopup = File('windows/runner/tray_popup_window.cpp')
        .readAsStringSync();
    final nativeBuild = File('windows/runner/CMakeLists.txt')
        .readAsStringSync();
    final dartEntrypoints = File('lib/main.dart').readAsStringSync();
    final popupApp = File('lib/page/WindowsPopupApp.dart').readAsStringSync();
    final dartTray = File('lib/utils/WindowsTray.dart').readAsStringSync();
    final dartApp = File('lib/page/WindowsTrayApp.dart').readAsStringSync();
    final windowsLogs = File('lib/page/WindowsLogsPage.dart')
        .readAsStringSync();
    final windowsHome = File('lib/page/WindowsHome.dart').readAsStringSync();
    final runtime = File('lib/utils/WindowsAuthRuntime.dart')
        .readAsStringSync();

    expect(dartApp, contains('onLogout: widget.runtime.logout'));
    expect(dartApp, contains('onKickDevice: widget.runtime.kickDevice'));
    expect(nativeWindow, contains(WindowsTrayClient.channelName));
    for (final method in <String>[
      WindowsTrayClient.methodAttach,
      WindowsTrayClient.methodSetTooltip,
      WindowsTrayClient.methodSetPopupState,
      WindowsTrayClient.methodExitComplete,
      WindowsTrayClient.methodOnAction,
    ]) {
      expect(nativeWindow, contains('"$method"'));
    }
    for (final action in WindowsTrayAction.values) {
      expect(nativeWindow, contains('"${action.name}"'));
      expect(dartTray, contains(action.name));
    }
    for (final label in <String>[
      '打开 LinkUp',
      '立即检查',
      '设置',
      '查看日志',
      '退出 LinkUp',
    ]) {
      expect(nativeWindow, contains('L"$label"'));
    }
    expect(nativeWindow, contains('Shell_NotifyIconW(NIM_ADD'));
    expect(nativeWindow, contains('std::make_unique<TrayPopupWindow>'));
    expect(nativeWindow, contains('popup_window_->ShowAt(PopupBounds())'));
    expect(nativeWindow, isNot(contains('SetPopupWindowMode')));
    expect(nativePopup, contains('project_.set_dart_entrypoint("popupMain")'));
    expect(nativeBuild, contains('"tray_popup_window.cpp"'));
    expect(
      dartEntrypoints,
      contains("@pragma('vm:entry-point')\nvoid popupMain()"),
    );
    expect(dartEntrypoints, contains('runApp(const WindowsPopupApp());'));
    expect(popupApp, isNot(contains('WindowsAuthRuntime')));
    expect(nativePopup, contains(WindowsPopupApp.channelName));
    for (final method in <String>[
      WindowsPopupApp.methodGetState,
      WindowsPopupApp.methodReady,
      WindowsPopupApp.methodUpdateState,
      WindowsPopupApp.methodManualCheck,
      WindowsPopupApp.methodOpenDetails,
      WindowsPopupApp.methodHidePopup,
    ]) {
      expect(nativePopup, contains('"$method"'));
    }
    expect(nativePopup, contains('WS_EX_TOOLWINDOW'));
    expect(nativePopup, contains('WM_ACTIVATE'));
    expect(nativePopup, contains('GetNativeWindow()'));
    expect(nativePopup, isNot(contains('AuthenticationCoordinator')));
    expect(dartApp, contains('WindowsPopupState.fromRuntime'));
    expect(dartApp, isNot(contains('compact:')));
    expect(
      nativeWindow,
      contains('ShowMainWindow();\n      DispatchTrayAction("openLogs");'),
    );
    expect(dartApp, contains('case WindowsTrayAction.openLogs:'));
    expect(dartApp, contains('_selectedDestination = 2'));
    expect(windowsHome, contains('const WindowsLogsPage()'));
    expect(windowsLogs, isNot(contains('WindowsAuthRuntime')));
    expect(windowsLogs, isNot(contains('AuthenticationCoordinator')));
    expect(nativeWindow, contains('Shell_NotifyIconW(NIM_DELETE'));
    expect(nativeWindow, contains('Shell_NotifyIconGetRect'));
    expect(nativeWindow, contains('MonitorFromRect'));
    expect(nativeWindow, contains('GetMonitorInfoW'));
    expect(nativeWindow, contains('FlutterDesktopGetDpiForMonitor'));
    expect(nativeWindow, contains('std::clamp<LONG>'));
    expect(nativeWindow, contains('NOTIFYICON_VERSION_4'));
    expect(nativeWindow, contains('L"TaskbarCreated"'));
    expect(nativeWindow, contains('关闭窗口后，LinkUp 会继续在系统托盘运行'));
    expect(nativeWindow, contains('HideToTray();'));
    expect(nativeWindow, contains('DispatchTrayAction("openMain")'));
    expect(nativeWindow, contains('DispatchTrayAction("exitRequested")'));
    expect(nativeMain, contains('CreateMutexW'));
    expect(nativeMain, contains('ERROR_ALREADY_EXISTS'));
    expect(nativeMain, contains('kLinkUpActivateExistingMessage'));
    expect(nativeWindowHeader, contains('kLinkUpActivateExistingMessage'));
    expect(
      nativeWindow,
      contains(
        'if (message == kLinkUpActivateExistingMessage) {\n'
        '    ShowMainWindow();\n'
        '    DispatchTrayAction("openMain");',
      ),
    );
    expect(dartApp, contains('widget.runtime.dispose()'));
    expect(runtime, contains('await _coordinator.dispose();'));
  });

  test('托盘原生命令更新浮层状态并转发操作', () async {
    const channel = MethodChannel('testWindowsTray');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(
        call.method,
        anyOf(
          WindowsTrayClient.methodAttach,
          WindowsTrayClient.methodSetPopupState,
        ),
      );
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final tray = WindowsTrayClient(channel: channel);
    final actions = <WindowsTrayAction>[];
    tray.onAction = (action) async => actions.add(action);
    await tray.attach();

    await tray.setPopupState(<String, Object?>{'title': '未配置'});
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(WindowsTrayClient.methodOnAction, 'manualCheck'),
      ),
      (_) {},
    );

    expect(actions, <WindowsTrayAction>[WindowsTrayAction.manualCheck]);
  });
}
