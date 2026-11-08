/// A game's screens, in a world of their own.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import '../controls/controls.dart';
import '../layout/layout.dart';
import '../theme/theme.dart';
import 'just_game_ui.dart';
import 'ui_document.dart';
import 'ui_navigator.dart';
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
  UiScreens({World? world, this.localize, this.gameWorld})
    : world = world ?? (World(context: gameWorld?.context)..initialize()) {
    this.world.context.install(JustGameUi.extension);
    this.world
      ..addSystem(system)
      ..addSystem(TimelineSystem());
  }

  /// Where the screens are.
  final World world;

  /// The game's world, for actions that name something in it.
  final World? gameWorld;

  /// How a `@key` becomes words.
  final String Function(String key)? localize;

  /// Keeps text in step; tells whoever draws the screens when it changed.
  late final UiTextSystem system = UiTextSystem(localize: localize);

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
  /// [read] fetches a text asset; the context's bundle when null. A screen
  /// that will not read is left out and said so, rather than stopping the
  /// game. Each is read with the context's migrations
  /// (`context.migrations`), so a component a package renamed loads under
  /// its new name.
  Future<void> loadManifest(
    UiScreenManifest manifest, {
    UiAssetReader? read,
  }) async {
    final fetch = read ?? world.context.bundle.loadString;
    this.manifest = manifest;
    for (final entry in manifest.screens) {
      try {
        final json = jsonDecode(await fetch(entry.path));
        add(
          UiDocument.fromJson(
            (json as Map).cast<String, dynamic>(),
            hooks: world.context.migrations,
          ),
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
  ///
  /// The list's theme becomes the context's [UiThemes.fallback]: what a
  /// screen that names no theme is drawn with, and what text and buttons in
  /// the level are drawn with ([UiWorldStyle]). [dispose] puts the built-in
  /// one back — unless newer screens have chosen since.
  Future<void> loadThemes() async {
    final themes = UiThemes.of(world.context);
    final theme = manifest?.theme;
    if (theme != null) {
      await themes.usePreview(theme);
      themes.useFallback(themes.preview, owner: this);
    }
    // A painter cannot wait for a file: a canvas whose theme has not
    // arrived draws with the fallback and picks the real one up a frame
    // later. Read here, that window is a frame or two rather than for ever.
    final paths = <String>{
      for (final entity in world.query(const [UiCanvasComponent]))
        if (entity.getComponent<UiCanvasComponent>()!.theme case final path
            when path.isNotEmpty)
          path,
    };
    for (final path in paths) {
      await themes.load(path);
    }
  }

  /// Builds [document] as one of the screens, open from the start when
  /// [startOpen]. A screen already there with its name is replaced — once
  /// the new one has been built, so a file that will not read leaves the
  /// old one standing.
  Entity add(UiDocument document, {bool startOpen = false}) {
    final canvas = document.instantiate(world);
    _removeLoaded(document.name);
    _loaded.add(_Loaded(document, canvas, startOpen));
    _open(canvas, startOpen);
    return canvas;
  }

  /// Takes the screen called [name] away.
  void remove(String name) {
    _removeLoaded(name);
    navigator.adopt();
  }

  void _removeLoaded(String name) {
    for (final l in _loaded.where((l) => l.document.name == name).toList()) {
      _destroyTree(l.canvas);
      _loaded.remove(l);
    }
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
  ///
  /// A button pressed on a screen keeps [UiButtonComponent.wasPressed] for
  /// one of these, as a button in the level does for one frame, and then
  /// lets it go.
  void update(double dt) {
    for (final entity in world.query(const [UiButtonComponent])) {
      final button = entity.getComponent<UiButtonComponent>()!;
      if (!button.wasPressed) {
        _pressSeen.remove(button);
      } else if (!_pressSeen.add(button)) {
        button.wasPressed = false;
        _pressSeen.remove(button);
      }
    }
    world.update(dt);
  }

  /// Buttons whose press has had its frame.
  final Set<UiButtonComponent> _pressSeen = {};

  /// Lets the screens go: their world, and the theme their list chose (the
  /// next screens, or a test, start from the built-in look).
  void dispose() {
    system.onChanged = null;
    UiThemes.of(world.context).releaseFallback(this);
    world.dispose();
  }
}

class _Loaded {
  _Loaded(this.document, this.canvas, this.startOpen);

  final UiDocument document;
  final Entity canvas;
  final bool startOpen;
}
