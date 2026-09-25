import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:LinkUp/utils/LogUtil.dart';
import 'package:LinkUp/utils/SecretStore.dart';

const String defaultAuthServer = '10.129.1.1';
const String defaultAcid = '1';

/// 认证配置的不可变内存表示。
///
/// 密码只在授权的运行时对象中存在，不会被 [toJson] 写入普通配置文件。
class AuthConfig {
  const AuthConfig({
    required this.username,
    required this.password,
    required this.acid,
    required this.autoAcid,
    required this.authServer,
    required this.userType,
    this.hasExplicitAcid = true,
    this.createdAt,
  });

  final String username;
  final String password;
  final String acid;
  final bool autoAcid;
  final String authServer;
  final String userType;

  /// 运行时 [acid] 会使用默认值，但该标记保留空值是否明确可用。
  final bool hasExplicitAcid;
  final String? createdAt;

  String get authenticatedUsername =>
      userType.isEmpty ? username : '$username@$userType';

  AuthConfig copyWith({
    String? username,
    String? password,
    String? acid,
    bool? autoAcid,
    String? authServer,
    String? userType,
    bool? hasExplicitAcid,
    String? createdAt,
  }) {
    return AuthConfig(
      username: username ?? this.username,
      password: password ?? this.password,
      acid: acid ?? this.acid,
      autoAcid: autoAcid ?? this.autoAcid,
      authServer: authServer ?? this.authServer,
      userType: userType ?? this.userType,
      hasExplicitAcid: hasExplicitAcid ?? this.hasExplicitAcid,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 构造普通 JSON 配置；这里明确不包含密码。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'username': username,
      'acid': hasExplicitAcid ? acid : '',
      'auto_acid': autoAcid,
      'auth_server': authServer,
      'user_type': userType,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory AuthConfig.fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) {
    final rawAcid = _stringValue(json['acid'], '');
    return AuthConfig(
      username: _stringValue(json['username']),
      password: password,
      acid: normalizeAcid(rawAcid),
      hasExplicitAcid: rawAcid.trim().isNotEmpty,
      autoAcid: _boolValue(json['auto_acid'], true),
      authServer: normalizeAuthServer(_stringValue(json['auth_server'])),
      userType: _stringValue(json['user_type']),
      createdAt: _stringValue(json['created_at'], ''),
    );
  }
}

/// 对普通配置的目标字段更新。
///
/// 字符串字段遵循 `null=保留、空字符串=清空、非空=覆盖`。认证服务器在
/// 写入前会归一化为明确默认值，避免空字符串成为运行地址。
class ConfigUpdate {
  const ConfigUpdate({
    this.username,
    this.password,
    this.acid,
    this.autoAcid,
    this.authServer,
    this.userType,
  });

  final String? username;
  final String? password;
  final String? acid;
  final bool? autoAcid;
  final String? authServer;
  final String? userType;

  bool get hasChanges =>
      username != null ||
      password != null ||
      acid != null ||
      autoAcid != null ||
      authServer != null ||
      userType != null;
}

/// 不可恢复的凭据值不会被放入异常文本，避免密码从错误路径泄漏。
class ConfigStorageException implements Exception {
  const ConfigStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ConfigFormatException extends ConfigStorageException {
  const ConfigFormatException() : super('配置文件格式无效');
}

class ConfigMigrationException extends ConfigStorageException {
  const ConfigMigrationException() : super('配置密码迁移失败，请重试');
}

class ConfigSecretException extends ConfigStorageException {
  const ConfigSecretException() : super('秘密存储操作失败，请重试');

  const ConfigSecretException.missing() : super('秘密存储中缺少密码，请重新配置');
}

typedef ConfigPathProvider = Future<String> Function();

/// 普通配置文件的最小存储接口，便于验证写入失败和恢复语义。
abstract interface class ConfigFileStore {
  Future<String?> read();

  Future<void> write(String content);

  Future<void> delete();

  Future<bool> exists();
}

/// 使用同目录临时文件替换目标文件，避免写入中断破坏旧配置。
class FileConfigFileStore implements ConfigFileStore {
  FileConfigFileStore(this.pathProvider);

  final ConfigPathProvider pathProvider;

  Future<File> _file() async => File(await pathProvider());

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String content) async {
    final file = await _file();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temporaryFile = File('${file.path}.tmp');
    try {
      await temporaryFile.writeAsString(content, flush: true);
      if (!await temporaryFile.exists() ||
          await temporaryFile.readAsString() != content) {
        throw const ConfigStorageException('配置文件写入验证失败');
      }

      await temporaryFile.rename(file.path);
      if (!await file.exists() || await file.readAsString() != content) {
        throw const ConfigStorageException('配置文件写入验证失败');
      }
    } finally {
      try {
        if (await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } catch (_) {
        // 清理失败不能覆盖原始写入结果。
      }
    }
  }

  @override
  Future<void> delete() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists() async => (await _file()).exists();
}

/// 普通配置和密码秘密的唯一仓库入口。
///
/// 文件存储和 [SecretStore] 都可注入，因此迁移、更新和失败恢复可以在
/// 不依赖 Android 插件的单元测试中验证。
class ConfigRepository {
  ConfigRepository({
    required ConfigPathProvider pathProvider,
    required this.secretStore,
    ConfigFileStore? fileStore,
  }) : fileStore = fileStore ?? FileConfigFileStore(pathProvider);

  static const String passwordSecretKey = 'campus_password';

  final ConfigFileStore fileStore;
  final SecretStore secretStore;

  Future<void> _operationQueue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>?> _readRawUnlocked() async {
    final content = await fileStore.read();
    if (content == null) return null;

    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const ConfigFormatException();
      }
      return Map<String, dynamic>.from(decoded);
    } on ConfigStorageException {
      rethrow;
    } on FormatException {
      throw const ConfigFormatException();
    } on TypeError {
      throw const ConfigFormatException();
    }
  }

  Future<void> _writeJsonUnlocked(Map<String, dynamic> value) async {
    await fileStore.write(jsonEncode(value));
  }

  Future<void> _writeSecretUnlocked(String password) async {
    try {
      await secretStore.write(passwordSecretKey, password);
      final verified = await secretStore.read(passwordSecretKey);
      if (verified != password) {
        throw const ConfigSecretException();
      }
    } on ConfigSecretException {
      rethrow;
    } catch (_) {
      throw const ConfigSecretException();
    }
  }

  Future<AuthConfig?> _loadUnlocked() async {
    final raw = await _readRawUnlocked();
    if (raw == null) return null;

    String password;
    if (raw.containsKey('password')) {
      final legacyPassword = raw['password'];
      if (legacyPassword is! String) {
        throw const ConfigMigrationException();
      }

      try {
        await _writeSecretUnlocked(legacyPassword);
      } catch (_) {
        throw const ConfigMigrationException();
      }

      final sanitized = Map<String, dynamic>.from(raw)..remove('password');
      try {
        await _writeJsonUnlocked(sanitized);
      } catch (_) {
        throw const ConfigMigrationException();
      }
      password = legacyPassword;
    } else {
      try {
        final storedPassword = await secretStore.read(passwordSecretKey);
        if (storedPassword == null) {
          throw const ConfigSecretException.missing();
        }
        password = storedPassword;
      } on ConfigSecretException {
        rethrow;
      } catch (_) {
        throw const ConfigSecretException();
      }
    }

    return AuthConfig.fromJson(raw, password: password);
  }

  AuthConfig _normalize(AuthConfig config) {
    return config.copyWith(
      username: config.username.trim(),
      acid: normalizeAcid(config.acid),
      authServer: normalizeAuthServer(config.authServer),
      userType: config.userType.trim(),
    );
  }

  bool _isValid(AuthConfig config) =>
      config.username.isNotEmpty && config.password.isNotEmpty;

  Future<AuthConfig?> _recoverWithPasswordUnlocked(String password) async {
    if (password.isEmpty) return null;
    final raw = await _readRawUnlocked();
    if (raw == null) return null;

    await _writeSecretUnlocked(password);
    final sanitized = Map<String, dynamic>.from(raw)..remove('password');
    await _writeJsonUnlocked(sanitized);
    return AuthConfig.fromJson(sanitized, password: password);
  }

  /// 读取组合后的认证配置，并在首次读取时迁移旧明文密码。
  Future<AuthConfig?> load() => _enqueue(() async {
    try {
      return await _loadUnlocked();
    } on ConfigStorageException {
      rethrow;
    } catch (_) {
      throw const ConfigStorageException('读取配置失败，请重试');
    }
  });

  /// 保存一份完整的初始配置。密码先写入秘密存储，普通 JSON 永远不含密码。
  Future<bool> save(AuthConfig config) => _enqueue(() async {
    final normalized = _normalize(config);
    if (!_isValid(normalized)) return false;

    try {
      await _writeSecretUnlocked(normalized.password);
      await _writeJsonUnlocked(normalized.toJson());
      await LogUtil.info('认证配置已保存');
      return true;
    } catch (_) {
      await LogUtil.warning('认证配置保存失败');
      return false;
    }
  });

  /// 只更新传入的目标字段；未传入的字段保持原值。
  ///
  /// [canPersist] 在仓库操作队列内、实际写入前检查世代条件；认证流程用它
  /// 阻止网络环境变化后的旧 ACID 落盘。
  Future<bool> update(
    ConfigUpdate update, {
    bool Function()? canPersist,
  }) => _enqueue(() async {
    if (!update.hasChanges) return true;

    try {
      AuthConfig? current;
      try {
        current = await _loadUnlocked();
      } on ConfigSecretException {
        current = await _recoverWithPasswordUnlocked(update.password ?? '');
      } on ConfigMigrationException {
        current = await _recoverWithPasswordUnlocked(update.password ?? '');
      }
      if (current == null) return false;

      if (update.username != null && update.username!.trim().isEmpty) {
        return false;
      }
      if (update.password != null && update.password!.isEmpty) {
        return false;
      }
      if (canPersist != null && !canPersist()) return false;

      if (update.password != null) {
        await _writeSecretUnlocked(update.password!);
      }

      final hasFileChange =
          update.username != null ||
          update.acid != null ||
          update.autoAcid != null ||
          update.authServer != null ||
          update.userType != null;
      if (!hasFileChange) return true;

      final updated = current.copyWith(
        username: update.username?.trim(),
        acid: update.acid == null ? null : normalizeAcid(update.acid!),
        hasExplicitAcid: update.acid?.trim().isNotEmpty,
        autoAcid: update.autoAcid,
        authServer: update.authServer == null
            ? null
            : normalizeAuthServer(update.authServer),
        userType: update.userType?.trim(),
      );
      if (canPersist != null && !canPersist()) return false;
      await _writeJsonUnlocked(updated.toJson());
      return true;
    } on ConfigMigrationException {
      rethrow;
    } catch (_) {
      await LogUtil.warning('认证配置更新失败');
      return false;
    }
  });

  /// 删除普通配置和密码秘密；任一操作失败都返回 false，允许再次调用。
  Future<bool> delete() => _enqueue(() async {
    var succeeded = true;

    try {
      await fileStore.delete();
    } catch (_) {
      succeeded = false;
    }

    try {
      await secretStore.deleteAll();
      if (await secretStore.read(passwordSecretKey) != null) {
        succeeded = false;
      }
    } catch (_) {
      succeeded = false;
    }

    if (succeeded) {
      await LogUtil.info('认证配置已删除');
    } else {
      await LogUtil.warning('认证配置删除失败，可重试');
    }
    return succeeded;
  });

  Future<bool> exists() => _enqueue(() async {
    try {
      return await fileStore.exists();
    } catch (_) {
      await LogUtil.warning('检查配置文件失败');
      return false;
    }
  });
}

/// 生产环境的 [ConfigRepository] 入口。
class ConfigUtil {
  ConfigUtil._();

  static final ConfigRepository _repository = ConfigRepository(
    pathProvider: _defaultPath,
    secretStore: FlutterSecureStorageSecretStore(),
  );

  static Future<AuthConfig?> loadConfig() => _repository.load();

  static Future<bool> saveConfig(AuthConfig config) => _repository.save(config);

  static Future<bool> updateConfig(
    ConfigUpdate update, {
    bool Function()? canPersist,
  }) => _repository.update(update, canPersist: canPersist);

  static Future<bool> deleteConfig() => _repository.delete();

  static Future<bool> configExists() => _repository.exists();

  static Future<String> _defaultPath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/linkup_config.json';
    } catch (_) {
      await LogUtil.warning('获取配置文件路径失败');
      rethrow;
    }
  }
}

String normalizeAuthServer(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? defaultAuthServer : trimmed;
}

String normalizeAcid(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? defaultAcid : trimmed;
}

String _stringValue(Object? value, [String fallback = '']) {
  return value is String ? value : fallback;
}

bool _boolValue(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}
