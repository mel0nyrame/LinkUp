import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:LinkUp/utils/ConfigUtil.dart';
import 'package:LinkUp/utils/SecretStore.dart';

String _fixtureValue(String label) => 'fixture-$label-value';

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};
  final Map<String, String> backupValues = <String, String>{};
  Object? readError;
  Object? writeError;
  Object? deleteError;
  Object? deleteAllError;

  @override
  Future<String?> read(String key) async {
    if (readError != null) throw readError!;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeError != null) throw writeError!;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (deleteError != null) throw deleteError!;
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    if (deleteAllError != null) throw deleteAllError!;
    values.clear();
    backupValues.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _FakeSecretStore secretStore;
  late ConfigRepository repository;
  late File configFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('linkup-config-test-');
    secretStore = _FakeSecretStore();
    configFile = File('${directory.path}/linkup_config.json');
    repository = ConfigRepository(
      pathProvider: () async => configFile.path,
      secretStore: secretStore,
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('首次保存显式写入全部普通配置并将密码保存到秘密存储', () async {
    final password = _fixtureValue('initial');

    final saved = await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '5',
        autoAcid: false,
        authServer: '',
        userType: '',
      ),
    );

    expect(saved, isTrue);
    final raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw['username'], 'fixture-user');
    expect(raw['acid'], '5');
    expect(raw['auto_acid'], isFalse);
    expect(raw['auth_server'], '10.129.1.1');
    expect(raw['user_type'], '');
    expect(raw.containsKey('password'), isFalse);
    expect(
      await secretStore.read(ConfigRepository.passwordSecretKey),
      isNotNull,
    );

    final loaded = await repository.load();
    expect(loaded?.username, 'fixture-user');
    expect(loaded?.password, isNotEmpty);
    expect(loaded?.authenticatedUsername, 'fixture-user');
  });

  test('user_type 的空字符串明确清空并影响认证用户名', () async {
    final password = _fixtureValue('user-type');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '1',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: 'cmcc',
      ),
    );

    expect(await repository.update(const ConfigUpdate(userType: '')), isTrue);

    final loaded = await repository.load();
    expect(loaded?.userType, isEmpty);
    expect(loaded?.authenticatedUsername, 'fixture-user');
  });

  test('局部更新不会覆盖未提供的认证配置', () async {
    final password = _fixtureValue('partial');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '5',
        autoAcid: false,
        authServer: '10.129.1.1',
        userType: 'cmcc',
      ),
    );

    await repository.update(const ConfigUpdate(authServer: '10.129.1.2'));
    await repository.update(const ConfigUpdate(authServer: ''));
    await repository.update(const ConfigUpdate(acid: '9'));
    await repository.update(const ConfigUpdate(autoAcid: true));

    final loaded = await repository.load();
    expect(loaded?.username, 'fixture-user');
    expect(loaded?.password, isNotEmpty);
    expect(loaded?.authServer, defaultAuthServer);
    expect(loaded?.acid, '9');
    expect(loaded?.autoAcid, isTrue);
    expect(loaded?.userType, 'cmcc');
  });

  test('空 ACID 保留为不可用状态而不伪造成已保存候选', () async {
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: _fixtureValue('empty-acid'),
        acid: '',
        hasExplicitAcid: false,
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );

    final loaded = await repository.load();
    final raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

    expect(loaded?.acid, '143');
    expect(loaded?.hasExplicitAcid, isFalse);
    expect(raw['acid'], isEmpty);
  });

  test('并发的目标字段更新不会互相覆盖', () async {
    final password = _fixtureValue('concurrent');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '1',
        autoAcid: false,
        authServer: '10.129.1.1',
        userType: 'cmcc',
      ),
    );

    final results = await Future.wait(<Future<bool>>[
      repository.update(const ConfigUpdate(acid: '9')),
      repository.update(const ConfigUpdate(authServer: '10.129.1.2')),
    ]);

    expect(results, everyElement(isTrue));
    final loaded = await repository.load();
    expect(loaded?.acid, '9');
    expect(loaded?.authServer, '10.129.1.2');
    expect(loaded?.username, 'fixture-user');
    expect(loaded?.userType, 'cmcc');
  });

  test('旧配置迁移先验证秘密写入再移除普通 password 字段', () async {
    final password = _fixtureValue('migration');
    await configFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'username': 'fixture-user',
        'password': password,
        'acid': '7',
        'auto_acid': true,
        'auth_server': '10.129.1.1',
        'user_type': 'cmcc',
        'created_at': 'fixture-time',
      }),
    );

    final loaded = await repository.load();
    final raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;

    expect(loaded?.username, 'fixture-user');
    expect(loaded?.password, isNotEmpty);
    expect(raw.containsKey('password'), isFalse);
    expect(
      await secretStore.read(ConfigRepository.passwordSecretKey),
      isNotNull,
    );
  });

  test('迁移写入失败时保留旧配置并返回可恢复错误', () async {
    final password = _fixtureValue('migration-failure');
    await configFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'username': 'fixture-user',
        'password': password,
        'acid': '1',
        'auto_acid': true,
        'auth_server': '10.129.1.1',
        'user_type': '',
      }),
    );
    secretStore.writeError = StateError('secret write unavailable');

    await expectLater(
      repository.load(),
      throwsA(isA<ConfigMigrationException>()),
    );

    final raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw['password'], isNotNull);
    expect(await configFile.exists(), isTrue);
  });

  test('迁移清理 JSON 写入失败时保留旧文件并可重试', () async {
    final password = _fixtureValue('json-write-failure');
    await configFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'username': 'fixture-user',
        'password': password,
        'acid': '1',
        'auto_acid': true,
        'auth_server': '10.129.1.1',
        'user_type': '',
      }),
    );
    final temporaryPath = '${configFile.path}.tmp';
    await Directory(temporaryPath).create();

    await expectLater(
      repository.load(),
      throwsA(isA<ConfigMigrationException>()),
    );

    var raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw['password'], isNotNull);
    expect(await configFile.exists(), isTrue);

    await Directory(temporaryPath).delete();
    expect(await repository.load(), isNotNull);
    raw = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw.containsKey('password'), isFalse);
  });

  test('迁移验证失败时保留旧配置，恢复后仍可重试', () async {
    final password = _fixtureValue('verification-failure');
    await configFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'username': 'fixture-user',
        'password': password,
        'acid': '1',
        'auto_acid': true,
        'auth_server': '10.129.1.1',
        'user_type': '',
      }),
    );
    secretStore.readError = StateError('secret read unavailable');

    await expectLater(
      repository.load(),
      throwsA(isA<ConfigMigrationException>()),
    );
    var raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw['password'], isNotNull);

    secretStore.readError = null;
    expect(await repository.load(), isNotNull);
    raw = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw.containsKey('password'), isFalse);
  });

  test('秘密丢失时可通过重新提交密码恢复配置', () async {
    final password = _fixtureValue('recover');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '1',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    secretStore.values.clear();

    expect(
      await repository.update(
        ConfigUpdate(password: _fixtureValue('replacement')),
      ),
      isTrue,
    );
    expect(
      await secretStore.read(ConfigRepository.passwordSecretKey),
      isNotNull,
    );
    final raw =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(raw.containsKey('password'), isFalse);
  });

  test('修改密码只更新秘密存储', () async {
    final oldPassword = _fixtureValue('old');
    final newPassword = _fixtureValue('new');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: oldPassword,
        acid: '1',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );
    final before = await configFile.readAsString();

    expect(
      await repository.update(ConfigUpdate(password: newPassword)),
      isTrue,
    );

    expect(await configFile.readAsString(), before);
    final current = await secretStore.read(ConfigRepository.passwordSecretKey);
    expect(current, isNotNull);
    expect(current == oldPassword, isFalse);
  });

  test('删除配置会同时删除普通配置和秘密并可重试', () async {
    final password = _fixtureValue('delete');
    await repository.save(
      AuthConfig(
        username: 'fixture-user',
        password: password,
        acid: '1',
        autoAcid: true,
        authServer: '10.129.1.1',
        userType: '',
      ),
    );

    secretStore.backupValues['${ConfigRepository.passwordSecretKey}_BACKUP'] =
        _fixtureValue('delete-backup');
    secretStore.deleteAllError = StateError('secret delete unavailable');
    expect(await repository.delete(), isFalse);
    expect(
      await secretStore.read(ConfigRepository.passwordSecretKey),
      isNotNull,
    );
    expect(secretStore.backupValues, isNotEmpty);

    secretStore.deleteAllError = null;
    expect(await repository.delete(), isTrue);
    expect(await configFile.exists(), isFalse);
    expect(await secretStore.read(ConfigRepository.passwordSecretKey), isNull);
    expect(secretStore.backupValues, isEmpty);
  });
}
