import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络工具类，用于检测 WiFi 等网络状态
class NetworkUtil {
  static final Connectivity _connectivity = Connectivity();

  /// 检查 WiFi 是否开启并连接
  /// 返回 true 表示 WiFi 已连接，false 表示未连接 WiFi
  static Future<bool> isWifiConnected() async {
    try {
      final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      
      // 检查是否有 WiFi 连接
      // 注意：connectivity_plus 3.x+ 返回的是 List<ConnectivityResult>
      for (final result in results) {
        if (result == ConnectivityResult.wifi) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('检测 WiFi 状态失败: $e');
      return false;
    }
  }

  /// 获取当前网络连接类型
  static Future<String> getConnectionType() async {
    try {
      final List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      
      if (results.isEmpty) {
        return '无网络连接';
      }
      
      final result = results.first;
      switch (result) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return '移动数据';
        case ConnectivityResult.ethernet:
          return '以太网';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.bluetooth:
          return '蓝牙';
        case ConnectivityResult.other:
          return '其他网络';
        case ConnectivityResult.none:
        default:
          return '无网络连接';
      }
    } catch (e) {
      return '未知';
    }
  }

  /// 监听网络状态变化
  static Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}
