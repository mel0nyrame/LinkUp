import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 系统设置工具类
class SystemSettingsUtil {
  static const String _keepAliveKey = 'keep_alive';
  static const String _autoStartKey = 'auto_start';
  
  static SharedPreferences? _prefs;
  static bool _isKeepAliveEnabled = false;

  /// 初始化
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isKeepAliveEnabled = getKeepAlive();
    
    // 根据设置应用后台保活
    await applyKeepAlive();
  }

  /// 获取保留后台设置
  static bool getKeepAlive() {
    return _prefs?.getBool(_keepAliveKey) ?? true;
  }

  /// 设置保留后台
  static Future<bool> setKeepAlive(bool value) async {
    _isKeepAliveEnabled = value;
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

  /// 应用后台保活设置
  static Future<void> applyKeepAlive() async {
    if (_isKeepAliveEnabled) {
      // 启用屏幕常亮（防止应用被系统休眠）
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  /// 检查是否支持开机自启（仅 Android）
  static Future<bool> isAutoStartSupported() async {
    if (!Platform.isAndroid) return false;
    
    try {
      const platform = MethodChannel('com.example.linkup/system');
      final bool result = await platform.invokeMethod('isAutoStartSupported');
      return result;
    } catch (e) {
      print('检查开机自启支持失败: $e');
      return false;
    }
  }

  /// 检查开机自启权限（仅 Android）
  static Future<bool> _checkAutoStartPermission() async {
    if (!Platform.isAndroid) return false;
    
    try {
      const platform = MethodChannel('com.example.linkup/system');
      final bool result = await platform.invokeMethod('checkAutoStartPermission');
      return result;
    } catch (e) {
      print('检查开机自启权限失败: $e');
      return false;
    }
  }

  /// 请求开机自启权限（打开设置页面）
  static Future<void> _requestAutoStartPermission() async {
    if (!Platform.isAndroid) return;
    
    try {
      const platform = MethodChannel('com.example.linkup/system');
      await platform.invokeMethod('requestAutoStartPermission');
    } catch (e) {
      print('请求开机自启权限失败: $e');
    }
  }

  /// 打开电池优化白名单设置
  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      const platform = MethodChannel('com.example.linkup/system');
      await platform.invokeMethod('openBatteryOptimizationSettings');
    } catch (e) {
      print('打开电池优化设置失败: $e');
    }
  }
}
