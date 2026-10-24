/// The project's files, as the interface editor reads and writes them.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths, ProjectFiles;

import '../../runtime/screens/ui_document.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import '../../runtime/theme/ui_theme.dart';

/// Reads and writes the interface's files under a project folder: screens,
/// the screen list, themes and fonts. Paths are project-relative with
/// forward slashes, the way the game names its assets.
///
/// Writes go through `ProjectFiles`: to a sibling file first, then moved
/// over the old one, so a crash mid-save never leaves half a screen behind
/// — and only to files the project may write ([isWritable]).
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

  /// Whether [path] may be written: a file of the project, or of a package
  /// outside pub's cache — never one that climbs out of either, or names a
  /// drive. Paths read out of files (a screen list, a canvas's theme) are
  /// checked with this before anything is written or deleted there.
  bool isWritable(String path) => PackageAssetPaths.of(root).isWritable(path);

  /// Refuses [path] when it is not [isWritable].
  void _mayWrite(String path) {
    if (!isWritable(path)) {
      throw FileSystemException(
        'Not a file of this project the editor may change',
        path,
      );
    }
  }

  /// Writes [text] to [path], whole or not at all: when anything fails, the
  /// file there is as it was and the error is rethrown.
  void writeSync(String path, String text) {
    _mayWrite(path);
    ProjectFiles.writeStringSync(absolute(path), text);
  }

  /// [json] written as the editor writes every file: two-space indents and
  /// a newline at the end.
  void writeJsonSync(String path, Object json) =>
      writeSync(path, '${_pretty.convert(json)}\n');

  void deleteSync(String path) {
    _mayWrite(path);
    final file = _file(path);
    if (file.existsSync()) file.deleteSync();
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

  /// The game's screen list — empty when it has none yet, and when it does
  /// not read ([manifestProblem] says why; [writeManifest] then refuses).
  UiScreenManifest readManifest([String path = UiScreenManifest.defaultPath]) =>
      _manifest(path).$1;

  /// Why the screen list at [path] does not read — broken JSON, or a newer
  /// format — or null when it reads or is not there yet.
  String? manifestProblem([String path = UiScreenManifest.defaultPath]) =>
      _manifest(path).$2;

  (UiScreenManifest, String?) _manifest(String path) {
    final String? text;
    try {
      text = readSync(path);
    } on FileSystemException catch (error) {
      return (UiScreenManifest(), error.message);
    }
    if (text == null) return (UiScreenManifest(), null);
    try {
      final json = jsonDecode(text);
      if (json is! Map) {
        return (UiScreenManifest(), 'it holds no JSON object');
      }
      return (UiScreenManifest.fromJson(json.cast<String, dynamic>()), null);
    } on FormatException catch (error) {
      return (UiScreenManifest(), error.message);
    } on Object catch (error) {
      return (UiScreenManifest(), '$error');
    }
  }

  /// Writes the screen list. Throws a [FormatException], and leaves the
  /// file exactly as it is, while the one there does not read: written
  /// over, every screen it lists — and its theme — would be lost.
  void writeManifest(
    UiScreenManifest manifest, [
    String path = UiScreenManifest.defaultPath,
  ]) {
    if (manifestProblem(path) case final problem?) {
      throw FormatException(
        '$path does not read ($problem), so it was left as it is. Mend it '
        'by hand first.',
      );
    }
    writeJsonSync(path, manifest.toJson());
  }

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
