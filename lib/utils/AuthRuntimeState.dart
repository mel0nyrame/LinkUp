import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';

/// 认证运行时跨平台边界发布的状态快照。
///
/// 快照只携带概况页需要的信息：账号、IP 和流量来自 `rad_user_info`，ACID 来自
/// 本轮认证参数。密码、Challenge、HMD5 和签名不进入这里，因此常驻通知和 UI
/// 都不可能从状态中读到凭据。
class AuthRuntimeState {
  const AuthRuntimeState({
    required this.status,
    required this.isOnline,
    this.message,
    this.acid,
    this.retryAfterSeconds,
    this.userInfo,
  });

  final AuthenticationStatus status;
  final bool isOnline;
  final String? message;
  final String? acid;
  final int? retryAfterSeconds;
  final RadUserInfo? userInfo;

  factory AuthRuntimeState.fromCoordinatorState(AuthenticationState state) {
    return AuthRuntimeState(
      status: state.status,
      isOnline: state.isOnline,
      message: state.message,
      acid: state.parameters?.acid,
      retryAfterSeconds: state.retryAfter?.inSeconds,
      userInfo: state.userInfo,
    );
  }

  const AuthRuntimeState.stopped()
    : status = AuthenticationStatus.stopped,
      isOnline = false,
      message = null,
      acid = null,
      retryAfterSeconds = null,
      userInfo = null;

  Map<String, Object?> toMap() {
    final content = notificationContentFor(this);
    return <String, Object?>{
      'status': status.name,
      'isOnline': isOnline,
      if (message != null) 'message': message,
      if (acid != null) 'acid': acid,
      if (retryAfterSeconds != null) 'retryAfterSeconds': retryAfterSeconds,
      if (userInfo != null) 'userInfo': userInfo!.toJson(),
      'notification': <String, Object?>{
        'title': content.title,
        'text': content.text,
      },
    };
  }

  static AuthRuntimeState fromMap(Map<Object?, Object?> map) {
    final name = map['status'];
    final status = AuthenticationStatus.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AuthenticationStatus.stopped,
    );
    final rawUserInfo = map['userInfo'];
    return AuthRuntimeState(
      status: status,
      isOnline: map['isOnline'] == true,
      message: map['message'] as String?,
      acid: map['acid'] as String?,
      retryAfterSeconds: map['retryAfterSeconds'] as int?,
      userInfo: rawUserInfo is Map
          ? RadUserInfo.fromJson(Map<String, dynamic>.from(rawUserInfo))
          : null,
    );
  }
}

/// 常驻通知显示的文本。
///
/// 内容只由状态枚举和重试间隔派生，不读取 [AuthRuntimeState.userInfo]、
/// [AuthRuntimeState.acid] 或状态 message，因此通知不会泄漏用户信息或认证
/// 材料。
class AuthRuntimeNotificationContent {
  const AuthRuntimeNotificationContent({
    required this.title,
    required this.text,
  });

  final String title;
  final String text;
}

/// 从状态快照派生常驻通知内容。
AuthRuntimeNotificationContent notificationContentFor(AuthRuntimeState state) {
  return AuthRuntimeNotificationContent(
    title: 'LinkUp 校园网认证',
    text: _notificationText(state),
  );
}

String _notificationText(AuthRuntimeState state) {
  switch (state.status) {
    case AuthenticationStatus.online:
    case AuthenticationStatus.alreadyOnline:
      return '已连接到校园网';
    case AuthenticationStatus.checking:
      return '正在检查网络状态…';
    case AuthenticationStatus.authenticating:
      return '正在认证校园网…';
    case AuthenticationStatus.offline:
      return 'WiFi 未连接';
    case AuthenticationStatus.backingOff:
      final retryAfter = state.retryAfterSeconds;
      return retryAfter == null ? '认证未完成，稍后重试' : '认证未完成，$retryAfter 秒后重试';
    case AuthenticationStatus.failed:
    case AuthenticationStatus.cancelled:
    case AuthenticationStatus.stale:
      return '认证未完成，将自动重试';
    case AuthenticationStatus.idle:
    case AuthenticationStatus.stopped:
      return '后台认证已停止';
  }
}
