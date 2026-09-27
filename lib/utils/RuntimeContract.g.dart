// 由 tool/generate_runtime_contract.dart 从 AuthRuntimeBridge.kt 生成。
// 修改 Kotlin 契约区块后重新生成，勿手改。
abstract final class RuntimeContract {
  static const String hostChannel = "com.mel0ny.linkup/authRuntime";
  static const String uiChannel = "com.mel0ny.linkup/authUi";
  static const String systemChannel = "com.mel0ny.linkup/system";
  static const String commandStart = "start";
  static const String commandStop = "stop";
  static const String commandManualCheck = "manualCheck";
  static const String commandLogout = "logout";
  static const String commandKickDevice = "kickDevice";
  static const String commandConfigurationChanged = "configurationChanged";
  static const String commandNetworkChanged = "networkChanged";
  static const String methodReady = "ready";
  static const String methodState = "state";
  static const String methodCommand = "command";
  static const String methodFireCommand = "fireCommand";
  static const String methodAttach = "attach";
  static const String methodDetach = "detach";
  static const String methodOnState = "onState";
  static const String keyName = "name";
  static const String keyArgs = "args";
  static const String keyStatus = "status";
  static const String keyIsOnline = "isOnline";
  static const String keyMessage = "message";
  static const String keyReason = "reason";
  static const String keyAcid = "acid";
  static const String keyRetryAfterSeconds = "retryAfterSeconds";
  static const String keyUserInfo = "userInfo";
  static const String keyNotification = "notification";
  static const String keyTitle = "title";
  static const String keyText = "text";
  static const String keyConnected = "connected";
  static const String keyIp = "ip";
  static const String preferencesName = "FlutterSharedPreferences";
  static const String preferencePrefix = "flutter.";
  static const String preferenceKeepAlive = "keep_alive";
  static const String preferenceAutoStart = "auto_start";
  static const String preferenceAccountConfigured = "account_configured";
  static const bool defaultKeepAlive = true;
  static const bool defaultAutoStart = false;
  static const bool defaultAccountConfigured = false;
  static const String systemStartAuthRuntime = "startAuthRuntime";
  static const String systemStopAuthRuntime = "stopAuthRuntime";
  static const String systemRequestNotificationPermission =
      "requestNotificationPermission";
  static const String systemIsAutoStartSupported = "isAutoStartSupported";
  static const String systemCheckAutoStartPermission =
      "checkAutoStartPermission";
  static const String systemRequestAutoStartPermission =
      "requestAutoStartPermission";
  static const String systemOpenBatteryOptimizationSettings =
      "openBatteryOptimizationSettings";
}
