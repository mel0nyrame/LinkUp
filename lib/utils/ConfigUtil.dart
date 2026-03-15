import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ConfigUtil {
  static const String _fileName = 'linkup_config.json';
  
  // 获取配置文件路径
  static Future<String> get _localPath async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      // 确保目录存在
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return '${directory.path}/$_fileName';
    } catch (e) {
      debugPrint('ConfigUtil: 获取目录失败 - $e');
      rethrow;
    }
  }

  // 检查配置文件是否存在
  static Future<bool> configExists() async {
    try {
      final path = await _localPath;
      final file = File(path);
      return await file.exists();
    } catch (e) {
      debugPrint('ConfigUtil: 检查文件存在失败 - $e');
      return false;
    }
  }

  // 读取配置
  static Future<Map<String, dynamic>?> loadConfig() async {
    try {
      final path = await _localPath;
      debugPrint('ConfigUtil: 尝试从 $path 读取配置');
      
      final file = File(path);
      
      if (!await file.exists()) {
        debugPrint('ConfigUtil: 配置文件不存在');
        return null;
      }
      
      final content = await file.readAsString();
      debugPrint('ConfigUtil: 读取到内容: $content');
      
      final result = jsonDecode(content);
      if (result is Map<String, dynamic>) {
        debugPrint('ConfigUtil: 解析成功');
        return result;
      } else {
        debugPrint('ConfigUtil: 配置格式不正确');
        return null;
      }
    } on FormatException catch (e) {
      debugPrint('ConfigUtil: JSON 解析错误 - $e');
      return null;
    } on FileSystemException catch (e) {
      debugPrint('ConfigUtil: 文件系统错误 - $e');
      return null;
    } catch (e, stackTrace) {
      debugPrint('ConfigUtil: 读取配置异常 - $e');
      debugPrint('ConfigUtil: 堆栈 - $stackTrace');
      return null;
    }
  }

  // 保存配置
  static Future<bool> saveConfig({
    required String username,
    required String password,
    String acid = '1',
    bool autoAcid = true,
  }) async {
    try {
      final path = await _localPath;
      debugPrint('ConfigUtil: 准备保存配置到 $path');
      
      final file = File(path);
      
      // 确保父目录存在
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        debugPrint('ConfigUtil: 创建父目录 ${parentDir.path}');
        await parentDir.create(recursive: true);
      }
      
      final config = {
        'username': username,
        'password': password,
        'acid': acid,
        'auto_acid': autoAcid,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      final jsonString = jsonEncode(config);
      debugPrint('ConfigUtil: 写入内容: $jsonString');
      
      await file.writeAsString(jsonString, flush: true);
      
      // 验证写入是否成功
      if (await file.exists()) {
        final verifyContent = await file.readAsString();
        if (verifyContent == jsonString) {
          debugPrint('ConfigUtil: 配置保存成功并已验证');
          return true;
        } else {
          debugPrint('ConfigUtil: 验证失败，内容不匹配');
          return false;
        }
      } else {
        debugPrint('ConfigUtil: 文件写入后不存在');
        return false;
      }
    } on FileSystemException catch (e) {
      debugPrint('ConfigUtil: 文件系统错误 - $e');
      return false;
    } catch (e, stackTrace) {
      debugPrint('ConfigUtil: 保存配置异常 - $e');
      debugPrint('ConfigUtil: 堆栈 - $stackTrace');
      return false;
    }
  }
  
  // 删除配置（用于测试或重置）
  static Future<bool> deleteConfig() async {
    try {
      final path = await _localPath;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('ConfigUtil: 配置已删除');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ConfigUtil: 删除配置失败 - $e');
      return false;
    }
  }
}
