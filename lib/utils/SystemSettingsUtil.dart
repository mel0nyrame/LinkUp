import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:LinkUp/utils/LogUtil.dart';

/// 系统设置工具类
class SystemSettingsUtil {
  static const String _keepAliveKey = 'keep_alive';
  static const String _autoStartKey = 'auto_start';
  static const String _accountConfiguredKey = 'account_configured';
  static const MethodChannel _systemChannel = MethodChannel(
    'com.mel0ny.linkup/system',
  );

  static SharedPreferences? _prefs;

  /// 加载偏好。
  ///
  /// 这里只读偏好。把开关应用到前台服务是独立的 [applyKeepAlive]，由调用方在
  /// 真正需要服务启停时显式调用：启动路径上它要走 MethodChannel 并可能弹系统
  /// 通知权限对话框，混在偏好加载里会让打开应用后的等待串到首屏之前。
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 读取“是否存在已保存的认证配置”提示。
  ///
  /// 这只是首帧就能读到的**提示**，权威事实是 `ConfigUtil.configExists` 对配置
  /// 文件的真实检查。键不存在时返回 null 而不是 false：没有可信事实时调用方必须
  /// 当作未知处理，不许当成“未配置”跳过首次配置。
  static bool? getAccountConfiguredHint() =>
      _prefs?.getBool(_accountConfiguredKey);

  /// 记录是否存在已保存的认证配置。
  ///
  /// 开机自启在 Dart isolate 启动前就要判定，配置文件却只有 Dart 侧能读；这个
  /// 派生标记是唯一跨语言可读的“配置存在”事实，由 [ConfigUtil] 在保存、删除和
  /// 每次启动检查时同步。
  static Future<void> setAccountConfigured(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    final result = await _prefs?.setBool(_accountConfiguredKey, value) ?? false;
    if (!result) {
      await LogUtil.warning('认证配置标记写入失败，开机自启可能不会启动服务');
    }
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
