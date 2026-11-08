/// Fonts a game drops into its assets, loaded while it runs.
///
/// Flutter normally wants every family declared in `pubspec.yaml`, which
/// means editing a build file — and restarting — to try a font. A font
/// loaded here works the moment it is on disk, so the editor can offer
/// whatever is in `assets/fonts/` and a scene can name it.
library;

import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The fonts one engine's interface has loaded, and where it reads them.
///
/// Kept on the engine's [EngineContext] ([of]), not in a static, so an
/// editor reading a project's files never changes where a game in the same
/// process reads its own. Flutter's font registry itself is process-wide: a
/// family loaded by one engine can be drawn by every other, and the last
/// load of a family is the face everyone draws.
final class UiFonts {
  UiFonts._(this._context) {
    useBundle();
  }

  static final Object _key = Object();

  /// [context]'s fonts, made the first time they are asked for.
  static UiFonts of(EngineContext context) =>
      context.slot(_key, () => UiFonts._(context));

  final EngineContext _context;

  /// Families that are ready to draw with.
  final Set<String> _loaded = {};

  /// Loads in flight, so asking twice does not read the file twice.
  final Map<String, Future<void>> _loading = {};

  /// Raised by [reset], so a load begun before it changes nothing after.
  int _era = 0;

  /// Where the bytes come from. A tool points this at the project's files;
  /// a game reads its bundle (the context's, `EngineContext.bundle`).
  late Future<ByteData> Function(String path) read;

  /// Reads from the context's bundle again.
  void useBundle() => read = _context.bundle.load;

  /// The families loaded so far.
  List<String> get families => _loaded.toList()..sort();

  /// Whether [family] is ready to draw with.
  bool isLoaded(String family) => _loaded.contains(family);

  /// Makes [family] drawable from [paths] — one file per weight or style.
  ///
  /// Returns once it can be drawn with. Asking again is free, so a widget
  /// may call this in its build without thinking.
  ///
  /// [from] reads the files; [read] when null.
  Future<void> ensureLoaded(
    String family,
    List<String> paths, {
    Future<ByteData> Function(String path)? from,
  }) {
    if (family.isEmpty || paths.isEmpty || _loaded.contains(family)) {
      return Future.value();
    }
    return _loading[family] ??= _load(family, paths, from ?? read);
  }

  Future<void> _load(
    String family,
    List<String> paths,
    Future<ByteData> Function(String path) from,
  ) async {
    // A load a [reset] overtook answers whoever waited for it and changes
    // nothing: the reset's own loads are the ones that count now.
    final era = _era;
    try {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(from(path));
      }
      await loader.load();
      if (era == _era) _loaded.add(family);
    } catch (_) {
      // A font that will not load leaves text in the fallback family —
      // worth a line in the Problems dock, never worth a crash mid-frame.
    } finally {
      if (era == _era) _loading.remove(family);
    }
  }

  /// Forgets what has been loaded. Flutter keeps the glyphs, so this is for
  /// tests and for an editor reloading a font that changed on disk. A load
  /// still under way finishes without counting.
  void reset() {
    _era++;
    _loaded.clear();
    _loading.clear();
  }

  /// The family a font file is named for: `assets/fonts/PressStart2P.ttf`
  /// is `PressStart2P`, and `Inter-Bold.ttf` is `Inter`.
  ///
  /// How the editor turns a folder of files into a list of families, and
  /// how several weights land under one name.
  static String familyOf(String path) {
    final file = path.split('/').last.split('\\').last;
    final dot = file.lastIndexOf('.');
    final stem = dot < 0 ? file : file.substring(0, dot);
    final dash = stem.indexOf('-');
    final name = dash <= 0 ? stem : stem.substring(0, dash);
    return name.replaceAll('_', ' ').trim();
  }

  /// Groups font files by the family they belong to.
  static Map<String, List<String>> familiesIn(Iterable<String> paths) {
    final out = <String, List<String>>{};
    for (final path in paths) {
      final lower = path.toLowerCase();
      if (!lower.endsWith('.ttf') &&
          !lower.endsWith('.otf') &&
          !lower.endsWith('.ttc')) {
        continue;
      }
      out.putIfAbsent(familyOf(path), () => []).add(path);
    }
    for (final files in out.values) {
      files.sort();
    }
    return out;
  }

  /// Loads every family under [paths] — what a game calls at boot with the
  /// contents of its fonts folder. [from] reads the files; [read] when null.
  Future<void> loadAll(
    Iterable<String> paths, {
    Future<ByteData> Function(String path)? from,
  }) async {
    final families = familiesIn(paths);
    await Future.wait([
      for (final entry in families.entries)
        ensureLoaded(entry.key, entry.value, from: from),
    ]);
  }

  /// Where a game keeps the fonts its interface uses, unless it says
  /// otherwise.
  static const String defaultFolder = 'assets/fonts/';

  /// Loads every font file the bundle holds under [folder] — what
  /// `JustGameUi.install` does at boot, so the families the editor offers
  /// from the project's `assets/fonts/` are the families the game draws.
  ///
  /// Reads the bundle's asset manifest; [bundle] is the context's when
  /// null. A bundle with no manifest (a test, a tool) or no fonts there
  /// loads nothing, and a file that will not load leaves its family to the
  /// fallback. The folder must be listed under `flutter: assets:`.
  Future<void> loadFolder(String folder, {AssetBundle? bundle}) async {
    final prefix = folder.endsWith('/') ? folder : '$folder/';
    final List<String> assets;
    try {
      assets = (await AssetManifest.loadFromAssetBundle(
        bundle ?? _context.bundle,
      )).listAssets();
    } on Object {
      return;
    }
    await loadAll([
      for (final asset in assets)
        if (asset.startsWith(prefix)) asset,
    ], from: bundle?.load);
  }
}
