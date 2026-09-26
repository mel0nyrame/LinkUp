import 'dart:convert';
import 'dart:io';

void main() {
  final source = File(
    'android/app/src/main/kotlin/com/mel0ny/linkup/AuthRuntimeBridge.kt',
  ).readAsStringSync();
  final start = source.indexOf('// BEGIN runtime contract');
  final end = source.indexOf('// END runtime contract');
  if (start < 0 || end <= start) {
    throw StateError('AuthRuntimeBridge 缺少运行时契约区块');
  }

  final lines = <String>[
    '// 由 tool/generate_runtime_contract.dart 从 AuthRuntimeBridge.kt 生成。',
    '// 修改 Kotlin 契约区块后重新生成，勿手改。',
    'abstract final class RuntimeContract {',
  ];
  final declarations = RegExp(r'const val ([A-Z_]+) = ("[^"]*"|true|false)')
      .allMatches(source.substring(start, end));
  for (final declaration in declarations) {
    final name = declaration.group(1)!;
    final value = jsonDecode(declaration.group(2)!);
    final words = name.toLowerCase().split('_');
    final dartName =
        words.first +
        words
            .skip(1)
            .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
            .join();
    final type = value is bool ? 'bool' : 'String';
    lines.add('  static const $type $dartName = ${jsonEncode(value)};');
  }
  lines.add('}');
  final output = File('lib/utils/RuntimeContract.g.dart');
  output.writeAsStringSync('${lines.join('\n')}\n');
  final format = Process.runSync(Platform.resolvedExecutable, [
    'format',
    output.path,
  ]);
  if (format.exitCode != 0) throw StateError(format.stderr);
}
