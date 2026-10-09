/// A game's screens, in a world of their own.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_game_engine/just_game_engine.dart';

import '../components/screen/ui_canvas_component.dart';
import '../layer/ui_navigator.dart';
import '../logic/ui_actions.dart';
import '../logic/ui_bindings.dart';
import '../systems/ui_system.dart';
import '../theme/ui_theme.dart';
import '../just_game_ui.dart';
import 'ui_document.dart';
import 'ui_screen_manifest.dart';

/// Reads a text asset: the bundle in a game, a file in the editor, a map in
/// a test.
typedef UiAssetReader = Future<String> Function(String path);

/// Every screen a game has, built once and kept for the whole game.
///
/// Screens live in a [World] of their own, not the level's: loading a level,
/// or clearing it to restart, never takes the pause menu with it. What
/// keeps them alive — bindings re-read, text typed out, timelines played —
/// runs in [update], which the engine calls every frame whether or not the
/// game is paused (see `UiScreensPlugin`), so a menu works while the game
/// it paused is stopped.
///
/// The screens' world shares the game world's context (its definitions, its
/// timeline signals), so an action on a screen that emits a signal reaches
/// the level's timelines. With no game world it gets a context of its own.
/// The interface's components are installed into whichever it is.
class UiScreens {
  UiScreens({World? world, this.localise, this.gameWorld})
    : world = world ?? (World(context: gameWorld?.context)..initialize()) {
    this.world.context.install(JustGameUi.extension);
    UiBindings.registerBuiltIns();
    this.world
      ..addSystem(system)
      ..addSystem(TimelineSystem());
  }

  /// Where the screens are.
  final World world;

  /// The game's world, for actions that name something in it.
  final World? gameWorld;

  /// How a `@key` becomes words.
  final String Function(String key)? localise;

  /// Keeps text in step; tells whoever draws the screens when it changed.
  late final UiSystem system = UiSystem(localise: localise);

  /// Which screens are open.
  late final UiNavigator navigator = UiNavigator(world);

  final List<_Loaded> _loaded = [];

  /// The screen list they were loaded from, if any.
  UiScreenManifest? manifest;

  /// The screens, by name, in the order they were loaded.
  List<String> get names => [for (final l in _loaded) l.document.name];

  /// The document [name] was built from, or null.
  UiDocument? documentOf(String name) {
    for (final l in _loaded) {
      if (l.document.name == name) return l.document;
    }
    return null;
  }

  /// The canvas of the screen called [name], or null.
  Entity? canvasOf(String name) {
    for (final l in _loaded) {
      if (l.document.name == name && world.isEntityAlive(l.canvas)) {
        return l.canvas;
      }
    }
    return null;
  }

  /// Reads [manifest] and every screen it lists, and builds them.
  ///
  /// [read] fetches a text asset; the app bundle when null. A screen that
  /// will not read is left out and said so, rather than stopping the game.
  Future<void> loadManifest(
    UiScreenManifest manifest, {
    UiAssetReader? read,
  }) async {
    final fetch = read ?? rootBundle.loadString;
    this.manifest = manifest;
    for (final entry in manifest.screens) {
      try {
        final json = jsonDecode(await fetch(entry.path));
        add(
          UiDocument.fromJson((json as Map).cast<String, dynamic>()),
          startOpen: entry.startOpen,
        );
      } on Object catch (error) {
        debugPrint('just_ui_editor: screen ${entry.path} did not load: $error');
      }
    }
    await loadThemes();
  }

  /// Throws every screen away and reads [manifest]'s again — after one was
  /// saved while the game runs in an editor.
  Future<void> reloadFrom(
    UiScreenManifest manifest, {
    UiAssetReader? read,
  }) async {
    for (final l in List.of(_loaded)) {
      _destroyTree(l.canvas);
    }
    _loaded.clear();
    navigator.popToRoot();
    await loadManifest(manifest, read: read);
  }

  /// Reads the themes the screen list and the canvases name, so the first
  /// frames are not drawn with the fallback.
  Future<void> loadThemes() async {
    final theme = manifest?.theme;
    if (theme != null) {
      await UiThemes.usePreview(theme);
      // What a screen that names no theme is drawn with.
      UiThemes.fallback = UiThemes.preview;
    }
    await UiThemes.loadFor(world);
  }

  /// Builds [document] as one of the screens, open from the start when
  /// [startOpen]. A screen already there with its name is replaced.
  Entity add(UiDocument document, {bool startOpen = false}) {
    remove(document.name);
    final canvas = document.instantiate(world);
    _loaded.add(_Loaded(document, canvas, startOpen));
    _open(canvas, startOpen);
    return canvas;
  }

  /// Takes the screen called [name] away.
  void remove(String name) {
    for (final l in _loaded.where((l) => l.document.name == name).toList()) {
      _destroyTree(l.canvas);
      _loaded.remove(l);
    }
    navigator.adopt();
  }

  /// Every screen as it was first built: typed text, ticked boxes and open
  /// menus all back to how they started — a restart.
  void reset() {
    final loaded = List.of(_loaded);
    _loaded.clear();
    for (final l in loaded) {
      _destroyTree(l.canvas);
    }
    for (final l in loaded) {
      final canvas = l.document.instantiate(world);
      _loaded.add(_Loaded(l.document, canvas, l.startOpen));
      _open(canvas, l.startOpen);
    }
    navigator.adopt();
  }

  void _open(Entity canvas, bool open) {
    final component = canvas.getComponent<UiCanvasComponent>();
    if (component == null) return;
    component
      ..visible = open
      ..markDirty();
    navigator.adopt();
  }

  void _destroyTree(Entity root) {
    final children = root.getComponent<ChildrenComponent>()?.childIds;
    for (final id in List.of(children ?? const <EntityId>[])) {
      final child = world.getEntity(id);
      if (child != null) _destroyTree(child);
    }
    if (world.isEntityAlive(root)) world.destroyEntity(root);
  }

  /// Whether the screen or layer called [name] is showing.
  bool isOpen(String name) =>
      canvasOf(name)?.getComponent<UiCanvasComponent>()?.visible ?? false;

  /// Opens [name] over what is open.
  void push(String name) => navigator.push(name);

  /// Closes the screen on top.
  void back() => navigator.back();

  /// Shows [name] (a screen goes on the stack; a layer appears).
  void show(String name) => navigator.show(name, true);

  /// Hides [name].
  void hide(String name) => navigator.show(name, false);

  /// Closes every screen, leaving the layers.
  void closeAll() => navigator.popToRoot();

  /// What `ui.show`, `ui.push` and `ui.back` reach — the actions' defaults
  /// once the interface is installed.
  UiActionHost get host => navigator.fillingIn(const UiActionHost());

  /// One frame of the screens' own systems.
  void update(double dt) => world.update(dt);

  void dispose() {
    system.onChanged = null;
    world.dispose();
  }
}

class _Loaded {
  _Loaded(this.document, this.canvas, this.startOpen);

  final UiDocument document;
  final Entity canvas;
  final bool startOpen;
}
