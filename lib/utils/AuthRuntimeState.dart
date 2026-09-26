import 'package:LinkUp/utils/AuthenticationCoordinator.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:LinkUp/utils/RuntimeContract.g.dart';

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
    this.reason = AuthenticationReason.none,
  });

  final AuthenticationStatus status;
  final bool isOnline;
  final String? message;
  final String? acid;
  final int? retryAfterSeconds;
  final RadUserInfo? userInfo;
  final AuthenticationReason reason;

  factory AuthRuntimeState.fromCoordinatorState(AuthenticationState state) {
    return AuthRuntimeState(
      status: state.status,
      isOnline: state.isOnline,
      message: state.message,
      acid: state.parameters?.acid,
      retryAfterSeconds: state.retryAfter?.inSeconds,
      userInfo: state.userInfo,
      reason: state.reason,
    );
  }

  const AuthRuntimeState.stopped()
    : status = AuthenticationStatus.stopped,
      isOnline = false,
      message = null,
      acid = null,
      retryAfterSeconds = null,
      userInfo = null,
      reason = AuthenticationReason.none;

  AuthStatusPresentation get presentation {
    switch (status) {
      case AuthenticationStatus.online:
      case AuthenticationStatus.alreadyOnline:
        return AuthStatusPresentation(
          title: '已连接',
          detail: message ?? '已在线',
          notification: '已连接到校园网',
        );
      case AuthenticationStatus.checking:
        return const AuthStatusPresentation(
          title: '正在检查',
          detail: '正在检查网络状态...',
          notification: '正在检查网络状态…',
          loading: true,
        );
      case AuthenticationStatus.authenticating:
        return const AuthStatusPresentation(
          title: '正在认证',
          detail: '正在登录...',
          notification: '正在认证校园网…',
          loading: true,
        );
      case AuthenticationStatus.offline:
        return AuthStatusPresentation(
          title: 'WiFi 未连接',
          detail: message ?? 'WiFi 未连接',
          notification: 'WiFi 未连接',
        );
      case AuthenticationStatus.backingOff:
        return AuthStatusPresentation(
          title: _reasonTitle(reason),
          detail: message ?? '认证未完成，稍后重试',
          notification: retryAfterSeconds == null
              ? '认证未完成，稍后重试'
              : '认证未完成，$retryAfterSeconds 秒后重试',
          needsAction: _needsAction(reason),
        );
      case AuthenticationStatus.failed:
      case AuthenticationStatus.cancelled:
      case AuthenticationStatus.stale:
        return AuthStatusPresentation(
          title: _reasonTitle(reason),
          detail: message ?? '认证未完成，将自动重试',
          notification: '认证未完成，将自动重试',
          needsAction: _needsAction(reason),
        );
      case AuthenticationStatus.stopped:
        return AuthStatusPresentation(
          title: '未连接',
          detail: message,
          notification: '后台认证已停止',
        );
    }
  }

  Map<String, Object?> toMap() {
    final content = notificationContentFor(this);
    return <String, Object?>{
      RuntimeContract.keyStatus: status.name,
      RuntimeContract.keyIsOnline: isOnline,
      if (message != null) RuntimeContract.keyMessage: message,
      RuntimeContract.keyReason: reason.name,
      if (acid != null) RuntimeContract.keyAcid: acid,
      if (retryAfterSeconds != null)
        RuntimeContract.keyRetryAfterSeconds: retryAfterSeconds,
      if (userInfo != null) RuntimeContract.keyUserInfo: userInfo!.toJson(),
      RuntimeContract.keyNotification: <String, Object?>{
        RuntimeContract.keyTitle: content.title,
        RuntimeContract.keyText: content.text,
      },
    };
  }

  static AuthRuntimeState fromMap(Map<Object?, Object?> map) {
    final name = map[RuntimeContract.keyStatus];
    final status = AuthenticationStatus.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AuthenticationStatus.stopped,
    );
    final rawUserInfo = map[RuntimeContract.keyUserInfo];
    final rawReason = map[RuntimeContract.keyReason];
    return AuthRuntimeState(
      status: status,
      isOnline: map[RuntimeContract.keyIsOnline] == true,
      message: map[RuntimeContract.keyMessage] as String?,
      acid: map[RuntimeContract.keyAcid] as String?,
      retryAfterSeconds: map[RuntimeContract.keyRetryAfterSeconds] as int?,
      userInfo: rawUserInfo is Map
          ? RadUserInfo.fromJson(Map<String, dynamic>.from(rawUserInfo))
          : null,
      reason: AuthenticationReason.values.firstWhere(
        (value) => value.name == rawReason,
        orElse: () => AuthenticationReason.none,
      ),
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

class AuthStatusPresentation {
  const AuthStatusPresentation({
    required this.title,
    required this.detail,
    required this.notification,
    this.loading = false,
    this.needsAction = false,
  });

  final String title;
  final String? detail;
  final String notification;
  final bool loading;
  final bool needsAction;
}

String _reasonTitle(AuthenticationReason reason) => switch (reason) {
  AuthenticationReason.wifiUnavailable => 'WiFi 未连接',
  AuthenticationReason.missingConfig => '未配置',
  AuthenticationReason.invalidCredentials => '账号验证失败',
  AuthenticationReason.invalidAcid => 'ACID 无效',
  AuthenticationReason.networkUnavailable => '网络不可用',
  AuthenticationReason.serverUnavailable => '认证服务器异常',
  AuthenticationReason.none || AuthenticationReason.unknown => '未连接',
};

bool _needsAction(AuthenticationReason reason) =>
    reason == AuthenticationReason.missingConfig ||
    reason == AuthenticationReason.invalidCredentials ||
    reason == AuthenticationReason.invalidAcid;

/// 从状态快照派生常驻通知内容。
AuthRuntimeNotificationContent notificationContentFor(AuthRuntimeState state) {
  return AuthRuntimeNotificationContent(
    title: 'LinkUp 校园网认证',
    text: state.presentation.notification,
  );
}
