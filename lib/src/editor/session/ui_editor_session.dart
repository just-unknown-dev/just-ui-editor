/// Everything the interface editor holds while it is open.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';
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

  static UiGuide? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = (json['at'] as num?)?.toDouble();
    if (at == null) return null;
    return UiGuide(vertical: json['axis'] == 'x', at: at);
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
  UiEditorSession({
    required this.project,
    SceneCodec? codec,
    EngineContext? context,
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

  /// Every screen file in the project, listed or not.
  final Signal<List<String>> files = Signal(const [], debugLabel: 'uiFiles');

  /// Reads the screen list and the files again — after something outside
  /// changed them.
  void refreshFiles() {
    _names = null;
    manifest.value = project.readManifest();
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
  /// could not be read.
  bool open(String path) {
    final UiDocument read;
    try {
      read = project.readScreen(path);
    } on Object {
      return false;
    }
    _replace(UiScreenDocument.open(path, read, codec: codec, context: context));
    return true;
  }

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

  /// Writes the open screen to its file. True when it was written.
  bool save() {
    final doc = _doc;
    if (doc == null) return false;
    project.writeScreen(doc.path, doc.capture());
    doc.markSaved();
    if (!files.value.contains(doc.path)) refreshFiles();
    return true;
  }

  /// Where a new screen called [name] is saved.
  String pathFor(String name, {String folder = 'assets/ui'}) =>
      '$folder/${UiSceneExtractor.fileNameFor(name)}';

  /// A name no listed screen has, from [base].
  String freeScreenName(String base) {
    final taken = {for (final path in files.value) _nameOfFile(path)};
    if (!taken.contains(base.toLowerCase())) return base;
    var n = 2;
    while (taken.contains('$base$n'.toLowerCase())) {
      n++;
    }
    return '$base$n';
  }

  static String _nameOfFile(String path) => path
      .split('/')
      .last
      .replaceAll('.${UiDocument.extension}', '')
      .replaceAll('_', '')
      .toLowerCase();

  /// Makes a new screen called [name], saves it, lists it, and opens it.
  UiScreenDocument createScreen(
    String name, {
    bool isScreen = true,
    bool startOpen = false,
  }) {
    final path = pathFor(name);
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
    project.writeScreen(path, doc.capture());
    doc.markSaved();
    _list(path, startOpen: startOpen);
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

  /// A copy of the screen at [path], under a name of its own, opened.
  bool duplicateScreen(String path) {
    final UiDocument source;
    try {
      source = project.readScreen(path);
    } on Object {
      return false;
    }
    final name = freeScreenName('${source.name}Copy');
    final renamed = source.renamed(name);
    final target = pathFor(name);
    project.writeScreen(target, renamed);
    _list(target, startOpen: manifest.value.entryFor(path)?.startOpen ?? false);
    return open(target);
  }

  /// Renames the screen at [path] — its canvas, its file, its entry in the
  /// list. False when [name] is taken or empty.
  bool renameScreen(String path, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final target = pathFor(trimmed);
    if (target != path && project.exists(target)) return false;
    final open = _doc;
    final wasOpen = open != null && open.path == path;
    if (wasOpen) {
      // The open one is renamed where it stands and written, unsaved
      // changes and all — a rename is not the moment to lose them.
      open.canvas.name = trimmed;
      project.writeScreen(target, open.capture());
      open.path = target;
      open.markSaved();
      open.sceneState.refresh();
    } else {
      final UiDocument source;
      try {
        source = project.readScreen(path);
      } on Object {
        return false;
      }
      project.writeScreen(target, source.renamed(trimmed));
    }
    if (target != path) project.deleteSync(path);
    final entries = [
      for (final e in manifest.value.screens)
        e.path == path ? e.copyWith(path: target) : e,
    ];
    project.writeManifest(manifest.value.withScreens(entries));
    refreshFiles();
    if (wasOpen) document.value = open;
    return true;
  }

  /// Deletes the screen at [path] and takes it off the list.
  void deleteScreen(String path) {
    if (_doc?.path == path) _replace(null);
    project.deleteSync(path);
    final entries = [
      for (final e in manifest.value.screens)
        if (e.path != path) e,
    ];
    project.writeManifest(manifest.value.withScreens(entries));
    refreshFiles();
  }

  /// Whether the screen at [path] shows from the game's first frame.
  void setStartOpen(String path, bool startOpen) {
    final list = manifest.value;
    final entries = list.entryFor(path) == null
        ? [...list.screens, UiScreenEntry(path: path, startOpen: startOpen)]
        : [
            for (final e in list.screens)
              e.path == path ? e.copyWith(startOpen: startOpen) : e,
          ];
    project.writeManifest(list.withScreens(entries));
    refreshFiles();
  }

  /// Puts [path] on the game's list, or takes it off.
  void setListed(String path, bool listed) {
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
    project.writeManifest(list.withScreens(entries));
    refreshFiles();
  }

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
  }

  // ── The theme ──────────────────────────────────────────────────────────

  /// The theme open in the Theme tab, or null.
  final Signal<UiThemeDocument?> theme = Signal(null, debugLabel: 'uiThemeDoc');

  /// Every theme in the project.
  List<String> get themeFiles => project.themeFiles();

  /// Opens the theme at [path] in the Theme tab. False when it would not
  /// read.
  bool openTheme(String path) {
    final next = UiThemeDocument.open(project, path);
    if (next == null) return false;
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

  /// Makes a theme at [path] from the built-in one, and opens it.
  void createTheme([String path = 'assets/ui/default.uitheme.json']) {
    if (!project.exists(path)) {
      project.writeJsonSync(
        path,
        UiTheme.fallback
            .copyWith(name: path.split('/').last.split('.').first)
            .toJson(),
      );
    }
    openTheme(path);
  }

  /// Saves the open theme; every screen drawn with it already shows it.
  bool saveTheme() {
    final open = theme.value;
    if (open == null) return false;
    open.save(project);
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

  /// The guides of the open screen.
  List<UiGuide> get guides => [
    for (final g in (_doc?.editorData.value['guides'] as List? ?? const []))
      ?UiGuide.fromJson(g),
  ];

  void setGuides(List<UiGuide> next, {String label = 'Move guide'}) =>
      _doc?.setEditorData('guides', [
        for (final g in next) g.toJson(),
      ], label: label);

  // ── Trying it ──────────────────────────────────────────────────────────

  final Signal<UiEditMode> mode = Signal(UiEditMode.edit, debugLabel: 'uiMode');

  bool get previewing => mode.value == UiEditMode.preview;

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
  Map<String, String> get samples => {
    for (final entry
        in ((_doc?.editorData.value['samples'] as Map?) ?? const {}).entries)
      '${entry.key}': '${entry.value}',
  };

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
