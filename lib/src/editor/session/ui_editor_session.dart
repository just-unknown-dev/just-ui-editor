/// Everything the interface editor holds while it is open.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/io.dart' show FileSystemException;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/button_component.dart';
import '../../runtime/just_game_ui.dart';
import '../../runtime/layer/ui_layer.dart';
import '../../runtime/screens/ui_document.dart';
import '../../runtime/screens/ui_scene_extractor.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import '../../runtime/theme/ui_theme.dart';
import '../canvas/ui_canvas_metrics.dart';
import '../document/ui_screen_document.dart';
import '../project/ui_project.dart';
import '../theme/ui_theme_document.dart';
import 'ui_device.dart';

/// Editing, or trying the screen out as a player would.
enum UiEditMode { edit, preview }

/// A guide dragged out of a ruler: a line at [at] design pixels.
class UiGuide {
  const UiGuide({required this.vertical, required this.at});

  /// A vertical line (constant x), or a horizontal one.
  final bool vertical;
  final double at;

  Map<String, dynamic> toJson() => {'axis': vertical ? 'x' : 'y', 'at': at};

  /// The guide [json] describes, or null when it is not one — a file
  /// edited by hand is read as far as it makes sense, never thrown on.
  static UiGuide? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! num || !at.isFinite) return null;
    return UiGuide(vertical: json['axis'] == 'x', at: at.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is UiGuide && other.vertical == vertical && other.at == at;

  @override
  int get hashCode => Object.hash(vertical, at);
}

/// The interface editor's state: the screens, the one open, how it is being
/// looked at, and how it is being tried.
class UiEditorSession {
  /// [context] is the edited engine's — the screens are built on it, so
  /// the game's own components read; null gives the session a context of
  /// its own. [codec] defaults to one over its definitions.
  ///
  /// [onFilesChanged] hears of every file the session writes, moves or
  /// deletes — whatever shows them (the running game, the Assets dock)
  /// reads them again.
  UiEditorSession({
    required this.project,
    SceneCodec? codec,
    EngineContext? context,
    this.onFilesChanged,
  }) : context = context ?? EngineContext(),
       _ownsContext = context == null {
    this.context.install(JustGameUi.extension);
    this.codec = codec ?? SceneCodec(this.context.definitions);
    refreshFiles();
  }

  final UiProject project;
  late final SceneCodec codec;

  /// What the screens are built on.
  final EngineContext context;
  final bool _ownsContext;

  /// Told the project paths of the files written, moved or deleted.
  final void Function(List<String> paths)? onFilesChanged;

  void _changed(List<String> paths) => onFilesChanged?.call(paths);

  /// Why the last thing asked of the session — opening, saving, renaming,
  /// changing the screen list — did not happen, for the editor to say.
  String? lastError;

  bool _fail(String message) {
    lastError = message;
    return false;
  }

  // ── Screens ────────────────────────────────────────────────────────────

  /// The screen open, or null.
  final Signal<UiScreenDocument?> document = Signal(
    null,
    debugLabel: 'uiDocument',
  );

  /// The game's screen list.
  late final Signal<UiScreenManifest> manifest = Signal(
    UiScreenManifest(),
    debugLabel: 'uiManifest',
  );

  /// Why the game's screen list does not read, or null when it does (or is
  /// not there yet). While it is set the list is never written: written
  /// over, every screen it names would be lost.
  final Signal<String?> manifestProblem = Signal(
    null,
    debugLabel: 'uiManifestProblem',
  );

  /// Every screen file in the project, listed or not.
  final Signal<List<String>> files = Signal(const [], debugLabel: 'uiFiles');

  /// Reads the screen list and the files again — after something outside
  /// changed them.
  void refreshFiles() {
    _names = null;
    manifest.value = project.readManifest();
    manifestProblem.value = project.manifestProblem();
    files.value = project.screenFiles();
  }

  Map<String, String>? _names;

  /// Every screen's file, by the screen's name — what `ui.push` and the
  /// preview's Behind name them by.
  Map<String, String> get screensByName =>
      _names ??= {for (final path in files.value) ?_readName(path): path};

  /// The name of the screen in the file at [path], or null when it does
  /// not read.
  String? nameOf(String path) {
    for (final entry in screensByName.entries) {
      if (entry.value == path) return entry.key;
    }
    return null;
  }

  String? _readName(String path) {
    try {
      return project.readScreen(path).name;
    } on Object {
      return null;
    }
  }

  UiScreenDocument? get _doc => document.value;

  /// Opens the screen at [path], closing the one before. False when it
  /// could not be read; [lastError] then says why.
  bool open(String path) {
    final UiDocument read;
    try {
      read = project.readScreen(path);
    } on Object catch (error) {
      return _fail('$path does not read: ${_describe(error)}');
    }
    _replace(UiScreenDocument.open(path, read, codec: codec, context: context));
    return true;
  }

  static String _describe(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError?) =>
      '$message (${osError.message})',
    FileSystemException(:final message) => message,
    _ => '$error',
  };

  void _replace(UiScreenDocument? next) {
    final previous = _doc;
    batch(() {
      document.value = next;
      mode.value = UiEditMode.edit;
      forcedState.value = null;
      snapGuides.value = const [];
      final saved = next?.editorData.value['device'];
      if (saved is Map) {
        device.value = UiDevice.fromJson(saved.cast<String, dynamic>());
      }
      // A screen designed wider than tall is shown on its side.
      final design = next?.settings?.designSize;
      if (design != null) landscape.value = design.width > design.height;
    });
    previous?.dispose();
    // What the inspector says a style inherits is this screen's theme.
    final theme = themePathFor(next);
    if (theme != null) UiThemes.usePreview(theme);
  }

  /// Writes the open screen to its file. True when it was written; false
  /// with [lastError] saying why when it was not — the screen then stays
  /// unsaved.
  bool save() {
    final doc = _doc;
    if (doc == null) return false;
    try {
      project.writeScreen(doc.path, doc.capture());
    } on Object catch (error) {
      return _fail('${doc.path} was not saved: ${_describe(error)}');
    }
    doc.markSaved();
    if (!files.value.contains(doc.path)) refreshFiles();
    _changed([doc.path]);
    return true;
  }

  /// Where a new screen called [name] is saved.
  String pathFor(String name, {String folder = 'assets/ui'}) =>
      '$folder/${UiSceneExtractor.fileNameFor(name)}';

  /// A name no screen has from [base] — `Pause`, `Pause2` — whose file
  /// ([pathFor]) is not there yet either: two names can share a file name
  /// (`Main Menu` and `MainMenu` are both `main_menu.ui.json`).
  String freeScreenName(String base) {
    if (!_screenNameTaken(base)) return base;
    var n = 2;
    while (_screenNameTaken('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  bool _screenNameTaken(String name, {String? except}) {
    final lower = name.toLowerCase();
    for (final MapEntry(key: other, value: path) in screensByName.entries) {
      if (path != except && other.toLowerCase() == lower) return true;
    }
    final target = pathFor(name);
    return target != except && project.exists(target);
  }

  /// Why the screen list may not be written now, or null when it may.
  String? get _listProblem => switch (manifestProblem.value) {
    final problem? =>
      '${UiScreenManifest.defaultPath} does not read ($problem). Mend it '
          'by hand first: written over, every screen it names would be lost.',
    null => null,
  };

  /// Makes a new screen called [name], saves it, lists it, and opens it.
  ///
  /// Throws a [FileSystemException] when a file is already where it would
  /// go (see [freeScreenName]), and a [FormatException] when the screen
  /// list does not read — nothing is written then.
  UiScreenDocument createScreen(
    String name, {
    bool isScreen = true,
    bool startOpen = false,
  }) {
    final path = pathFor(name);
    if (project.exists(path)) {
      throw FileSystemException('A screen is already there', path);
    }
    if (_listProblem case final problem?) throw FormatException(problem);
    final doc = UiScreenDocument.blank(
      path,
      name,
      isScreen: isScreen,
      codec: codec,
      context: context,
    );
    final canvas = doc.settings;
    // A new screen draws the way the others do: their size and theme.
    final like = _anyCanvasSettings();
    if (canvas != null && like != null) {
      canvas
        ..designSize = like.designSize
        ..scaleMode = like.scaleMode
        ..theme = like.theme;
    } else if (canvas != null) {
      canvas.theme = manifest.value.theme ?? '';
    }
    try {
      project.writeScreen(path, doc.capture());
      doc.markSaved();
      _list(path, startOpen: startOpen);
    } on Object {
      doc.dispose();
      rethrow;
    }
    _replace(doc);
    return doc;
  }

  UiCanvasComponent? _anyCanvasSettings() {
    for (final path in files.value) {
      try {
        final settings = project.readScreen(path).canvasSettings;
        if (settings != null) return settings;
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// Writes a copy of the screen at [path], under a name of its own, and
  /// lists it — without opening it: that is the editor's to do, once it has
  /// asked about the open screen's unsaved work. The copy's path, or null
  /// with [lastError] saying why.
  String? duplicateScreen(String path) {
    if (_listProblem case final problem?) {
      _fail(problem);
      return null;
    }
    final UiDocument source;
    try {
      source = project.readScreen(path);
    } on Object catch (error) {
      _fail('$path does not read: ${_describe(error)}');
      return null;
    }
    final name = freeScreenName('${source.name}Copy');
    final renamed = source.renamed(name);
    final target = pathFor(name);
    try {
      project.writeScreen(target, renamed);
      _list(
        target,
        startOpen: manifest.value.entryFor(path)?.startOpen ?? false,
      );
    } on Object catch (error) {
      _fail('The copy was not made: ${_describe(error)}');
      return null;
    }
    return target;
  }

  /// Why the screen at [path] may not be called [name], or null when it
  /// may: an empty name, one another screen has, a file already where the
  /// new name would go, one of the screen's own elements being called that
  /// (names are how a screen's tree is linked), a file that is not the
  /// project's to change, or a screen list that does not read.
  String? renameScreenProblem(String path, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'A screen needs a name.';
    if (!project.isWritable(path)) {
      return '$path is not a file of this project the editor may change.';
    }
    if (_listProblem case final problem?) return problem;
    for (final MapEntry(key: other, value: at) in screensByName.entries) {
      if (at != path && other.toLowerCase() == trimmed.toLowerCase()) {
        return 'Another screen is already called $other.';
      }
    }
    final target = _targetFor(path, trimmed);
    if (target != path && project.exists(target)) {
      return 'There is a file at $target already.';
    }
    final Iterable<String?> elements;
    final open = _doc;
    if (open != null && open.path == path) {
      elements = [
        for (final e in open.world.entities)
          if (e.id != open.canvas.id) e.name,
      ];
    } else {
      try {
        elements = [
          for (final e in project.readScreen(path).entities.skip(1))
            e['name'] as String?,
        ];
      } on Object catch (error) {
        return '$path does not read: ${_describe(error)}';
      }
    }
    if (elements.contains(trimmed)) {
      return 'One of its own elements is called $trimmed: a screen and its '
          'elements need names of their own.';
    }
    return null;
  }

  /// Where the screen at [path] goes when it is called [name]: its own file
  /// again when the two name one file — a change of letter case only, on a
  /// file system that folds case.
  String _targetFor(String path, String name) {
    final target = pathFor(name);
    if (target == path) return path;
    return ProjectFiles.samePath(
          project.absolute(target),
          project.absolute(path),
        )
        ? path
        : target;
  }

  /// Renames the screen at [path] — its canvas, its file, its entry in the
  /// list. False, with [lastError] saying why, when [renameScreenProblem]
  /// has an objection or a file could not be written.
  bool renameScreen(String path, String name) {
    if (renameScreenProblem(path, name) case final problem?) {
      return _fail(problem);
    }
    final trimmed = name.trim();
    final target = _targetFor(path, trimmed);
    final open = _doc;
    final wasOpen = open != null && open.path == path;
    final oldName = wasOpen ? open.name : nameOf(path);
    try {
      if (wasOpen) {
        // The open one is renamed where it stands and written, unsaved
        // changes and all — a rename is not the moment to lose them.
        final was = open.canvas.name;
        open.canvas.name = trimmed;
        try {
          project.writeScreen(target, open.capture());
        } on Object {
          open.canvas.name = was;
          rethrow;
        }
        open.path = target;
        open.markSaved();
        open.sceneState.refresh();
      } else {
        project.writeScreen(target, project.readScreen(path).renamed(trimmed));
      }
      // The list before the old file goes: a list naming a file that is
      // not there is the one thing a failure here must not leave.
      final entries = [
        for (final e in manifest.value.screens)
          e.path == path ? e.copyWith(path: target) : e,
      ];
      project.writeManifest(manifest.value.withScreens(entries));
      if (target != path) project.deleteSync(path);
    } on Object catch (error) {
      refreshFiles();
      return _fail('$path was not renamed: ${_describe(error)}');
    }
    refreshFiles();
    if (oldName != null && behind.value.contains(oldName)) {
      behind.value = [for (final n in behind.value) n == oldName ? trimmed : n];
    }
    if (wasOpen) document.value = open;
    _changed([target, if (target != path) path, UiScreenManifest.defaultPath]);
    return true;
  }

  /// Deletes the screen at [path] and takes it off the list. False, with
  /// [lastError] saying why, when it is not the project's to delete or the
  /// list does not read.
  bool deleteScreen(String path) {
    if (!project.isWritable(path)) {
      return _fail(
        '$path is not a file of this project the editor may change.',
      );
    }
    if (_listProblem case final problem?) return _fail(problem);
    final entries = [
      for (final e in manifest.value.screens)
        if (e.path != path) e,
    ];
    try {
      project.writeManifest(manifest.value.withScreens(entries));
      if (_doc?.path == path) _replace(null);
      project.deleteSync(path);
    } on Object catch (error) {
      refreshFiles();
      return _fail('$path was not deleted: ${_describe(error)}');
    }
    refreshFiles();
    _changed([path, UiScreenManifest.defaultPath]);
    return true;
  }

  /// Whether the screen at [path] shows from the game's first frame. False,
  /// with [lastError] saying why, when the list was not written.
  bool setStartOpen(String path, bool startOpen) {
    final list = manifest.value;
    final entries = list.entryFor(path) == null
        ? [...list.screens, UiScreenEntry(path: path, startOpen: startOpen)]
        : [
            for (final e in list.screens)
              e.path == path ? e.copyWith(startOpen: startOpen) : e,
          ];
    return _writeList(list.withScreens(entries));
  }

  /// Puts [path] on the game's list, or takes it off. False, with
  /// [lastError] saying why, when the list was not written.
  bool setListed(String path, bool listed) {
    final list = manifest.value;
    final entries = listed
        ? [
            ...list.screens,
            if (list.entryFor(path) == null) UiScreenEntry(path: path),
          ]
        : [
            for (final e in list.screens)
              if (e.path != path) e,
          ];
    return _writeList(list.withScreens(entries));
  }

  bool _writeList(UiScreenManifest next) {
    if (_listProblem case final problem?) return _fail(problem);
    try {
      project.writeManifest(next);
    } on Object catch (error) {
      refreshFiles();
      return _fail('The screen list was not saved: ${_describe(error)}');
    }
    refreshFiles();
    _changed([UiScreenManifest.defaultPath]);
    return true;
  }

  /// Lists [path], when it is not yet. Throws when the list is not written.
  void _list(String path, {required bool startOpen}) {
    final list = manifest.value;
    if (list.entryFor(path) == null) {
      project.writeManifest(
        list.withScreens([
          ...list.screens,
          UiScreenEntry(path: path, startOpen: startOpen),
        ]),
      );
    }
    refreshFiles();
    _changed([path, UiScreenManifest.defaultPath]);
  }

  // ── The theme ──────────────────────────────────────────────────────────

  /// The theme open in the Theme tab, or null.
  final Signal<UiThemeDocument?> theme = Signal(null, debugLabel: 'uiThemeDoc');

  /// Every theme in the project.
  List<String> get themeFiles => project.themeFiles();

  /// Opens the theme at [path] in the Theme tab. False when it would not
  /// read. The theme open before is let go — and what it showed unsaved
  /// with it.
  bool openTheme(String path) {
    final next = UiThemeDocument.open(project, path);
    if (next == null) return _fail('$path does not read as a theme.');
    final previous = theme.value;
    theme.value = next;
    previous?.dispose();
    return true;
  }

  /// The theme a screen shows by: its own, else the game's.
  String? themePathFor(UiScreenDocument? doc) {
    final own = doc?.settings?.theme ?? '';
    if (own.isNotEmpty) return own;
    return manifest.value.theme;
  }

  /// Makes a theme at [path] from the built-in one, and opens it. False,
  /// with [lastError] saying why, when it could not be written.
  bool createTheme([String path = 'assets/ui/default.uitheme.json']) {
    if (!project.exists(path)) {
      try {
        project.writeJsonSync(
          path,
          UiTheme.fallback
              .copyWith(name: path.split('/').last.split('.').first)
              .toJson(),
        );
      } on Object catch (error) {
        return _fail('$path was not made: ${_describe(error)}');
      }
      _changed([path]);
    }
    return openTheme(path);
  }

  /// Saves the open theme; every screen drawn with it already shows it.
  /// False, with [lastError] saying why, when it was not written.
  bool saveTheme() {
    final open = theme.value;
    if (open == null) return false;
    try {
      open.save(project);
    } on Object catch (error) {
      return _fail('${open.path} was not saved: ${_describe(error)}');
    }
    _changed([open.path]);
    return true;
  }

  /// Whether anything open — the screen or the theme — has unsaved changes.
  bool get hasUnsavedWork =>
      (document.value?.dirty.value ?? false) ||
      (theme.value?.dirty.value ?? false);

  /// Saves whatever is unsaved. True when all of it was written.
  bool saveAll() {
    var ok = true;
    if (document.value?.dirty.value ?? false) ok = save() && ok;
    if (theme.value?.dirty.value ?? false) ok = saveTheme() && ok;
    return ok;
  }

  // ── Looking at it ──────────────────────────────────────────────────────

  final Signal<UiDevice> device = Signal(
    UiDevices.phone,
    debugLabel: 'uiDevice',
  );
  final Signal<bool> landscape = Signal(false, debugLabel: 'uiLandscape');

  /// How big the frame is drawn; 0 fits it to the space.
  final Signal<double> zoom = Signal(0, debugLabel: 'uiZoom');

  /// How far the frame is moved from the middle.
  final Signal<Offset> pan = Signal(Offset.zero, debugLabel: 'uiPan');

  /// What "fit" came to last time — where a step in or out starts from.
  /// Worked out as the canvas is built, so it is a plain value; [shownZoom]
  /// is what anything else watches.
  double fittedZoom = 1;

  /// The zoom the canvas was last drawn at, as a percentage label reads it.
  /// Set after each frame ([syncShownZoom]), never while one is built.
  final Signal<double> shownZoom = Signal(1, debugLabel: 'uiShownZoom');

  /// Brings [shownZoom] up to what the canvas is drawn at.
  void syncShownZoom() {
    final now = currentZoom;
    if (shownZoom.value != now) shownZoom.value = now;
  }

  final Signal<bool> snap = Signal(true, debugLabel: 'uiSnap');
  final Signal<bool> grid = Signal(false, debugLabel: 'uiGrid');
  final Signal<double> gridStep = Signal(8, debugLabel: 'uiGridStep');
  final Signal<bool> rulers = Signal(true, debugLabel: 'uiRulers');
  final Signal<bool> showGuides = Signal(true, debugLabel: 'uiGuides');

  /// Outlines every element, not only the selected ones.
  final Signal<bool> boxes = Signal(false, debugLabel: 'uiBoxes');

  /// Whether a drag on the canvas is going on: the panels that show what
  /// it changes catch up when it ends, not on every move.
  final Signal<bool> dragging = Signal(false, debugLabel: 'uiDragging');

  static const List<double> zoomStops = [
    0.1,
    0.15,
    0.25,
    0.33,
    0.5,
    0.67,
    0.75,
    1,
    1.25,
    1.5,
    2,
    3,
    4,
  ];

  /// The zoom actually used, fit resolved.
  double get currentZoom => zoom.value == 0 ? fittedZoom : zoom.value;

  void zoomStep(int steps) {
    final now = currentZoom;
    final stops = zoomStops;
    var index = stops.indexWhere((z) => z >= now - 1e-6);
    if (index < 0) index = stops.length - 1;
    if (steps > 0 && stops[index] <= now + 1e-6) index++;
    if (steps < 0) index--;
    zoom.value = stops[index.clamp(0, stops.length - 1)];
  }

  /// Fits the frame to the space again and puts it back in the middle.
  void zoomToFit() => batch(() {
    zoom.value = 0;
    pan.value = Offset.zero;
  });

  /// Shows the open screen on [next], and remembers it with the screen.
  void setDevice(UiDevice next) {
    device.value = next;
    final doc = _doc;
    if (doc == null) return;
    // Remembered, not an edit: it is written with the next save but is
    // nothing to undo.
    doc.editorData.value = {...doc.editorData.value, 'device': next.toJson()};
  }

  /// The guides of the open screen. Entries that are no guide — a file
  /// edited by hand — are passed over.
  List<UiGuide> get guides {
    final saved = _doc?.editorData.value['guides'];
    return [
      if (saved is List)
        for (final g in saved) ?UiGuide.fromJson(g),
    ];
  }

  void setGuides(List<UiGuide> next, {String label = 'Move guide'}) =>
      _doc?.setEditorData('guides', [
        for (final g in next) g.toJson(),
      ], label: label);

  // ── Trying it ──────────────────────────────────────────────────────────

  final Signal<UiEditMode> mode = Signal(UiEditMode.edit, debugLabel: 'uiMode');

  bool get previewing => mode.value == UiEditMode.preview;

  /// The canvas Preview shows: a copy of the open screen's, which a player
  /// may change as they like (see the canvas view), or null outside
  /// Preview.
  Entity? previewCanvas;

  /// Other screens drawn underneath the open one, by name — the HUD under
  /// a pause menu.
  final Signal<List<String>> behind = Signal(const [], debugLabel: 'uiBehind');

  /// Buttons shown as though hovered, pressed or switched off.
  final Signal<UiInteractionState?> forcedState = Signal(
    null,
    debugLabel: 'uiForcedState',
  );

  /// Bigger or smaller text, as a player's settings would make it.
  final Signal<double> textScale = Signal(1, debugLabel: 'uiTextScale');

  /// Made-up values for the bindings the screen reads, so `{coins}` shows
  /// something while the game is not running.
  Map<String, String> get samples {
    final saved = _doc?.editorData.value['samples'];
    return {
      if (saved is Map)
        for (final entry in saved.entries)
          if (entry.value != null) '${entry.key}': '${entry.value}',
    };
  }

  void setSample(String binding, String? value) {
    final next = {...samples};
    if (value == null || value.isEmpty) {
      next.remove(binding);
    } else {
      next[binding] = value;
    }
    _doc?.setEditorData('samples', next, label: 'Sample $binding');
  }

  /// What was last done in the preview, for the strip to say — an action a
  /// button would run, which the editor shows rather than runs.
  final Signal<String?> lastAction = Signal(null, debugLabel: 'uiLastAction');

  // ── Where things are ───────────────────────────────────────────────────

  /// Each element's node, filled in as the screen is built — how the editor
  /// finds where each one landed.
  final UiNodeBoxes nodes = UiNodeBoxes();

  /// The canvas as last laid out, set by the canvas view each frame.
  UiCanvasMetrics? metrics;

  /// The lines a drag is lined up with, in design pixels, while it lasts.
  final Signal<List<SnapGuide>> snapGuides = Signal(
    const [],
    debugLabel: 'uiSnapGuides',
  );

  // ── Selection ──────────────────────────────────────────────────────────

  /// What is selected in the open screen, the primary first.
  List<Entity> get selection {
    final doc = _doc;
    if (doc == null) return const [];
    final state = doc.sceneState;
    final primary = state.selectedEntity.value;
    final ids = state.multiSelectedIds.value;
    return [
      ?primary,
      for (final id in ids)
        if (id != primary?.id) ?doc.world.getEntity(id),
    ];
  }

  void dispose() {
    _doc?.dispose();
    theme.value?.dispose();
    for (final s in [
      document,
      theme,
      manifest,
      manifestProblem,
      files,
      device,
      landscape,
      zoom,
      shownZoom,
      pan,
      snap,
      grid,
      gridStep,
      rulers,
      showGuides,
      boxes,
      dragging,
      mode,
      behind,
      forcedState,
      textScale,
      lastAction,
      snapGuides,
    ]) {
      s.dispose();
    }
    if (_ownsContext) context.dispose();
  }
}
