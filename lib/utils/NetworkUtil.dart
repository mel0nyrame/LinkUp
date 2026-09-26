import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 网络工具类，用于检测 WiFi 等网络状态
class NetworkUtil {
  static final Connectivity _connectivity = Connectivity();

  /// 检查 WiFi 是否开启并连接
  /// 返回 true 表示 WiFi 已连接，false 表示未连接 WiFi
  static Future<bool> isWifiConnected() async {
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();

      // 检查是否有 WiFi 连接
      // 注意：connectivity_plus 3.x+ 返回的是 List<ConnectivityResult>
      for (final result in results) {
        if (result == ConnectivityResult.wifi) {
          return true;
        }
      }
      return false;
    } catch (e) {
      LogUtil.error('检测 WiFi 状态失败', e);
      return false;
    }
  }
}
