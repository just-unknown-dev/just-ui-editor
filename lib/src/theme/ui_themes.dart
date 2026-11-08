/// Where one engine's themes come from, and the ones it has read.
library;

import 'package:just_game_engine/just_game_engine.dart';

import 'ui_theme.dart';

/// Where themes come from, and the ones read so far, for one engine.
///
/// Kept on the engine's [EngineContext] ([of]), not in a static, so an
/// editor pointing [loader] at a project's files, or a game's screen list
/// choosing the [fallback], changes that engine's themes and no other's.
/// A tool replaces [loader] to read the project's files instead of the
/// asset bundle — the same seam as the engine's timelines
/// (`context.timelines`).
final class UiThemes {
  UiThemes._(this._context) {
    useBundle();
  }

  static final Object _key = Object();

  /// [context]'s themes, made the first time they are asked for.
  static UiThemes of(EngineContext context) =>
      context.slot(_key, () => UiThemes._(context));

  final EngineContext _context;

  /// Reads a theme file; the context's bundle unless a tool says otherwise.
  late Future<UiTheme> Function(String path) loader;

  Future<UiTheme> _fromBundle(String path) async =>
      UiTheme.parse(await _context.bundle.loadString(path));

  /// Restores the bundle loader.
  void useBundle() => loader = _fromBundle;

  final Map<String, UiTheme> _loaded = {};

  /// Paths that would not load, so they are not asked for again every
  /// frame. Cleared by [evict], [put] and [reset].
  final Set<String> _failed = {};

  /// Loads in flight, so asking twice does not read the file twice.
  final Map<String, Future<UiTheme>> _loading = {};

  /// The theme a canvas that names none is drawn with.
  UiTheme fallback = UiTheme.fallback;

  /// Who chose [fallback] last ([useFallback]); only they put it back.
  Object? _fallbackOwner;

  /// The theme an editor resolves roles against when it shows what a style
  /// inherits.
  ///
  /// There is no one theme at rest — each canvas names its own — so a tool
  /// that wants to show "16, from body" sets this to the project's theme
  /// once it has read it. Left alone it is [fallback], whose role defaults
  /// are what a canvas with no theme draws with anyway.
  UiTheme preview = UiTheme.fallback;

  /// Where [preview] was read from, when it was read from a file.
  String? previewPath;

  /// Makes the theme at [path] the [preview].
  Future<void> usePreview(String path) async {
    previewPath = path;
    preview = await load(path);
  }

  /// Makes [theme] the [fallback] on behalf of [owner] — a game's screens,
  /// whose list names it — until [owner] gives it back
  /// ([releaseFallback]). A later owner takes it over.
  void useFallback(UiTheme theme, {required Object owner}) {
    fallback = theme;
    _fallbackOwner = owner;
  }

  /// The built-in [fallback] again, when [owner] chose the one in use; a
  /// [preview] that was that fallback goes back to the built-in one too.
  /// Nothing when another has chosen since.
  void releaseFallback(Object owner) {
    if (!identical(_fallbackOwner, owner)) return;
    _fallbackOwner = null;
    if (identical(preview, fallback)) {
      preview = UiTheme.fallback;
      previewPath = null;
    }
    fallback = UiTheme.fallback;
  }

  /// What [path] holds, once it has been read. Null before then — a painter
  /// cannot wait for a file, so it draws with [fallback] until the load
  /// lands and the next frame picks it up. A path that would not load is
  /// [fallback] until it is [evict]ed.
  UiTheme? cached(String path) =>
      _loaded[path] ?? (_failed.contains(path) ? fallback : null);

  /// Whether [path] was asked for and would not load.
  bool failed(String path) => _failed.contains(path);

  /// Reads [path], keeping it for [cached]. A theme that will not load is
  /// the fallback rather than an exception mid-frame, and is not read again
  /// until it is [evict]ed.
  Future<UiTheme> load(String path) {
    if (path.isEmpty || _failed.contains(path)) return Future.value(fallback);
    final known = _loaded[path];
    if (known != null) return Future.value(known);
    return _loading[path] ??= _read(path);
  }

  Future<UiTheme> _read(String path) async {
    // A read that a [reset] or an [evict] overtook answers whoever waited
    // for it, and changes nothing: what it read, or that it failed, is of
    // a time since forgotten.
    final era = _era;
    final evictions = _evictions[path] ?? 0;
    bool current() => era == _era && (_evictions[path] ?? 0) == evictions;
    try {
      final theme = await loader(path);
      if (!current()) return theme;
      _loaded[path] = theme;
      // The first theme a project loads is the one a tool shows roles
      // from, until something says otherwise.
      if (identical(preview, UiTheme.fallback)) {
        preview = theme;
        previewPath = path;
      }
      return theme;
    } catch (_) {
      if (current()) _failed.add(path);
      return fallback;
    } finally {
      if (current()) _loading.remove(path);
    }
  }

  /// Raised by [reset], and by an [evict] of every theme, so a read begun
  /// before either is not kept after it.
  int _era = 0;

  /// How often each path was [evict]ed on its own, for the same reason.
  final Map<String, int> _evictions = {};

  /// Uses [theme] for [path] from now on, as though read from it — how a
  /// theme editor shows an edit on every canvas before it is saved.
  void put(String path, UiTheme theme) {
    _loaded[path] = theme;
    _failed.remove(path);
    if (previewPath == path) preview = theme;
  }

  /// Back to nothing read: no themes, the built-in fallback and preview,
  /// the bundle loader. For tests, and for a tool opening another project.
  void reset() {
    _era++;
    _loaded.clear();
    _failed.clear();
    _loading.clear();
    fallback = UiTheme.fallback;
    _fallbackOwner = null;
    preview = UiTheme.fallback;
    previewPath = null;
    useBundle();
  }

  /// Forgets [path] — it changed on disk. Without one, every theme.
  ///
  /// The [preview] is read again when it was one of them, so a tool that
  /// shows what a style inherits shows the theme as it is now, not as it
  /// was when the tool opened.
  void evict([String? path]) {
    if (path == null) {
      _era++;
      _loaded.clear();
      _failed.clear();
      _loading.clear();
    } else {
      _evictions[path] = (_evictions[path] ?? 0) + 1;
      _loaded.remove(path);
      _failed.remove(path);
      _loading.remove(path);
    }
    final shown = previewPath;
    if (shown != null && (path == null || path == shown)) {
      preview = fallback;
      load(shown).then((theme) {
        if (previewPath == shown) preview = theme;
      });
    } else if (_loaded.isEmpty) {
      preview = fallback;
    }
  }
}
