/// The project's files, as the interface editor reads and writes them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart'
    show PackageAssetPaths;

import '../../runtime/screens/ui_document.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import '../../runtime/theme/ui_theme.dart';

/// Reads and writes the interface's files under a project folder: screens,
/// the screen list, themes and fonts. Paths are project-relative with
/// forward slashes, the way the game names its assets.
///
/// Writes go to a sibling file first and are renamed into place, so a
/// crash mid-save never leaves half a screen behind.
class UiProject {
  UiProject(String root) : root = _slashed(root);

  /// The project folder.
  final String root;

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  static String _slashed(String path) => path.replaceAll(r'\', '/');

  /// Where [path] is on disk: in the project, or — for `packages/<name>/…`
  /// — in that package's folder.
  String absolute(String path) => PackageAssetPaths.of(root).absolute(path);

  File _file(String path) => File(absolute(path));

  bool exists(String path) => _file(path).existsSync();

  /// [path]'s text, or null when there is no such file.
  String? readSync(String path) {
    final file = _file(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  /// [path]'s text — from the project, or the app bundle when the project
  /// has no such file.
  Future<String> read(String path) async {
    final file = _file(path);
    if (await file.exists()) return file.readAsString();
    return rootBundle.loadString(path, cache: false);
  }

  /// Writes [text] to [path], whole or not at all.
  void writeSync(String path, String text) {
    final file = _file(path);
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.saving');
    temp.writeAsStringSync(text, flush: true);
    if (file.existsSync()) file.deleteSync();
    temp.renameSync(file.path);
  }

  /// [json] written as the editor writes every file: two-space indents and
  /// a newline at the end.
  void writeJsonSync(String path, Object json) =>
      writeSync(path, '${_pretty.convert(json)}\n');

  void deleteSync(String path) {
    final file = _file(path);
    if (file.existsSync()) file.deleteSync();
  }

  void renameSync(String from, String to) {
    final target = _file(to);
    target.parent.createSync(recursive: true);
    _file(from).renameSync(target.path);
  }

  // ── Screens ────────────────────────────────────────────────────────────

  /// Every screen file under `assets/`, listed or not, by path.
  List<String> screenFiles() => _filesEndingIn('.${UiDocument.extension}');

  /// The screen at [path].
  UiDocument readScreen(String path) {
    final text = readSync(path);
    if (text == null) throw FileSystemException('No such screen', path);
    return UiDocument.fromJson(
      (jsonDecode(text) as Map).cast<String, dynamic>(),
    );
  }

  void writeScreen(String path, UiDocument document) =>
      writeJsonSync(path, document.toJson());

  /// The game's screen list — empty when it has none yet.
  UiScreenManifest readManifest([String path = UiScreenManifest.defaultPath]) {
    final text = readSync(path);
    if (text == null) return UiScreenManifest();
    try {
      return UiScreenManifest.fromJson(
        (jsonDecode(text) as Map).cast<String, dynamic>(),
      );
    } on Object {
      return UiScreenManifest();
    }
  }

  void writeManifest(
    UiScreenManifest manifest, [
    String path = UiScreenManifest.defaultPath,
  ]) => writeJsonSync(path, manifest.toJson());

  // ── Themes and fonts ───────────────────────────────────────────────────

  /// Every theme under `assets/`.
  List<String> themeFiles() => _filesEndingIn('.uitheme.json');

  /// What `UiThemes` reads through while the editor runs: the project's
  /// file, so a theme saved a moment ago shows without a rebuild.
  Future<UiTheme> loadTheme(String path) async =>
      UiTheme.parse(await read(path));

  /// A font file's bytes, from the project or the bundle.
  Future<ByteData> fontData(String path) async {
    final file = _file(path);
    if (!await file.exists()) return rootBundle.load(path);
    return ByteData.sublistView(await file.readAsBytes());
  }

  /// Every font in [folder], so a font dropped into the project can be
  /// used with no rebuild and no line in pubspec.yaml.
  List<String> fontFiles([String folder = 'assets/fonts']) {
    const endings = ['.ttf', '.otf', '.ttc'];
    return [
      for (final path in _filesUnder(folder))
        if (endings.any(path.toLowerCase().endsWith)) path,
      // And the fonts installed packages ship.
      ...PackageAssetPaths.of(root).packageFiles(endings: endings),
    ];
  }

  List<String> _filesEndingIn(String ending) => [
    for (final path in _filesUnder('assets'))
      if (path.toLowerCase().endsWith(ending)) path,
    ...PackageAssetPaths.of(root).packageFiles(endings: [ending]),
  ];

  List<String> _filesUnder(String folder) {
    final directory = Directory(absolute(folder));
    if (!directory.existsSync()) return const [];
    final prefix = '$root/';
    return [
      for (final entry in directory.listSync(recursive: true))
        if (entry is File && !entry.path.endsWith('.saving'))
          _slashed(entry.path).replaceFirst(prefix, ''),
    ]..sort();
  }
}
