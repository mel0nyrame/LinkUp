import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:LinkUp/utils/SystemSettingsUtil.dart';

/// 开机自启依赖的偏好事实。
///
/// `BootReceiver` 在 Dart isolate 启动前就要判定，所以这两个偏好和“配置存在”
/// 标记都必须落在原生可读的共享偏好上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('保留后台运行默认开启，开机自启默认关闭', () {
    expect(SystemSettingsUtil.getKeepAlive(), isTrue);
    expect(SystemSettingsUtil.getAutoStart(), isFalse);
  });

  test('配置存在标记跟随保存与删除，开机侧读到同一份事实', () async {
    await SystemSettingsUtil.setAccountConfigured(true);
    expect(await _readKey('account_configured'), isTrue);

    await SystemSettingsUtil.setAccountConfigured(false);
    expect(await _readKey('account_configured'), isFalse);
  });
}

/// 读取裸键。
///
/// `flutter.` 前缀和 `FlutterSharedPreferences` 桶名由 shared_preferences 的
/// Android 实现决定，测试用的内存实现不带前缀；前缀的一致性由
/// `android_runtime_contract_test.dart` 对两侧源码断言。
Future<Object?> _readKey(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.get(key);
}
