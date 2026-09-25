import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PluginUtilities;

import 'package:flutter/widgets.dart';

import 'package:LinkUp/utils/AuthRuntimeController.dart';
import 'package:LinkUp/utils/AuthRuntimeHost.dart';
import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/SrunAuthenticationProtocol.dart';

/// 后台认证入口。
///
/// Android 前台服务用 embedder 的 `DartExecutor.DartEntrypoint` 以无参形式首次
/// 启动它，随后用 callback dispatcher 携带命令名重复调用。
@pragma('vm:entry-point')
void linkupAuthRuntimeDispatcher([List<dynamic>? args]) {
  WidgetsFlutterBinding.ensureInitialized();
  if (args == null || args.isEmpty) {
    unawaited(_bootstrap());
    return;
  }
  unawaited(_dispatch(args));
}

AuthRuntimeController? _controller;

/// 构建后台运行时并把命令回调句柄交给宿主。
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
  controller.subscribe();

  final handle = PluginUtilities.getCallbackHandle(linkupAuthRuntimeDispatcher);
  if (handle == null) {
    await LogUtil.error('认证运行时回调句柄不可用，后台认证无法接受命令', null);
    return;
  }
  await controller.host.publishCommandHandle(handle.toRawHandle());
}

Future<void> _dispatch(List<dynamic> args) async {
  final controller = _controller;
  if (controller == null) {
    await LogUtil.warning('认证运行时尚未就绪，忽略命令');
    return;
  }

  final command = args[0];
  if (command is! String) return;

  final rawArgs = args.length > 1 ? args[1] : null;
  final parsed = rawArgs is String ? _decodeArgs(rawArgs) : null;
  final requestId = parsed?.remove('id');

  final value = await controller.execute(command, parsed);
  if (requestId is int) {
    await controller.host.publishCommandResult(requestId, value);
  }
}

Map<String, Object?>? _decodeArgs(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return Map<String, Object?>.from(decoded);
  } on FormatException {
    return null;
  }
}
