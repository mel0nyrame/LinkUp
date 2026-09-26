import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/SrunAuthenticationProtocol.dart';

/// 后台认证入口。
///
/// Android 前台服务用 `DartExecutor.DartEntrypoint` 启动一次，之后通过
/// MethodChannel 向这个正在运行的 isolate 下发命令。
@pragma('vm:entry-point')
void linkupAuthRuntimeDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_bootstrap());
}

AuthRuntimeController? _controller;

/// 构建后台运行时并在命令处理器就绪后通知宿主。
///
/// 宿主在同一轮主线程任务里完成插件与 MethodChannel 注册；Dart isolate 要等
/// 主线程空闲后才会运行首个事件，因此注册一定先于下面的发布动作。
Future<void> _bootstrap() async {
  if (_controller != null) return;
  await LogUtil.init();

  final controller = AuthRuntimeController(
    coordinator: AuthenticationCoordinator(
      configSource: ConfigUtilSource(),
      protocol: SrunAuthenticationProtocol(),
      protocolFactory: SrunAuthenticationProtocol.new,
      networkState: AuthenticationNetworkTracker(),
    ),
    host: MethodChannelAuthRuntimeHost(),
  );
  _controller = controller;
  const MethodChannel(MethodChannelAuthRuntimeHost.hostChannelName)
      .setMethodCallHandler(_dispatch);
  controller.subscribe();
  await controller.host.publishReady();
}

Future<Object?> _dispatch(MethodCall call) async {
  if (call.method != 'command') return null;
  final controller = _controller;
  if (controller == null) {
    await LogUtil.warning('认证运行时尚未就绪，忽略命令');
    return null;
  }

  final command = call.arguments;
  if (command is! Map || command['name'] is! String) return null;
  final args = command['args'];
  return controller.execute(
    command['name'] as String,
    args is Map ? Map<String, Object?>.from(args) : null,
  );
}
