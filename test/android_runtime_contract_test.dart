import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:LinkUp/utils/AuthRuntimeClient.dart';
import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/RuntimeContract.g.dart';

/// Android 原生层与 Dart 之间的跨语言契约。
///
/// Kotlin 桥是通道、命令、wire 键与原生偏好约定的源文件；Dart 常量由它生成。
/// 这里直接比对两侧事实，并检查关键接线仍消费这些常量。
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
  final backupRules = _read('android/app/src/main/res/xml/backup_rules.xml');
  final extractionRules = _read(
    'android/app/src/main/res/xml/data_extraction_rules.xml',
  );

  test('诊断日志不进入 Android 云备份或设备迁移', () {
    expect(backupRules, contains('path="app_flutter/error.log"'));
    expect(
      RegExp('path="app_flutter/error.log"').allMatches(extractionRules),
      hasLength(2),
    );
  });

  group('跨语言运行时契约', () {
    test('通道、命令、wire 键和偏好约定都来自 Kotlin 桥', () {
      final facts = <String, Object>{
        'HOST_CHANNEL': RuntimeContract.hostChannel,
        'UI_CHANNEL': RuntimeContract.uiChannel,
        'SYSTEM_CHANNEL': RuntimeContract.systemChannel,
        'COMMAND_START': RuntimeContract.commandStart,
        'COMMAND_STOP': RuntimeContract.commandStop,
        'COMMAND_MANUAL_CHECK': RuntimeContract.commandManualCheck,
        'COMMAND_LOGOUT': RuntimeContract.commandLogout,
        'COMMAND_KICK_DEVICE': RuntimeContract.commandKickDevice,
        'COMMAND_CONFIGURATION_CHANGED':
            RuntimeContract.commandConfigurationChanged,
        'COMMAND_NETWORK_CHANGED': RuntimeContract.commandNetworkChanged,
        'METHOD_READY': RuntimeContract.methodReady,
        'METHOD_STATE': RuntimeContract.methodState,
        'METHOD_COMMAND': RuntimeContract.methodCommand,
        'METHOD_FIRE_COMMAND': RuntimeContract.methodFireCommand,
        'METHOD_ATTACH': RuntimeContract.methodAttach,
        'METHOD_DETACH': RuntimeContract.methodDetach,
        'METHOD_ON_STATE': RuntimeContract.methodOnState,
        'KEY_NAME': RuntimeContract.keyName,
        'KEY_ARGS': RuntimeContract.keyArgs,
        'KEY_STATUS': RuntimeContract.keyStatus,
        'KEY_IS_ONLINE': RuntimeContract.keyIsOnline,
        'KEY_MESSAGE': RuntimeContract.keyMessage,
        'KEY_REASON': RuntimeContract.keyReason,
        'KEY_ACID': RuntimeContract.keyAcid,
        'KEY_RETRY_AFTER_SECONDS': RuntimeContract.keyRetryAfterSeconds,
        'KEY_USER_INFO': RuntimeContract.keyUserInfo,
        'KEY_NOTIFICATION': RuntimeContract.keyNotification,
        'KEY_TITLE': RuntimeContract.keyTitle,
        'KEY_TEXT': RuntimeContract.keyText,
        'KEY_CONNECTED': RuntimeContract.keyConnected,
        'KEY_IP': RuntimeContract.keyIp,
        'PREFERENCES_NAME': RuntimeContract.preferencesName,
        'PREFERENCE_PREFIX': RuntimeContract.preferencePrefix,
        'PREFERENCE_KEEP_ALIVE': RuntimeContract.preferenceKeepAlive,
        'PREFERENCE_AUTO_START': RuntimeContract.preferenceAutoStart,
        'PREFERENCE_ACCOUNT_CONFIGURED':
            RuntimeContract.preferenceAccountConfigured,
        'DEFAULT_KEEP_ALIVE': RuntimeContract.defaultKeepAlive,
        'DEFAULT_AUTO_START': RuntimeContract.defaultAutoStart,
        'DEFAULT_ACCOUNT_CONFIGURED': RuntimeContract.defaultAccountConfigured,
        'SYSTEM_START_AUTH_RUNTIME': RuntimeContract.systemStartAuthRuntime,
        'SYSTEM_STOP_AUTH_RUNTIME': RuntimeContract.systemStopAuthRuntime,
        'SYSTEM_REQUEST_NOTIFICATION_PERMISSION':
            RuntimeContract.systemRequestNotificationPermission,
        'SYSTEM_IS_AUTO_START_SUPPORTED':
            RuntimeContract.systemIsAutoStartSupported,
        'SYSTEM_CHECK_AUTO_START_PERMISSION':
            RuntimeContract.systemCheckAutoStartPermission,
        'SYSTEM_REQUEST_AUTO_START_PERMISSION':
            RuntimeContract.systemRequestAutoStartPermission,
        'SYSTEM_OPEN_BATTERY_OPTIMIZATION_SETTINGS':
            RuntimeContract.systemOpenBatteryOptimizationSettings,
      };
      for (final fact in facts.entries) {
        expect(
          bridge,
          contains('const val ${fact.key} = ${jsonEncode(fact.value)}'),
          reason: '${fact.key} 的 Dart 派生值必须与 Kotlin 源一致',
        );
      }
    });

    test('两侧消费者使用契约常量', () {
      expect(AuthRuntimeClient.uiChannelName, RuntimeContract.uiChannel);
      expect(
        MethodChannelAuthRuntimeHost.hostChannelName,
        RuntimeContract.hostChannel,
      );
      expect(mainActivity, contains('AuthRuntimeBridge.SYSTEM_CHANNEL'));
      expect(mainActivity, contains('AuthRuntimeBridge.UI_CHANNEL'));
      expect(mainActivity, contains('AuthRuntimeBridge.METHOD_COMMAND'));
      expect(mainActivity, contains('AuthRuntimeBridge.METHOD_FIRE_COMMAND'));
      expect(settings, contains('AuthRuntimeBridge.PREFERENCES_NAME'));
      expect(settings, contains('AuthRuntimeBridge.PREFERENCE_PREFIX'));
      expect(
        settings,
        contains('AuthRuntimeBridge.DEFAULT_ACCOUNT_CONFIGURED'),
      );
      expect(notification, contains('AuthRuntimeBridge.KEY_NOTIFICATION'));
      expect(state, contains('RuntimeContract.keyNotification'));
      expect(dartSettings, contains('RuntimeContract.systemChannel'));
      expect(entrypoint, contains('RuntimeContract.methodCommand'));
    });

    test('运行时命令清单与共享契约一致', () {
      expect(AuthRuntimeController.declaredCommands, {
        RuntimeContract.commandStart,
        RuntimeContract.commandStop,
        RuntimeContract.commandManualCheck,
        RuntimeContract.commandLogout,
        RuntimeContract.commandKickDevice,
        RuntimeContract.commandConfigurationChanged,
        RuntimeContract.commandNetworkChanged,
      });
    });

    test('无需回包的命令交给宿主后立即完成 UI 调用', () {
      final handler = _methodBody(
        mainActivity,
        'private fun handleRuntimeCall(',
      );
      expect(handler, contains('AuthRuntimeBridge.METHOD_FIRE_COMMAND'));
      expect(handler, contains('else null'));
      expect(handler, contains('result.success(null)'));
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
      expect(bridge, contains('invokeMethod(METHOD_COMMAND'));
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
      expect(
        settings,
        contains('KEY_KEEP_ALIVE, AuthRuntimeBridge.DEFAULT_KEEP_ALIVE'),
      );
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
          reason: '平台回调不得接触 $forbidden：Srun 协议只在 Dart 单轮认证实现里运行',
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
      expect(service, contains('AuthRuntimeBridge.KEY_CONNECTED'));
      expect(controller, contains('RuntimeContract.keyConnected'));
      expect(
        _methodBody(controller, 'case commandNetworkChanged:'),
        contains('args?[RuntimeContract.keyConnected] == true'),
        reason: '原生只发命令，可用性判断必须由协调器做',
      );
    });
  });

  group('开机自启', () {
    test('开机门读取配置和开关并保留服务启动接线', () {
      final onReceive = _methodBody(boot, 'override fun onReceive(');
      expect(onReceive, contains('isAccountConfigured'));
      expect(onReceive, contains('isKeepAliveEnabled'));
      expect(onReceive, contains('isAutoStartEnabled'));
      expect(onReceive, contains('AuthRuntimeService.start(context)'));
    });

    test('运行期间改设置会立刻反映到服务启停', () {
      final applyKeepAlive = _methodBody(
        dartSettings,
        'static Future<void> applyKeepAlive(',
      );
      expect(applyKeepAlive, contains('getKeepAlive()'));
      expect(
        applyKeepAlive,
        contains('RuntimeContract.systemStartAuthRuntime'),
      );
      expect(applyKeepAlive, contains('RuntimeContract.systemStopAuthRuntime'));
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
      expect(
        settings,
        contains(
          'KEY_ACCOUNT_CONFIGURED = AuthRuntimeBridge.PREFERENCE_PREFIX + AuthRuntimeBridge.PREFERENCE_ACCOUNT_CONFIGURED',
        ),
      );
      expect(
        settings,
        contains('KEY_AUTO_START, AuthRuntimeBridge.DEFAULT_AUTO_START'),
      );
      expect(
        settings,
        contains(
          'KEY_ACCOUNT_CONFIGURED, AuthRuntimeBridge.DEFAULT_ACCOUNT_CONFIGURED',
        ),
      );
      expect(dartSettings, contains('RuntimeContract.preferenceAutoStart'));
      expect(
        dartSettings,
        contains('RuntimeContract.preferenceAccountConfigured'),
      );
      expect(
        config,
        contains(
          'writeConfiguredHint: SystemSettingsUtil.setAccountConfigured',
        ),
      );
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

  group('启动时序', () {
    // 首帧等待的判定依赖源码结构而不是运行时行为：main() 会构建整个应用，
    // 真实日志初始化要建文件、真实配置检查要读文件，都得在 fake-async 之外
    // 的真实事件循环里推进，测试里无法稳定驱动；通知权限那一侧的副作用在
    // 非 Android 宿主上根本不会发生。结构断言能钉住真正的回归形态。
    test('日志初始化与后台运行时都推迟到首帧之后', () {
      final mainBody = _methodBody(mainDart, 'void main(List<String> args)');
      expect(mainBody, contains('runApp('));
      expect(
        mainBody,
        contains('addPostFrameCallback'),
        reason: '不参与首屏内容的初始化必须挂在首帧之后',
      );
      expect(
        mainBody,
        isNot(contains('LogUtil.init')),
        reason: '日志要先走一次 path_provider 往返再建文件，留在 runApp 之前会卡住首帧',
      );
      expect(
        mainBody,
        isNot(contains('applyKeepAlive')),
        reason: 'applyKeepAlive 会拉起前台服务并弹通知权限，留在 runApp 之前用户先看到系统弹窗',
      );
    });

    test('首屏判定依赖的偏好在 runApp 之前就已加载', () {
      final mainBody = _methodBody(mainDart, 'void main(List<String> args)');
      final initIndex = mainBody.indexOf('SystemSettingsUtil.init()');
      expect(
        initIndex,
        greaterThanOrEqualTo(0),
        reason: '首帧要同步读“配置存在”提示，偏好必须先加载',
      );
      expect(
        initIndex,
        lessThan(mainBody.indexOf('runApp(')),
        reason: '提示要在首帧就能同步读到，加载偏好不能推迟',
      );
    });

    test('首帧之后仍初始化日志并应用后台开关', () {
      final deferred = _methodBody(mainDart, 'Future<void> _prepareRuntime(');
      expect(deferred, contains('LogUtil.init()'));
      expect(deferred, contains('applyKeepAlive()'));
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
