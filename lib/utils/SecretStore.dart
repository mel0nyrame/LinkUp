import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 只保存敏感值的最小存储接口。
///
/// 生产实现使用 Android Keystore 支持的加密存储；测试和其他平台可以提供
/// 自己的实现，而不需要让配置仓库依赖具体插件。
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// 清除当前命名空间中的全部秘密，包括插件迁移留下的备份密文。
  Future<void> deleteAll();
}

/// LinkUp 的 Android 秘密存储实现。
class FlutterSecureStorageSecretStore implements SecretStore {
  static const _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
    storageNamespace: 'linkup_auth',
  );

  final FlutterSecureStorage _storage;

  FlutterSecureStorageSecretStore()
    : _storage = const FlutterSecureStorage(aOptions: _androidOptions);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
