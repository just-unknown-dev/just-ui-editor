// The editor's packages are this package's regular dependencies (one
// package holds the runtime and the editor), so every game resolves them.
// What must never follow: a native plugin the engine does not bring itself,
// which would ship in every game's plugin registrant. This reads the
// resolved packages (.dart_tool/package_config.json) and their pubspecs.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final configDir = Directory('.dart_tool').absolute.uri;
  final roots = <String, Uri>{
    for (final p in (config['packages'] as List).cast<Map<String, dynamic>>())
      p['name'] as String: configDir.resolve(
        (p['rootUri'] as String).endsWith('/')
            ? p['rootUri'] as String
            : '${p['rootUri']}/',
      ),
  };

  String? pubspecOf(String name) {
    final root = roots[name];
    if (root == null) return null;
    final file = File.fromUri(root.resolve('pubspec.yaml'));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  /// The names under the top-level `dependencies:` of [pubspec].
  List<String> dependenciesOf(String pubspec) {
    final lines = pubspec.replaceAll('\r\n', '\n').split('\n');
    final start = lines.indexWhere((l) => l.trimRight() == 'dependencies:');
    if (start < 0) return const [];
    return [
      for (final line
          in lines
              .skip(start + 1)
              .takeWhile(
                (l) => l.isEmpty || l.startsWith(' ') || l.startsWith('#'),
              ))
        if (RegExp(r'^  ([a-z_][a-z0-9_]*):').firstMatch(line) case final m?)
          m.group(1)!,
    ];
  }

  /// [name] and everything it depends on, as resolved here.
  Set<String> closure(String name) {
    final seen = <String>{};
    final stack = [name];
    while (stack.isNotEmpty) {
      final next = stack.removeLast();
      if (!seen.add(next)) continue;
      final pubspec = pubspecOf(next);
      if (pubspec != null) stack.addAll(dependenciesOf(pubspec));
    }
    return seen;
  }

  /// Whether [name] is a Flutter plugin with code of its own on a platform.
  bool isNativePlugin(String name) {
    final pubspec = pubspecOf(name);
    if (pubspec == null) return false;
    return RegExp(
          r'^\s+(pluginClass|ffiPlugin|dartPluginClass):',
          multiLine: true,
        ).hasMatch(pubspec) &&
        RegExp(r'^  plugin:', multiLine: true).hasMatch(pubspec);
  }

  test('the editor core brings no native plugin the engine does not', () {
    final engine = {
      for (final p in closure('just_game_engine'))
        if (isNativePlugin(p)) p,
    };
    final editor = {
      for (final p in closure('just_editor_core'))
        if (isNativePlugin(p)) p,
    };

    expect(engine, isNotEmpty, reason: 'the scan found the engine\'s');
    expect(editor.difference(engine), isEmpty);
  });

  test('the scan reads a pubspec the way pub writes one', () {
    expect(
      dependenciesOf('''
name: x
dependencies:
  flutter:
    sdk: flutter
  just_game_engine: ^2.0.0
  # a comment
  meta: ^1.16.0

dev_dependencies:
  flutter_test:
    sdk: flutter
'''),
      ['flutter', 'just_game_engine', 'meta'],
    );
  });
}
