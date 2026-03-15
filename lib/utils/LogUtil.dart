import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 日志工具类 - 将日志写入文件
class LogUtil {
  static File? _logFile;
  static bool _initialized = false;

  /// 初始化日志文件
  static Future<void> init() async {
    if (_initialized) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logPath = '${directory.path}/error.log';
      _logFile = File(logPath);
      
      // 如果日志文件不存在，创建并写入头部
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
        await _writeToFile('====== LinkUp 错误日志 ======\n');
        await _writeToFile('启动时间: ${DateTime.now()}\n');
        await _writeToFile('============================\n\n');
      } else {
        // 追加新会话标记
        await _writeToFile('\n====== 新会话 ${DateTime.now()} ======\n');
      }
      
      _initialized = true;
    } catch (e) {
      // 初始化失败时回退到 print
      print('日志初始化失败: $e');
    }
  }

  /// 写入日志文件
  static Future<void> _writeToFile(String content) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString(content, mode: FileMode.append);
      }
    } catch (e) {
      print('写入日志失败: $e');
    }
  }

  /// 记录错误日志
  static Future<void> error(String message, [dynamic error, StackTrace? stackTrace]) async {
    await init();
    
    final buffer = StringBuffer();
    buffer.writeln('[ERROR] ${DateTime.now()}');
    buffer.writeln(message);
    
    if (error != null) {
      buffer.writeln('异常: $error');
    }
    
    if (stackTrace != null) {
      buffer.writeln('堆栈:\n$stackTrace');
    }
    
    buffer.writeln('');
    
    await _writeToFile(buffer.toString());
    
    // 同时输出到控制台（调试用）
    print('[ERROR] $message${error != null ? ': $error' : ''}');
  }

  /// 记录信息日志
  static Future<void> info(String message) async {
    await init();
    
    final log = '[INFO] ${DateTime.now()} - $message\n';
    await _writeToFile(log);
    
    print('[INFO] $message');
  }

  /// 记录警告日志
  static Future<void> warning(String message) async {
    await init();
    
    final log = '[WARN] ${DateTime.now()} - $message\n';
    await _writeToFile(log);
    
    print('[WARN] $message');
  }

  /// 获取日志文件路径
  static Future<String?> getLogFilePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/error.log';
    } catch (e) {
      return null;
    }
  }

  /// 清空日志文件
  static Future<void> clear() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      print('清空日志失败: $e');
    }
  }

  /// 读取日志内容
  static Future<String> readLog() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
      return '';
    } catch (e) {
      return '读取日志失败: $e';
    }
  }
}
