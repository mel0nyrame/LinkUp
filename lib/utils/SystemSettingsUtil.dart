import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 系统设置工具类
class SystemSettingsUtil {
  static const String _keepAliveKey = 'keep_alive';
  static const String _autoStartKey = 'auto_start';
  static const MethodChannel _systemChannel = MethodChannel(
    'com.mel0ny.linkup/system',
  );

  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 认证运行时由 Android 前台服务承载，这里把已保存的设置应用到服务。
    await applyKeepAlive();
  }

  /// 获取保留后台设置
  static bool getKeepAlive() {
    return _prefs?.getBool(_keepAliveKey) ?? true;
  }

  /// 设置保留后台
  static Future<bool> setKeepAlive(bool value) async {
    final result = await _prefs?.setBool(_keepAliveKey, value) ?? false;
    await applyKeepAlive();
    return result;
  }

  /// 获取开机自启设置
  static bool getAutoStart() {
    return _prefs?.getBool(_autoStartKey) ?? false;
  }

  /// 设置开机自启
  static Future<bool> setAutoStart(bool value) async {
    final result = await _prefs?.setBool(_autoStartKey, value) ?? false;

    // Android 上检查权限
    if (Platform.isAndroid && value) {
      final hasPermission = await _checkAutoStartPermission();
      if (!hasPermission) {
        // 尝试打开设置页面
        await _requestAutoStartPermission();
      }
    }

    return result;
  }

  /// 把“保留后台运行”应用到 Android 前台认证服务。
  ///
  /// 认证运行时由服务持有的独立 FlutterEngine 承载，系统保活由前台服务负责，
  /// 屏幕常亮不参与认证保活。
  static Future<void> applyKeepAlive() async {
    if (!Platform.isAndroid) return;

    try {
      if (getKeepAlive()) {
        await _systemChannel.invokeMethod<void>('startAuthRuntime');
        // “保留后台运行”默认为开启，新装用户不会主动触发设置项，因此在前台服务
        // 真正开始常驻时申请通知权限。Android 拒绝多次后不再弹窗，用户拒绝也
        // 不会中断认证。
        await requestNotificationPermission();
      } else {
        await _systemChannel.invokeMethod<void>('stopAuthRuntime');
      }
    } catch (e, stackTrace) {
      await LogUtil.error('切换后台认证运行时失败', e, stackTrace);
    }
  }

  /// 为常驻通知申请权限。
  ///
  /// Android 13+ 没有通知权限时前台服务仍会运行，但系统不会展示常驻通知，因此
  /// 拒绝不会中断认证。
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;

    try {
      await _systemChannel.invokeMethod<void>('requestNotificationPermission');
    } catch (e, stackTrace) {
      await LogUtil.error('请求通知权限失败', e, stackTrace);
    }
  }

  /// 检查是否支持开机自启（仅 Android）
  static Future<bool> isAutoStartSupported() async {
    if (!Platform.isAndroid) return false;

    try {
      final bool result = await _systemChannel.invokeMethod(
        'isAutoStartSupported',
      );
      return result;
    } catch (e, stackTrace) {
      await LogUtil.error('检查开机自启支持失败', e, stackTrace);
      return false;
    }
  }

  /// 检查是否已开启开机自启权限（仅 Android）
  static Future<bool> _checkAutoStartPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final bool result = await _systemChannel.invokeMethod(
        'checkAutoStartPermission',
      );
      return result;
    } catch (e, stackTrace) {
      await LogUtil.error('检查开机自启权限失败', e, stackTrace);
      return false;
    }
  }

  /// 请求开机自启权限（打开设置页面）
  static Future<void> _requestAutoStartPermission() async {
    if (!Platform.isAndroid) return;

    try {
      await _systemChannel.invokeMethod('requestAutoStartPermission');
    } catch (e, stackTrace) {
      await LogUtil.error('请求开机自启权限失败', e, stackTrace);
    }
  }

  /// 打开电池优化白名单设置
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _systemChannel.invokeMethod('openBatteryOptimizationSettings');
    } catch (e, stackTrace) {
      await LogUtil.error('打开电池优化设置失败', e, stackTrace);
    }
  }
}
