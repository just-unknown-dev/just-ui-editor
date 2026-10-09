/// The interface editor, plugged into `just_game_engine_editor`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../runtime/components/button_component.dart';
import '../runtime/components/screen/ui_canvas_component.dart';
import '../runtime/components/text_component.dart';
import '../runtime/just_game_ui.dart';
import '../runtime/screens/ui_document.dart';
import '../runtime/screens/ui_screen_manifest.dart';
import '../runtime/screens/ui_screens_layer.dart';
import '../runtime/text/ui_fonts.dart';
import '../runtime/theme/ui_theme.dart';
import 'inspector/ui_extras.dart';
import 'inspector/ui_field_builders.dart';
import 'project/ui_level_screens.dart';
import 'project/ui_project.dart';
import 'validation/ui_checks.dart';
import 'workspace/ui_workspace.dart';

/// Adds the Interface editor to the engine editor:
///
/// - a workspace for the game's screens (`.ui.json`) and themes
///   (`.uitheme.json`), from the toolbar, from Ctrl+Shift+U, or by opening
///   one of those files in the Assets dock;
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
      ),
    ),
  ];

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'ui.open',
      icon: Icons.web_asset_rounded,
      tooltip: "Interface — the game's screens (Ctrl+Shift+U)",
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
      scope: CommandScope.editor,
      run: (c) => c.scope.openWorkspace(workspaceId),
    ),
    DesignerCommand(
      id: 'ui.moveScreensOut',
      label: 'Move screens out of the level',
      scope: CommandScope.editor,
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
  List<UiMovedScreen> moveScreensOut(EditorScope scope) {
    final moved = UiLevelScreens.moveOut(
      world: scope.world,
      sceneState: scope.sceneState,
      history: scope.history,
      codec: scope.codec,
      project: project,
    );
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
    onAssetChanged(UiScreenManifest.defaultPath);
    return moved;
  }

  @override
  List<KeyBinding> get keyBindings => const [
    KeyBinding(LogicalKeyboardKey.keyU, 'ui.open', control: true, shift: true),
  ];

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

  @override
  Map<String, FieldEditorBuilder> get fieldEditors => UiFieldEditors.all;

  @override
  List<ComponentEditorExtras> get componentExtras => UiExtras.all;

  @override
  List<InheritedColor> get inheritedColors => const [uiInheritedColor];

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
      color: BuiltInPrefabs.shapeColor,
      placement: PrefabPlacement.point,
      defaultSize: const Size(160, 32),
      description: 'Words in the level — which can read the game.',
      namePrefix: 'Text',
      build: (position, size) => [
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        LayerComponent(),
        TextComponent(text: 'Text', size: size),
      ],
    ),
  ];

  @override
  List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'ui.world',
      of: (e) => e.hasComponent<TextComponent>()
          ? Icons.text_fields
          : e.hasComponent<ButtonComponent>()
          ? Icons.smart_button
          : null,
    ),
  ];

  @override
  void onRegister(EditorModuleContext context) {
    _scope = context.scope;
    // Themes and fonts from the project's files, not the bundle: saved a
    // moment ago, shown without a rebuild.
    final files = project;
    UiThemes.loader = files.loadTheme;
    UiFonts.read = files.fontData;
    unawaited(_reloadFonts());
    // Authoring shows the level, not the game's screens over it.
    _scope?.engine?.layers.setEnabled(UiScreensLayer.layerId, false);
  }

  Future<void> _reloadFonts([String? path]) async {
    UiFonts.reset();
    await UiFonts.loadAll(path != null ? [path] : project.fontFiles());
  }

  @override
  void onAssetChanged(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.uitheme.json')) {
      UiThemes.evict(path);
      unawaited(UiThemes.load(path));
    } else if (lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.ttc')) {
      unawaited(_reloadFonts(path));
    } else if (lower.endsWith('.${UiDocument.extension}') ||
        lower.endsWith('screens.json')) {
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
  void onPlayStateChanged(bool playing) => unawaited(_follow(playing));

  /// The game's screens while a play-test runs, as the game would show
  /// them from its first frame; gone again, and reset, when it stops.
  Future<void> _follow(bool playing) async {
    final engine = _scope?.engine;
    if (engine == null) return;
    var installed = JustGameUi.of(engine);
    if (playing && installed == null) {
      try {
        installed = await JustGameUi.install(engine, read: project.read);
      } on Object {
        // No screen list yet: a play-test with no screens.
        return;
      }
    }
    installed?.screens.reset();
    engine.layers.setEnabled(UiScreensLayer.layerId, playing);
  }
}
