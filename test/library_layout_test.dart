// How lib/ is laid out, checked from the directives of every file (the
// same rules as just_game_engine's library_layout_test; the layout and the
// layers are in CONTRIBUTING.md, "Layout"):
// - every file under a top-level folder of lib/src is exported by a public
//   library, through its folder's barrel, or is internal: each of its public
//   declarations is `@internal`;
// - only a folder's barrel or a public library exports, and a barrel only
//   its own folder; a library that holds parts is not a barrel; the public
//   libraries export barrels whole;
// - no public library exports an `@internal` declaration, and a barrel
//   hides only `@internal` ones;
// - no file imports a barrel that leads back to it;
// - no import loop crosses from one feature (a top-level folder of lib/src)
//   to another, and no feature imports one in a layer above its own;
// - inside `editor/`, each part imports only its own or those below.
// And this package's own: the game's library never reaches the editor, the
// runtime imports nothing editor-side or native, no name is exported by
// both public libraries, and just_store.json agrees with the pubspec.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter_test/flutter_test.dart';

/// The public libraries, under lib/: what a game imports, and the editor.
const _public = ['just_ui_editor.dart', 'editor.dart'];

/// What a game imports: the runtime, never the editor.
const _gameLibrary = 'just_ui_editor.dart';

/// Files no public library exports and that are not `@internal` either,
/// with why.
const Map<String, String> _internalByList = {};

/// Files that export without being a barrel, with why. Each may export only
/// files of its own folder.
const Map<String, String> _exportSelectors = {};

/// The features — the top-level folders of lib/src — in layers, bottom to
/// top. A feature imports features in its own layer or below, never above;
/// within a layer imports go one way only (no loops). A new top-level
/// folder takes its place here.
const _layers = [
  // Leaves: text (styles, rich text, icons, painting, fonts) and bindings
  // (what a screen reads from the game and does to it).
  ['text', 'bindings'],
  // Themes, and the look of the level's own text.
  ['theme'],
  // How screens are arranged: canvases, slots, containers, panels.
  ['layout'],
  // The elements a screen holds, the game's widgets, the text system.
  ['controls'],
  // Text and buttons in the level: painters, the pointer.
  ['world'],
  // How every component is saved, and the renames.
  ['serialization'],
  // Screens as assets and widgets, and the entry points for a game.
  ['screens'],
  // The Interface editor. Nothing below imports it.
  ['editor'],
];

/// The parts of `editor/`, bottom to top; the module and the workspace
/// (the folder's own files) over them all.
const _editorParts = [
  ['project'],
  ['document'],
  ['geometry'],
  ['session'],
  ['inspector'],
  ['canvas'],
  ['panels'],
  [''],
];

/// What no file outside `src/editor/` may name: the editor, the editor's
/// packages, and the native-only libraries (the runtime is web-safe).
const _runtimeMayNot = [
  'package:just_editor_core/',
  'package:just_game_engine_editor/',
  'package:just_signals/',
  'package:just_ui_editor/editor.dart',
  'dart:io',
  'dart:html',
];

final _directive = RegExp(
  r'^[ \t]*(import|export|part[ \t]+of|part)\b([^;]*);',
  multiLine: true,
);
final _uri = RegExp(r"'([^']+)'");

final _hide = RegExp(r'\bhide\s+([\w\s,]+)');

/// One `import`, `export`, `part` or `part of` of a file, resolved.
final class _Directive {
  _Directive(this.kind, this.uri, this.target, this.hidden);

  final String kind;
  final String uri;

  /// The file it names, relative to lib/; null for another package's.
  final String? target;

  /// The names its `hide` leaves out.
  final Set<String> hidden;
}

/// A file under lib/: its path from lib/, text and directives.
final class _File {
  _File(this.path, this.text, this.directives);

  final String path;
  final String text;
  final List<_Directive> directives;

  Iterable<_Directive> of(String kind) =>
      directives.where((d) => d.kind == kind);

  /// The library it is part of, or itself.
  String get library =>
      of('part of').map((d) => d.target).nonNulls.firstOrNull ?? path;

  bool get holdsParts => of('part').isNotEmpty;

  /// A top-level folder's barrel: `src/<folder>/<folder>.dart`.
  bool get isBarrel {
    final parts = path.split('/');
    return parts.length == 3 &&
        parts[0] == 'src' &&
        parts[2] == '${parts[1]}.dart';
  }

  bool get isPublic => _public.contains(path);
}

String? _resolve(String from, String uri) {
  if (uri.startsWith('package:just_ui_editor/')) {
    return uri.substring('package:just_ui_editor/'.length);
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final segments = from.split('/')..removeLast();
  for (final s in uri.split('/')) {
    if (s == '..') {
      segments.removeLast();
    } else if (s != '.') {
      segments.add(s);
    }
  }
  return segments.join('/');
}

/// Every Dart file under lib/, by path from lib/.
Map<String, _File> _readLib() {
  final root = Directory('lib');
  final files = <String, _File>{};
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final path = f.path.substring(root.path.length + 1).replaceAll(r'\', '/');
    var text = f.readAsStringSync().replaceAll('\r\n', '\n');
    if (text.startsWith('﻿')) text = text.substring(1);
    files[path] = _File(path, text, [
      for (final m in _directive.allMatches(text))
        for (final u in _uri.allMatches(m.group(2)!))
          _Directive(
            m.group(1)!.replaceAll(RegExp(r'\s+'), ' '),
            u.group(1)!,
            _resolve(path, u.group(1)!),
            {
              for (final h in _hide.allMatches(m.group(2)!))
                for (final name in h.group(1)!.split(','))
                  if (name.trim().isNotEmpty) name.trim(),
            },
          ),
    ]);
  }
  return files;
}

/// What [from] exports, itself included, following exports onward.
Set<String> _exportedFrom(Map<String, _File> files, Iterable<String> from) {
  final seen = <String>{};
  final stack = [...from];
  while (stack.isNotEmpty) {
    final path = stack.removeLast();
    if (!seen.add(path)) continue;
    for (final d in files[path]?.of('export') ?? const <_Directive>[]) {
      if (d.target != null) stack.add(d.target!);
    }
  }
  return seen;
}

final _typeDeclaration = RegExp(
  r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*'
  r'(?:class|mixin|enum|typedef|extension\s+type|extension)\s+([A-Za-z_]\w*)',
);

/// The public top-level declarations of [text]: their line and name, and
/// whether `@internal` is among their annotations.
List<({int line, String name, bool internal})> _publicDeclarations(
  String text,
) {
  final lines = text.split('\n');
  final found = <({int line, String name, bool internal})>[];
  var depth = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (depth == 0 &&
        line.isNotEmpty &&
        !line.startsWith(RegExp(r'[\s/*@})\]]')) &&
        !line.startsWith(RegExp(r'(import|export|part|library)\b')) &&
        !line.startsWith(RegExp(r'extension\s+on\b'))) {
      final type = _typeDeclaration.firstMatch(line);
      String? name;
      if (type != null) {
        name = type.group(1);
      } else {
        // A function or variable: the last name before its parameters or
        // value, past any type arguments of its own.
        final head = line
            .split(RegExp(r'[(=;{]'))
            .first
            .trim()
            .replaceFirst(RegExp(r'<[^<>]*>$'), '');
        name = RegExp(r'[A-Za-z_]\w*').allMatches(head).lastOrNull?.group(0);
      }
      if (name != null && !name.startsWith('_')) {
        var internal = false;
        for (var j = i - 1; j >= 0; j--) {
          final above = lines[j].trim();
          if (above.startsWith('@')) {
            internal |= RegExp(r'^@internal\b').hasMatch(above);
          } else if (!above.startsWith('///')) {
            break;
          }
        }
        found.add((line: i + 1, name: name, internal: internal));
      }
    }
    // Brace depth, outside strings and comments, so only top-level lines
    // are read as declarations.
    final code = line
        .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), '')
        .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '')
        .split('//')
        .first;
    depth += '{'.allMatches(code).length - '}'.allMatches(code).length;
    if (depth < 0) depth = 0;
  }
  return found;
}

/// The feature a file under lib/ belongs to — its top-level folder of
/// lib/src — or null for a public library.
String? _featureOf(String path) {
  final parts = path.split('/');
  return parts.length > 2 && parts[0] == 'src' ? parts[1] : null;
}

/// Every import and export from one feature to another (parts are inside
/// their library's), by (from, to): the directives that make it.
Map<(String, String), List<String>> _featureEdges(Map<String, _File> files) {
  final edges = <(String, String), List<String>>{};
  for (final file in files.values) {
    final from = _featureOf(file.path);
    if (from == null) continue;
    for (final d in [...file.of('import'), ...file.of('export')]) {
      final target = d.target;
      final to = target == null ? null : _featureOf(target);
      if (to == null || to == from) continue;
      (edges[(from, to)] ??= []).add('${file.path} ${d.kind}s ${d.uri}');
    }
  }
  return edges;
}

/// The loops of [graph]: its strongly connected parts of more than one
/// node, each sorted (Tarjan's algorithm).
List<List<String>> _loops(Map<String, Set<String>> graph) {
  final index = <String, int>{};
  final low = <String, int>{};
  final stack = <String>[];
  final onStack = <String>{};
  final loops = <List<String>>[];
  var next = 0;
  void visit(String v) {
    index[v] = low[v] = next++;
    stack.add(v);
    onStack.add(v);
    for (final w in graph[v] ?? const <String>{}) {
      if (!index.containsKey(w)) {
        visit(w);
        low[v] = min(low[v]!, low[w]!);
      } else if (onStack.contains(w)) {
        low[v] = min(low[v]!, index[w]!);
      }
    }
    if (low[v] != index[v]) return;
    final loop = <String>[];
    String w;
    do {
      w = stack.removeLast();
      onStack.remove(w);
      loop.add(w);
    } while (w != v);
    if (loop.length > 1) loops.add(loop..sort());
  }

  final nodes = {...graph.keys, for (final to in graph.values) ...to}.toList()
    ..sort();
  for (final v in nodes) {
    if (!index.containsKey(v)) visit(v);
  }
  return loops;
}

void main() {
  final files = _readLib();
  final exported = _exportedFrom(files, _public);

  test('every file is exported by a public library or is internal', () {
    final problems = <String>[];
    for (final file in files.values) {
      if (!file.path.startsWith('src/')) continue;
      if (exported.contains(file.library)) continue;
      if (_internalByList.containsKey(file.library)) continue;
      for (final d in _publicDeclarations(file.text)) {
        if (!d.internal) {
          problems.add(
            '${file.path}:${d.line} ${d.name} — exported by no public '
            'library: export it from its barrel, or mark it @internal',
          );
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('the explicit lists name files that exist', () {
    expect([
      for (final path in [..._internalByList.keys, ..._exportSelectors.keys])
        if (!files.containsKey(path)) path,
    ], isEmpty);
  });

  // A name every export of its file hides is not exported.
  final hiddenEverywhere = <String, Set<String>>{};
  for (final file in files.values) {
    for (final d in file.of('export')) {
      final target = d.target;
      if (target == null) continue;
      final before = hiddenEverywhere[target];
      hiddenEverywhere[target] = before == null
          ? {...d.hidden}
          : before.intersection(d.hidden);
    }
  }

  test('no public library exports an @internal declaration', () {
    final problems = <String>[];
    for (final path in exported) {
      final file = files[path];
      if (file == null) continue;
      final hidden = hiddenEverywhere[path] ?? const <String>{};
      for (final d in _publicDeclarations(file.text)) {
        if (d.internal && !hidden.contains(d.name)) {
          problems.add(
            '${file.path}:${d.line} ${d.name} is @internal but '
            'exported',
          );
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('a barrel hides only @internal declarations of the file', () {
    final problems = <String>[];
    for (final file in files.values) {
      for (final d in file.of('export')) {
        if (d.hidden.isEmpty) continue;
        final target = files[d.target];
        final internal = {
          if (target != null)
            for (final p in _publicDeclarations(target.text))
              if (p.internal) p.name,
        };
        for (final name in d.hidden) {
          if (!internal.contains(name)) {
            problems.add(
              '${file.path} hides $name, which is not an @internal '
              'declaration of ${d.uri}: export it, or mark it @internal',
            );
          }
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('no file sits directly in lib/src', () {
    expect([
      for (final path in files.keys)
        if (path.startsWith('src/') && path.split('/').length == 2) path,
    ], isEmpty);
  });

  test('only a barrel or a public library exports, each only its own '
      'folder', () {
    final problems = <String>[];
    for (final file in files.values) {
      final exports = file.of('export').toList();
      if (exports.isEmpty || file.isPublic) continue;
      if (!file.isBarrel && !_exportSelectors.containsKey(file.path)) {
        problems.add('${file.path} exports, but is not a barrel');
        continue;
      }
      final folder = '${file.path.substring(0, file.path.lastIndexOf('/'))}/';
      for (final d in exports) {
        if (d.target != null && !d.target!.startsWith(folder)) {
          problems.add('${file.path} exports ${d.uri}, outside its folder');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('a library that holds parts is not a barrel', () {
    expect([
      for (final file in files.values)
        if (file.holdsParts && file.of('export').isNotEmpty) file.path,
    ], isEmpty);
  });

  test('no file imports a barrel that leads back to it', () {
    final problems = <String>[];
    for (final file in files.values) {
      for (final d in file.of('import')) {
        final target = d.target;
        if (target == null || files[target]?.of('export').isEmpty != false) {
          continue;
        }
        final reached = _exportedFrom(files, [target]);
        if (reached.contains(file.library) && target != file.library) {
          problems.add('${file.path} imports ${d.uri}, which exports it');
        }
      }
    }
    expect(problems, isEmpty);
  });

  final features = _featureEdges(files);
  final layerOf = {
    for (var i = 0; i < _layers.length; i++)
      for (final feature in _layers[i]) feature: i,
  };

  test('every feature has one layer, and every layer names a feature', () {
    final folders = files.keys.map(_featureOf).nonNulls.toSet();
    final listed = [for (final layer in _layers) ...layer];
    expect([
      for (final f in folders)
        if (!listed.contains(f)) '$f has no layer',
      for (final f in listed.toSet())
        if (listed.where((l) => l == f).length > 1) '$f is in two layers',
      for (final f in listed)
        if (!folders.contains(f)) '$f is no folder of lib/src',
    ], isEmpty);
  });

  test('no import loop crosses from one feature to another', () {
    final graph = <String, Set<String>>{};
    for (final (from, to) in features.keys) {
      (graph[from] ??= {}).add(to);
    }
    final problems = <String>[];
    for (final loop in _loops(graph)) {
      problems.add('a loop of ${loop.join(', ')}:');
      for (final MapEntry(key: (from, to), value: why) in features.entries) {
        if (loop.contains(from) && loop.contains(to)) {
          problems.addAll(['  $from -> $to', for (final w in why) '    $w']);
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('no feature imports one in a layer above its own', () {
    expect([
      for (final MapEntry(key: (from, to), value: why) in features.entries)
        if ((layerOf[to] ?? -1) > (layerOf[from] ?? _layers.length))
          for (final w in why)
            '$from (layer ${layerOf[from]}) imports $to '
                '(layer ${layerOf[to]}): $w',
    ], isEmpty);
  });

  test('the public library exports barrels whole, with no show or hide', () {
    final problems = <String>[];
    for (final path in _public) {
      final file = files[path]!;
      for (final m in _directive.allMatches(file.text)) {
        if (m.group(1) != 'export') continue;
        final rest = m.group(2)!;
        if (RegExp(r'\b(show|hide)\b').hasMatch(rest)) {
          problems.add('$path: export$rest');
        }
      }
      for (final d in file.of('export')) {
        if (d.target == null || !files[d.target]!.isBarrel) {
          problems.add('$path exports ${d.uri}, which is not a barrel');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('inside editor/, each part imports only its own or those below', () {
    String? partOf(String path) {
      final parts = path.split('/');
      if (parts.length < 3 || parts[0] != 'src' || parts[1] != 'editor') {
        return null;
      }
      return parts.length == 3 ? '' : parts[2];
    }

    final levelOf = {
      for (var i = 0; i < _editorParts.length; i++)
        for (final part in _editorParts[i]) part: i,
    };
    final problems = <String>[];
    for (final file in files.values) {
      final from = partOf(file.path);
      if (from == null) continue;
      if (!levelOf.containsKey(from)) {
        problems.add('editor/$from is in no part of _editorParts');
        continue;
      }
      for (final d in file.of('import')) {
        final to = d.target == null ? null : partOf(d.target!);
        if (to == null || to == from) continue;
        if (levelOf[to]! > levelOf[from]! ||
            (levelOf[to] == levelOf[from] && to != from)) {
          problems.add(
            '${file.path} (editor/$from) imports ${d.uri} (editor/$to)',
          );
        }
      }
    }
    expect(problems, isEmpty);
  });

  test("the game's library never reaches the editor", () {
    // Imports followed too: what a release build compiles.
    final seen = <String>{};
    final stack = [_gameLibrary];
    while (stack.isNotEmpty) {
      final path = stack.removeLast();
      if (!seen.add(path)) continue;
      for (final d in files[path]?.directives ?? const <_Directive>[]) {
        if (d.target != null && d.kind != 'part of') stack.add(d.target!);
      }
    }
    expect([
      for (final path in seen)
        if (path.startsWith('src/editor/') || path == 'editor.dart') path,
    ], isEmpty);
  });

  test('the runtime imports nothing editor-side, and nothing native', () {
    final problems = <String>[];
    for (final file in files.values) {
      if (file.path.startsWith('src/editor/') || file.path == 'editor.dart') {
        continue;
      }
      for (final d in file.directives) {
        if (d.kind == 'part of') continue;
        final target = d.target;
        if (target != null &&
            (target.startsWith('src/editor/') || target == 'editor.dart')) {
          problems.add('${file.path} ${d.kind}s ${d.uri}');
        }
        if (_runtimeMayNot.any(d.uri.startsWith)) {
          problems.add('${file.path} ${d.kind}s ${d.uri}');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('no name is exported by both public libraries', () {
    Set<String> namesOf(String library) {
      final hidden = <String, Set<String>>{};
      for (final file in files.values) {
        for (final d in file.of('export')) {
          if (d.target != null) {
            (hidden[d.target!] ??= {}).addAll(d.hidden);
          }
        }
      }
      return {
        for (final path in _exportedFrom(files, [library]))
          if (files[path] case final file?)
            for (final d in _publicDeclarations(file.text))
              if (!d.internal && !(hidden[path]?.contains(d.name) ?? false))
                d.name,
      };
    }

    expect(
      namesOf('just_ui_editor.dart').intersection(namesOf('editor.dart')),
      isEmpty,
    );
  });

  test('just_store.json agrees with the pubspec', () {
    final store =
        (jsonDecode(File('just_store.json').readAsStringSync()) as Map)
            .cast<String, dynamic>();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    String? field(String name) => RegExp(
      '^$name:\\s*(\\S+)',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    String? dependency(String name) => RegExp(
      '^  $name:\\s*(\\S+)',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);

    expect(store['version'], field('version'));
    final requires = (store['requires'] as Map).cast<String, String>();
    expect(requires['just_game_engine'], dependency('just_game_engine'));
    expect(
      requires['just_game_engine_editor'],
      dependency('just_game_engine_editor'),
    );
    final editor = (store['editor'] as Map).cast<String, dynamic>();
    expect(editor['editorOnlyLibraries'], ['editor.dart', 'src/editor/']);
  });

  test('the scanner reads declarations and their annotations', () {
    final found = _publicDeclarations('''
/// Doc.
@internal
final class Kept {
  void method() {}
  static const x = 1;
}

class Plain {}

@internal
Future<int> load() async => 1;

const int limit = 3;

T pick<T>(T a) => a;

extension on int {}

final class _Hidden {}
''');
    expect(found.map((d) => '${d.name}:${d.internal}'), [
      'Kept:true',
      'Plain:false',
      'load:true',
      'limit:false',
      'pick:false',
    ]);
  });
}
