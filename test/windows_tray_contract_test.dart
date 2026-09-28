import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/WindowsTray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows 托盘通道与单实例、窗口生命周期接线一致', () {
    final nativeWindow = File('windows/runner/flutter_window.cpp')
        .readAsStringSync();
    final nativeMain = File('windows/runner/main.cpp').readAsStringSync();
    final nativeWindowHeader = File('windows/runner/win32_window.h')
        .readAsStringSync();
    final dartTray = File('lib/utils/WindowsTray.dart').readAsStringSync();
    final dartApp = File('lib/page/WindowsTrayApp.dart').readAsStringSync();
    final runtime = File('lib/utils/WindowsAuthRuntime.dart')
        .readAsStringSync();

    expect(dartApp, contains('onLogout: widget.runtime.logout'));
    expect(dartApp, contains('onKickDevice: widget.runtime.kickDevice'));
    expect(nativeWindow, contains(WindowsTrayClient.channelName));
    for (final method in <String>[
      WindowsTrayClient.methodAttach,
      WindowsTrayClient.methodSetTooltip,
      WindowsTrayClient.methodShowMain,
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
      expect(call.method, WindowsTrayClient.methodAttach);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final tray = WindowsTrayClient(channel: channel);
    final actions = <WindowsTrayAction>[];
    tray.onAction = (action) async => actions.add(action);
    await tray.attach();

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(WindowsTrayClient.methodOnAction, 'togglePopup'),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(WindowsTrayClient.methodOnAction, 'manualCheck'),
      ),
      (_) {},
    );

    expect(tray.popupVisible.value, isTrue);
    expect(actions, <WindowsTrayAction>[
      WindowsTrayAction.togglePopup,
      WindowsTrayAction.manualCheck,
    ]);
  });
}
