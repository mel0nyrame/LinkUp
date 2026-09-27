import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 日志工具类 - 将日志写入文件
class LogUtil {
  static File? _logFile;
  static bool _initialized = false;
  static Future<void> _writes = Future<void>.value();
  static const int _maxBytes = 1024 * 1024;
  static const int _retainedBytes = 512 * 1024;

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
    } catch (_) {
      // 日志不可用时不把可能含凭据的底层异常转发到标准输出。
    }
  }

  /// 写入日志文件
  static Future<void> _writeToFile(String content) async {
    _writes = _writes.then((_) async {
      final file = _logFile;
      if (file == null) return;
      try {
        await file.writeAsString(
          _redact(content),
          mode: FileMode.append,
          encoding: utf8,
        );
        if (await file.length() > _maxBytes) {
          final bytes = await file.readAsBytes();
          final tail = bytes.sublist(bytes.length - _retainedBytes);
          await file.writeAsString(
            utf8.decode(tail, allowMalformed: true),
            encoding: utf8,
          );
        }
      } catch (_) {
        // 日志失败不能使认证失败，也不能把原始内容转发到标准输出。
      }
    });
    await _writes;
  }

  static String _redact(String value) {
    final withoutUrlQueries = value.replaceAll(
      RegExp(r'https?://[^\s?]+\?[^\s]+', caseSensitive: false),
      '[URL_QUERY_REDACTED]',
    );
    final withoutJsonSecrets = withoutUrlQueries.replaceAllMapped(
      RegExp(
        r'("(?:password|passwd|username|challenge|chksum|token|sign|info|authorization)"\s*:\s*)"(?:\\.|[^"\\])*"',
        caseSensitive: false,
      ),
      (match) => '${match[1]}"[REDACTED]"',
    );
    final secrets = RegExp(
      r'(password|passwd|username|challenge|chksum|token|sign|info|authorization)\s*[:=]\s*([^&\s,}\]]+)',
      caseSensitive: false,
    );
    return withoutJsonSecrets.replaceAllMapped(
      secrets,
      (match) => '${match[1]}=[REDACTED]',
    );
  }

  /// 记录错误日志
  static Future<void> error(
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) async {
    await init();

    final buffer = StringBuffer();
    buffer.writeln('[ERROR] ${DateTime.now()}');
    buffer.writeln(message);

    if (error != null) {
      buffer.writeln('异常类型: ${error.runtimeType}');
    }

    if (stackTrace != null) {
      buffer.writeln('堆栈:\n$stackTrace');
    }

    buffer.writeln('');

    await _writeToFile(buffer.toString());
  }

  /// 记录信息日志
  static Future<void> info(String message) async {
    await init();

    final log = '[INFO] ${DateTime.now()} - $message\n';
    await _writeToFile(log);
  }

  /// 记录警告日志
  static Future<void> warning(String message) async {
    await init();

    final log = '[WARN] ${DateTime.now()} - $message\n';
    await _writeToFile(log);
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
      await _writes;
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('', encoding: utf8);
      }
    } catch (_) {
      // 清理失败不泄漏底层异常。
    }
  }

  /// 读取日志内容（使用 UTF-8 编码，允许无效字节）
  static Future<String> readLog() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        // 使用 allowMalformed: true 允许读取包含无效 UTF-8 字节的文件
        final bytes = await _logFile!.readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      }
      return '';
    } catch (_) {
      return '读取日志失败';
    }
  }

  /// 测试结束时释放文件与队列的静态状态。
  static Future<void> resetForTest() async {
    await _writes;
    _logFile = null;
    _initialized = false;
    _writes = Future<void>.value();
  }
}
