import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';

/// Android 原生层与 Dart 之间的跨语言契约。
///
/// 这些约束没有其他机制能守住：通道名、命令名和 wire 键在两侧各写一份，
/// `flutter analyze` 与 Kotlin 编译都发现不了漂移；服务是否被提升为 started
/// 状态则决定 Activity 销毁后后台认证能否继续，而这在纯 Dart 测试里观察不到。
/// 因此这里直接对两侧源码断言契约本身。
void main() {
  final mainActivity = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/MainActivity.kt',
  );
  final service = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeService.kt',
  );
  final bridge = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeBridge.kt',
  );
  final notification = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeNotification.kt',
  );
  final settings = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/BackgroundRuntimeSettings.kt',
  );
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final state = _read('lib/utils/AuthRuntimeState.dart');
  final entrypoint = _read('lib/authRuntimeMain.dart');

  group('通道与命令名跨语言一致', () {
    test('Dart 侧声明的通道名在 Kotlin 侧逐字出现', () {
      expect(
        mainActivity,
        contains(AuthRuntimeClient.uiChannelName),
        reason: 'MainActivity 必须使用 AuthRuntimeClient.uiChannelName',
      );
      expect(
        bridge,
        contains(MethodChannelAuthRuntimeHost.hostChannelName),
        reason: 'AuthRuntimeBridge 必须使用宿主通道名',
      );
    });

    test('Kotlin 常量与 Dart 命令常量取值一致', () {
      expect(
        bridge,
        contains(
          'const val COMMAND_START = "${AuthRuntimeController.commandStart}"',
        ),
      );
      expect(
        bridge,
        contains(
          'const val COMMAND_STOP = "${AuthRuntimeController.commandStop}"',
        ),
      );
    });

    test('每个声明的命令都被运行时接受', () {
      for (final command in AuthRuntimeController.declaredCommands) {
        expect(
          _methodBody(entrypoint, 'Future<void> _dispatch('),
          isNot(contains(command)),
          reason: '入口只按位置解析命令名，不应硬编码 $command',
        );
        expect(
          _methodBody(state, 'Map<String, Object?> toMap()'),
          isNot(contains(command)),
        );
      }
      expect(AuthRuntimeController.declaredCommands, hasLength(6));
    });

    test('wire 键在两侧拼写一致', () {
      _expectKeys(bridge, const [
        'ready',
        'state',
        'commandResult',
        'commandHandle',
        'id',
        'value',
      ]);
      _expectKeys(mainActivity, const [
        'attach',
        'detach',
        'command',
        'name',
        'args',
      ]);
      _expectKeys(notification, const ['notification', 'title', 'text']);
      _expectKeys(state, const [
        'status',
        'isOnline',
        'retryAfterSeconds',
        'message',
        'acid',
        'userInfo',
      ]);
      _expectKeys(entrypoint, const ['id']);
    });
  });

  group('Manifest 声明后台前台服务', () {
    test('声明 specialUse 类型、对应权限和可审查 subtype', () {
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE'),
      );
      expect(manifest, contains('android:foregroundServiceType="specialUse"'));
      expect(
        manifest,
        contains('android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE'),
      );
    });

    test('服务不可导出', () {
      expect(
        RegExp(
          r'<service[^>]*android:name="\.AuthRuntimeService"[^>]*android:exported="false"',
        ).hasMatch(manifest),
        isTrue,
        reason: 'AuthRuntimeService 必须声明为非导出',
      );
    });

    test('不声明也不伪装为 dataSync', () {
      // Manifest 注释里可以解释为什么不用 dataSync，但声明中不得出现它。
      final declarations = manifest.replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );
      expect(declarations, isNot(contains('dataSync')));
      expect(declarations, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    });

    test('屏幕常亮保活依赖已移除', () {
      expect(manifest, isNot(contains('android.permission.WAKE_LOCK')));
      expect(_read('pubspec.yaml'), isNot(contains('wakelock_plus')));
    });
  });

  group('服务生命周期', () {
    test('开启后台运行时必须把服务提升为 started 状态', () {
      // 仅绑定的服务在 Activity 解绑后会被系统销毁，后台认证无法继续。
      expect(
        _methodBody(mainActivity, 'private fun startAuthRuntime()'),
        contains('AuthRuntimeService.start(this)'),
        reason: 'startAuthRuntime 必须调用 startForegroundService 提升服务状态',
      );
      expect(
        mainActivity,
        isNot(contains('startForegroundRuntime')),
        reason: '经 binder 转发无法让服务在解绑后存活',
      );
    });

    test('进入前台发生在 onCreate 与 onStartCommand 两条路径上', () {
      expect(
        _methodBody(service, 'override fun onCreate()'),
        contains('enterForeground()'),
      );
      expect(
        _methodBody(service, 'override fun onStartCommand('),
        contains('enterForeground()'),
      );
    });

    test('保留后台运行时开启时返回 START_STICKY', () {
      expect(
        _methodBody(service, 'override fun onStartCommand('),
        contains('START_STICKY'),
      );
    });

    test('未开启保留后台运行时时不常驻', () {
      final onStartCommand = _methodBody(
        service,
        'override fun onStartCommand(',
      );
      expect(onStartCommand, contains('isKeepAliveEnabled'));
      expect(onStartCommand, contains('stopSelf()'));
      expect(onStartCommand, contains('START_NOT_STICKY'));
    });

    test('关闭后台运行释放运行时资源并停止前台', () {
      final stopRuntime = _methodBody(service, 'fun stopRuntime()');
      expect(stopRuntime, contains('COMMAND_STOP'));
      expect(stopRuntime, contains('stopForeground'));
      expect(stopRuntime, contains('stopSelf()'));

      final onDestroy = _methodBody(service, 'override fun onDestroy()');
      expect(onDestroy, contains('detachEngine()'));
      expect(onDestroy, contains('engine?.destroy()'));
    });

    test('显式注册插件，Keystore 秘密存储才能在后台 engine 中使用', () {
      expect(service, contains('GeneratedPluginRegistrant.registerWith('));
    });

    test('通过 callback dispatcher 下发命令', () {
      expect(bridge, contains('executeDartCallback'));
      expect(bridge, contains('DartExecutor.DartCallback'));
      expect(
        service,
        contains('linkupAuthRuntimeDispatcher'),
        reason: 'DartEntrypoint 必须指向保留的后台认证入口',
      );
      expect(entrypoint, contains("@pragma('vm:entry-point')"));
    });

    test('命令在回调句柄就绪前排队而不是丢弃', () {
      expect(
        _methodBody(bridge, 'private fun send('),
        contains('queuedCommands.add(command)'),
      );
      expect(
        _methodBody(bridge, 'private fun handleRuntimeCall('),
        contains('flushQueuedCommands()'),
      );
    });

    test('Activity 只绑定一个运行时并在销毁时解绑', () {
      final onStart = _methodBody(mainActivity, 'override fun onStart()');
      expect(onStart, contains('bindService('));
      expect(onStart, contains('BIND_AUTO_CREATE'));
      expect(
        _methodBody(mainActivity, 'override fun onStop()'),
        contains('unbindService(connection)'),
      );
      expect(
        mainActivity,
        isNot(contains('AuthenticationCoordinator')),
        reason: 'Activity 的 FlutterEngine 不得创建协调器',
      );
    });

    test('保留后台运行时默认值在两侧一致', () {
      expect(settings, contains('KEY_KEEP_ALIVE, true'));
      expect(
        _methodBody(service, 'private fun ensureMonitoring()'),
        contains('isKeepAliveEnabled'),
      );
    });
  });

  group('常驻通知', () {
    test('低重要性渠道且持续可见', () {
      expect(notification, contains('NotificationManager.IMPORTANCE_LOW'));
      expect(notification, contains('setOngoing(true)'));
      expect(notification, contains('NotificationCompat.PRIORITY_LOW'));
    });

    test('只渲染 Dart 派生的通知文本，不读取用户信息', () {
      final build = _methodBody(notification, 'fun build(');
      for (final forbidden in const [
        'userInfo',
        'acid',
        'message',
        'password',
        'challenge',
        'userName',
      ]) {
        expect(build, isNot(contains(forbidden)), reason: '通知不得读取 $forbidden');
      }
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

void _expectKeys(String source, List<String> keys) {
  for (final key in keys) {
    // Kotlin 用双引号、Dart 用单引号，两侧拼写必须一致。
    expect(
      source.contains("'$key'") || source.contains('"$key"'),
      isTrue,
      reason: '缺少 wire 键 $key',
    );
  }
}

/// 截取从 `signature` 所在行起、到下一个同缩进声明为止的方法体。
///
/// 只用于结构断言，不解析 Kotlin；签名或缩进变化时测试会失败而不是静默通过。
String _methodBody(String source, String signature) {
  final lines = source.split('\n');
  final index = lines.indexWhere((line) => line.contains(signature));
  if (index < 0) fail('在源码中找不到 $signature');

  final indent = lines[index].length - lines[index].trimLeft().length;
  final body = <String>[lines[index]];
  for (final line in lines.skip(index + 1)) {
    if (line.trim().isEmpty) {
      body.add(line);
      continue;
    }
    if (line.length - line.trimLeft().length <= indent) break;
    body.add(line);
  }
  return body.join('\n');
}
