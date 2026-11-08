/// The interface editor, plugged into `just_game_engine_editor`.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/io.dart' show Directory;
import 'package:just_editor_core/just_editor_core.dart';

import '../controls/controls.dart';
import '../layout/layout.dart';
import '../screens/screens.dart';
import '../text/text.dart';
import '../theme/theme.dart';
import 'inspector/ui_extras.dart';
import 'inspector/ui_field_editors.dart';
import 'project/ui_checks.dart';
import 'project/ui_level_screens.dart';
import 'project/ui_project.dart';
import 'session/ui_editor_session.dart';
import 'ui_editor_workspace.dart';

/// Adds the Interface editor to the engine editor:
///
/// - a workspace for the game's screens (`.ui.json`) and themes
///   (`.uitheme.json`), from the toolbar, from Ctrl+Shift+U (Cmd+Shift+U on
///   macOS), or by opening one of those files in the Assets dock;
/// - the inspector rows for text styles, actions, anchors and theme roles,
///   which world-space text and buttons in a level use too;
/// - the Problems dock's checks of every screen;
/// - "Move screens out of the level", for a level from before screens
///   were files of their own;
/// - a Text prefab in every Level Designer's palette;
/// - the game's screens over the viewport while a play-test runs — and
///   only then.
///
/// ```dart
/// JustGameEditorPlugin.register(
///   engine: engine,
///   modules: [PlatformerModule(), UiEditorModule()],
/// );
/// ```
class UiEditorModule extends EditorModule {
  UiEditorModule({this.root});

  /// The project folder; the working directory when null.
  final String? root;

  static const String workspaceId = 'interface';

  EditorScope? _scope;

  /// The sessions of the Interface workspaces open now: told when a screen,
  /// the screen list or a theme changes on disk, so none writes over what
  /// changed with a copy read before.
  final Set<UiEditorSession> _sessions = {};

  UiProject get project => UiProject(root ?? Directory.current.path);

  @override
  String get id => 'just.ui_editor';

  @override
  String get name => 'Interface';

  @override
  IconData? get icon => Icons.web_asset_rounded;

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: workspaceId,
      label: 'Interface',
      icon: Icons.web_asset_rounded,
      order: 102,
      fileExtensions: const [UiDocument.extension, 'uitheme.json'],
      build: (context, workspace) => UiEditorWorkspace(
        scope: workspace.scope,
        project: project,
        path: workspace.path,
        onClose: workspace.onClose,
        onSaved: workspace.reloadAssets,
        fullScreen: workspace.fullScreen,
        onToggleFullScreen: workspace.onToggleFullScreen,
        setCloseGuard: workspace.setCloseGuard,
        onSession: (session, open) =>
            open ? _sessions.add(session) : _sessions.remove(session),
      ),
    ),
  ];

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'ui.open',
      icon: Icons.web_asset_rounded,
      tooltip: "Interface — the game's screens (${_openKey.shortcut})",
      order: 102,
      onPressed: (scope) => scope.openWorkspace(workspaceId),
      isActive: (scope) =>
          scope.activeWorkspace.value?.definition.id == workspaceId,
    ),
  ];

  @override
  List<DesignerCommand> get commands => [
    DesignerCommand(
      id: 'ui.open',
      label: 'Open the Interface editor',
      availability: CommandAvailability.editor,
      run: (c) => c.scope.openWorkspace(workspaceId),
    ),
    DesignerCommand(
      id: 'ui.moveScreensOut',
      label: 'Move screens out of the level',
      availability: CommandAvailability.editor,
      isEnabled: (c) => UiLevelScreens.of(c.scope.world).isNotEmpty,
      run: (c) => moveScreensOut(c.scope),
    ),
  ];

  @override
  List<SceneTreeAction> get sceneTreeActions => [
    SceneTreeAction(
      id: 'ui.moveScreensOut',
      label: 'Move screens out of the level',
      icon: Icons.drive_file_move_outline,
      isEnabled: (entity, scope) => entity.hasComponent<UiCanvasComponent>(),
      run: (entity, scope) => moveScreensOut(scope),
    ),
  ];

  /// Moves every screen still inside the open level out into files of its
  /// own on the game's list (see [UiLevelScreens.moveOut]), and says what
  /// went where in the editor's log.
  ///
  /// Nothing moves while the game's screen list does not read: the log
  /// says why, and the level is left as it is.
  List<UiMovedScreen> moveScreensOut(EditorScope scope) {
    final List<UiMovedScreen> moved;
    try {
      moved = UiLevelScreens.moveOut(
        world: scope.world,
        sceneState: scope.sceneState,
        history: scope.history,
        codec: scope.codec,
        project: project,
      );
    } on FormatException catch (error) {
      scope.log.log(
        'The screens were not moved out of the level: ${error.message}',
        source: 'interface',
      );
      return const [];
    }
    if (moved.isEmpty) return moved;
    for (final m in moved) {
      scope.log.log(
        m.was == null
            ? 'Moved the screen ${m.name} out of the level, to ${m.path}.'
            : 'Moved the screen ${m.was} out of the level, to ${m.path} — '
                  'as ${m.name}, since another screen is called ${m.was}.',
        source: 'interface',
      );
    }
    // The files are new: the Assets dock and the running game read them.
    scope.reloadAssets([
      for (final m in moved) m.path,
      UiScreenManifest.defaultPath,
    ]);
    return moved;
  }

  /// Opens the editor: Ctrl+Shift+U, Cmd+Shift+U on macOS.
  static const _openKey = KeyBinding(
    LogicalKeyboardKey.keyU,
    'ui.open',
    control: true,
    shift: true,
  );

  @override
  List<KeyBinding> get keyBindings => const [_openKey];

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: 'ui.edit',
      label: 'Edit in the Interface editor',
      icon: Icons.web_asset_rounded,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory &&
          (path.endsWith('.${UiDocument.extension}') ||
              path.endsWith('.uitheme.json')),
      run: (scope, path) => scope.openWorkspace(workspaceId, path: path),
    ),
  ];

  /// The engine being edited's context, once registered: its bindings,
  /// actions, widgets and themes are what the inspector offers.
  EngineContext? _context() => _scope?.context;

  @override
  Map<String, FieldEditorBuilder> get fieldEditors =>
      UiFieldEditors.all(_context);

  @override
  List<ComponentEditorExtras> get componentExtras => UiExtras.all(_context);

  @override
  List<InheritedColor> get inheritedColors => [
    UiFieldEditors.inheritedColor(_context),
  ];

  @override
  List<SceneValidator> get validators => const [UiChecks.run];

  @override
  List<String> get dataFileSuffixes => const [
    '.${UiDocument.extension}',
    '/screens.json',
    '.uitheme.json',
  ];

  /// Every Level Designer's, whichever module designs the level: the
  /// interface is not a designer itself.
  @override
  List<PrefabDefinition> get sharedPrefabs => [
    PrefabDefinition(
      id: 'ui.text',
      name: 'Text',
      category: 'Shapes',
      icon: Icons.text_fields,
      color: PrefabColors.shape,
      placement: PrefabPlacement.point,
      defaultSize: const Size(160, 32),
      description: 'Words in the level — which can read the game.',
      namePrefix: 'Text',
      build: (position, size) => [
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        LayerComponent(),
        UiTextComponent(text: 'Text', size: size),
      ],
    ),
  ];

  @override
  List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'ui.world',
      of: (e) => e.hasComponent<UiTextComponent>()
          ? Icons.text_fields
          : e.hasComponent<UiButtonComponent>()
          ? Icons.smart_button
          : null,
    ),
  ];

  @override
  void onRegister(EditorModuleContext context) {
    _scope = context.scope;
    _readFromProject();
    unawaited(_reloadFonts());
    unawaited(_styleLevelText());
    // Authoring shows the level, not the game's screens over it.
    _scope?.engine?.layers.setEnabled(UiScreensLayer.layerId, false);
  }

  /// What [onRegister] pointed the edited engine's `UiThemes` and `UiFonts`
  /// at, so [dispose] puts back only what is still this module's.
  Future<UiTheme> Function(String path)? _themeLoader;
  Future<ByteData> Function(String path)? _fontReader;

  /// The edited engine's themes and fonts from the project's files, not the
  /// bundle: saved a moment ago, shown without a rebuild. Another engine in
  /// the process (a game running beside the editor) keeps its own.
  void _readFromProject() {
    final context = _scope?.context;
    if (context == null) return;
    final files = project;
    UiThemes.of(context).loader = _themeLoader = files.loadTheme;
    UiFonts.of(context).read = _fontReader = files.fontData;
  }

  /// After a hot reload: the loaders handed out again, from the code as it
  /// is now.
  @override
  void onReassemble(EditorModuleContext context) {
    _scope = context.scope;
    _readFromProject();
  }

  /// The editor is going: themes and fonts are the bundle's again, unless
  /// something else has taken them over since.
  @override
  void dispose() {
    final context = _scope?.context;
    if (context != null) {
      final themes = UiThemes.of(context);
      if (_themeLoader != null && themes.loader == _themeLoader) {
        themes.useBundle();
      }
      final fonts = UiFonts.of(context);
      if (_fontReader != null && fonts.read == _fontReader) fonts.useBundle();
    }
    _themeLoader = null;
    _fontReader = null;
    _scope = null;
  }

  /// Every font in the project, read again. All of them, not just one that
  /// changed: forgetting what was loaded forgets every family, and one of
  /// several files of a family reloaded alone would be that family's only
  /// face.
  Future<void> _reloadFonts() async {
    final context = _scope?.context;
    if (context == null) return;
    final fonts = UiFonts.of(context)..reset();
    await fonts.loadAll(project.fontFiles());
  }

  /// The level's own text and buttons in the game's theme — the screen
  /// list's — as the game draws them, rather than the built-in one; none
  /// when the list names none.
  Future<void> _styleLevelText() async {
    final engine = _scope?.engine;
    if (engine == null) return;
    final path = project.readManifest().theme;
    final theme = path == null
        ? null
        : await UiThemes.of(engine.context).load(path);
    // Gone, or another asked for, while the theme was read.
    if (_scope?.engine != engine || project.readManifest().theme != path) {
      return;
    }
    UiWorldStyle.of(engine.context).theme = theme;
  }

  @override
  void onAssetChanged(String path) {
    final lower = path.toLowerCase();
    final context = _scope?.context;
    if (lower.endsWith('.uitheme.json')) {
      for (final session in List.of(_sessions)) {
        session.themeChanged(path);
      }
      if (context != null) {
        final themes = UiThemes.of(context)..evict(path);
        unawaited(themes.load(path));
      }
      if (project.readManifest().theme == path) {
        unawaited(_styleLevelText());
      }
    } else if (lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.ttc')) {
      unawaited(_reloadFonts());
    } else if (lower.endsWith('.${UiDocument.extension}') ||
        lower.endsWith('screens.json')) {
      if (lower.endsWith('screens.json')) unawaited(_styleLevelText());
      for (final session in List.of(_sessions)) {
        session.refreshFiles();
      }
      final engine = _scope?.engine;
      final installed = engine == null ? null : JustGameUi.of(engine);
      if (installed != null) {
        unawaited(
          installed.screens.reloadFrom(
            project.readManifest(),
            read: project.read,
          ),
        );
      }
    }
  }

  @override
  void onPlayStateChanged(bool playing) {
    _playing = playing;
    unawaited(_follow(playing));
  }

  /// Whether a play-test is running, as last heard: what a start that had
  /// to wait for files checks before it shows anything.
  bool _playing = false;

  /// An install under way, shared by every start that asks meanwhile.
  Future<UiScreensPlugin?>? _installing;

  /// The game's screens while a play-test runs, read from the files as
  /// they are now — the game's first frame — and gone again, and reset,
  /// when it stops.
  Future<void> _follow(bool playing) async {
    final engine = _scope?.engine;
    if (engine == null) return;
    var installed = JustGameUi.of(engine);
    if (!playing) {
      installed?.screens.reset();
      engine.layers.setEnabled(UiScreensLayer.layerId, false);
      return;
    }
    try {
      if (installed == null) {
        installed = await (_installing ??= _install(engine));
      } else {
        // Whatever was saved, moved or listed since the last play-test.
        await installed.screens.reloadFrom(
          project.readManifest(),
          read: project.read,
        );
      }
    } on Object {
      installed = JustGameUi.of(engine);
    }
    // Stopped while the files were read: nothing shows over the editor.
    if (!_playing || _scope == null) {
      installed?.screens.reset();
      engine.layers.setEnabled(UiScreensLayer.layerId, false);
      return;
    }
    engine.layers.setEnabled(UiScreensLayer.layerId, installed != null);
  }

  Future<UiScreensPlugin?> _install(Engine engine) async {
    try {
      // The editor reads the project's fonts itself (see onRegister).
      return await JustGameUi.install(engine, read: project.read, fonts: null);
    } on Object {
      // No screen list yet: a play-test with no screens.
      return null;
    } finally {
      _installing = null;
    }
  }
}
