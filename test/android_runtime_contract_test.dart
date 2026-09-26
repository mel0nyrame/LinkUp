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
  final mainDart = _read('lib/main.dart');
  final monitor = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeNetworkMonitor.kt',
  );
  final boot = _read(
    'android/app/src/main/kotlin/com/mel0ny/linkup/BootReceiver.kt',
  );
  final controller = _read('lib/utils/AuthRuntimeController.dart');
  final dartSettings = _read('lib/utils/SystemSettingsUtil.dart');
  final config = _read('lib/utils/ConfigUtil.dart');

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
      expect(
        bridge,
        contains(
          'const val COMMAND_NETWORK_CHANGED = '
          '"${AuthRuntimeController.commandNetworkChanged}"',
        ),
      );
    });

    test('每个声明的命令都被运行时接受', () {
      for (final command in AuthRuntimeController.declaredCommands) {
        expect(
          _methodBody(entrypoint, 'Future<Object?> _dispatch('),
          isNot(contains(command)),
          reason: '入口只按位置解析命令名，不应硬编码 $command',
        );
        expect(
          _methodBody(state, 'Map<String, Object?> toMap()'),
          isNot(contains(command)),
        );
      }
      expect(AuthRuntimeController.declaredCommands, hasLength(7));
    });

    test('wire 键在两侧拼写一致', () {
      _expectKeys(bridge, const ['ready', 'state', 'command', 'name', 'args']);
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
      _expectKeys(entrypoint, const ['command', 'name', 'args']);
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

    test('服务启动一次后台入口，随后使用 MethodChannel 下发命令', () {
      expect(
        service,
        contains('linkupAuthRuntimeDispatcher'),
        reason: 'DartEntrypoint 必须指向保留的后台认证入口',
      );
      expect(entrypoint, contains("@pragma('vm:entry-point')"));
      expect(bridge, isNot(contains('executeDartCallback(')));
      expect(bridge, contains('invokeMethod("command"'));
      expect(entrypoint, contains('setMethodCallHandler('));
    });

    test('主 Dart bundle 包含后台运行时入口库', () {
      expect(
        mainDart,
        contains("import 'package:LinkUp/authRuntimeMain.dart'"),
        reason: '后台 Engine 使用主 APK 的 Dart bundle，入口库必须可达',
      );
    });

    test('命令在处理器就绪前排队而不是丢弃', () {
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

  group('网络事件恢复认证', () {
    test('服务存活期间注册 Wi-Fi 回调，释放时注销', () {
      final ensureMonitoring = _methodBody(
        service,
        'private fun ensureMonitoring()',
      );
      expect(
        ensureMonitoring,
        contains('startNetworkMonitor()'),
        reason: '开始监控时必须注册网络回调，否则断网恢复要等下一个周期',
      );
      expect(ensureMonitoring, contains('AuthRuntimeBridge.COMMAND_START'));
      expect(
        _methodBody(service, 'private fun startNetworkMonitor()'),
        contains('AuthRuntimeNetworkMonitor(this)'),
      );
      expect(
        _methodBody(service, 'override fun onDestroy()'),
        contains('stopNetworkMonitor()'),
        reason: '销毁时必须注销回调，否则服务重启会累积监听',
      );
      expect(
        _methodBody(service, 'fun stopRuntime()'),
        contains('stopNetworkMonitor()'),
      );
      expect(
        _methodBody(service, 'private fun stopNetworkMonitor()'),
        contains('networkMonitor?.stop()'),
      );
      expect(monitor, contains('registerNetworkCallback'));
      expect(monitor, contains('unregisterNetworkCallback'));
      expect(monitor, contains('override fun onAvailable('));
      expect(monitor, contains('override fun onLost('));
    });

    test('网络回调只上报可用性，不复制认证逻辑', () {
      expect(
        monitor,
        contains('TRANSPORT_WIFI'),
        reason: '只跟踪 Wi-Fi：未认证的校园网不会成为系统默认网络',
      );
      expect(
        _methodBody(monitor, 'private fun report('),
        contains('reported == connected'),
        reason: '可用性没变就不下发，重复事件不会反复叫醒协调器',
      );
      final code = _codeOnly(monitor);
      for (final forbidden in const [
        'reality',
        'challenge',
        'password',
        'getUserInfo',
        'srun_portal',
        'rad_user_info',
      ]) {
        expect(
          code,
          isNot(contains(forbidden)),
          reason: '平台回调不得接触 $forbidden：Srun 协议只能在协调器里运行',
        );
      }
    });

    test('校园 WiFi 非默认网络时认证流量仍走 WiFi，事件在主线程下发', () {
      expect(manifest, contains('android.permission.CHANGE_NETWORK_STATE'));
      expect(monitor, contains('bindProcessToNetwork(network)'));
      expect(_methodBody(monitor, 'fun stop()'), contains('bind(null)'));
      expect(monitor, contains('Handler(Looper.getMainLooper())'));
      expect(
        _methodBody(monitor, 'override fun onAvailable('),
        contains('mainHandler.post'),
      );
      expect(
        _methodBody(monitor, 'override fun onLost('),
        contains('mainHandler.post'),
      );
    });

    test('WiFi 切换时即使仍可用也通知协调器重建 HTTP 连接', () {
      expect(
        _methodBody(monitor, 'override fun onAvailable('),
        contains('selectedNetwork = network'),
      );
      expect(
        _methodBody(monitor, 'private fun report('),
        contains('reportedNetwork == selectedNetwork'),
      );
      expect(
        _methodBody(monitor, 'override fun onLost('),
        contains('selectedNetwork = networks.firstOrNull()'),
      );
    });

    test('网络事件负载键在两侧拼写一致', () {
      expect(
        _methodBody(service, 'private fun startNetworkMonitor()'),
        contains('AuthRuntimeBridge.COMMAND_NETWORK_CHANGED'),
      );
      _expectKeys(service, const ['connected']);
      _expectKeys(controller, const ['connected']);
      expect(
        _methodBody(controller, 'case commandNetworkChanged:'),
        contains("args?['connected'] == true"),
        reason: '原生只发命令，可用性判断必须由协调器做',
      );
    });
  });

  group('开机自启', () {
    test('配置存在且两个开关同时开启才启动服务', () {
      final onReceive = _methodBody(boot, 'override fun onReceive(');
      expect(onReceive, contains('isAccountConfigured'));
      expect(onReceive, contains('isKeepAliveEnabled'));
      expect(onReceive, contains('isAutoStartEnabled'));
      expect(onReceive, contains('AuthRuntimeService.start(context)'));
      // 三个条件缺一即返回：把 || 写成 && 会让"两个开关都开"变成"两个开关都关"才启动。
      expect(
        onReceive,
        contains('if (!keepAlive || !autoStart || !configured) return'),
        reason: '开机门必须是三条件合取的反面，任一不满足都不得启动服务',
      );
    });

    test('运行期间改设置会立刻反映到服务启停', () {
      final applyKeepAlive = _methodBody(
        dartSettings,
        'static Future<void> applyKeepAlive(',
      );
      expect(
        applyKeepAlive,
        contains('if (getKeepAlive())'),
        reason: '保留后台运行是总开关，关闭即刻停服务',
      );
      expect(applyKeepAlive, contains('startAuthRuntime'));
      expect(applyKeepAlive, contains('stopAuthRuntime'));
      expect(
        _methodBody(dartSettings, 'static Future<bool> setKeepAlive('),
        contains('applyKeepAlive()'),
        reason: '改开关必须走同一条应用路径，不能只写偏好',
      );
    });

    test('开机不拉起 Activity', () {
      final code = _codeOnly(boot);
      expect(code, isNot(contains('startActivity')));
      expect(code, isNot(contains('getLaunchIntentForPackage')));
      expect(code, isNot(contains('PendingIntent')));
    });

    test('配置存在标记由配置 owner 维护，两侧键名与默认值一致', () {
      expect(settings, contains('"flutter.account_configured"'));
      expect(settings, contains('KEY_AUTO_START, false'));
      expect(settings, contains('KEY_ACCOUNT_CONFIGURED, false'));
      expect(dartSettings, contains("'auto_start'"));
      expect(dartSettings, contains("'account_configured'"));
      // 三个写入口都要同步：少一个，标记就会和磁盘上的配置脱节。
      for (final entryPoint in const [
        'static Future<bool> saveConfig(',
        'static Future<bool> deleteConfig(',
        'static Future<bool> configExists(',
      ]) {
        expect(
          _methodBody(config, entryPoint),
          contains('_syncAccountConfigured()'),
          reason:
              '$entryPoint 之后必须同步配置存在标记，'
              '配置文件在 Dart 侧文档目录，原生读不到',
        );
      }
    });

    test('不用 WorkManager、精确闹钟或后台 Activity 兜底', () {
      expect(_read('pubspec.yaml'), isNot(contains('workmanager')));
      expect(
        _read('android/app/build.gradle.kts'),
        isNot(contains('workmanager')),
      );
      expect(
        manifest,
        isNot(contains('android.permission.SCHEDULE_EXACT_ALARM')),
      );
      expect(manifest, isNot(contains('android.permission.USE_EXACT_ALARM')));
      expect(manifest, isNot(contains('android.permission.WAKE_LOCK')));
      // 开机广播只由 BootReceiver 接收：出现第二个订阅者就说明有第二条启动路径。
      expect(
        RegExp(r'action\.BOOT_COMPLETED')
            .allMatches(_codeOnly(manifest))
            .length,
        1,
      );
      expect(manifest, contains('android:name=".BootReceiver"'));
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

/// 去掉注释，只对可执行代码断言。
///
/// 说明文字可以自由提协议名词，"不接触协议"这类结论必须只看代码。
String _codeOnly(String source) {
  return source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//.*'), '');
}

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
