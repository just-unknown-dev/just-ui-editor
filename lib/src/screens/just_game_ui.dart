/// Plugging the interface into a game.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_game_engine/just_game_engine.dart';

import '../serialization/ui_components_extension.dart';
import '../text/text.dart';
import '../theme/theme.dart';
import '../world/world.dart';
import 'ui_input_bridge.dart';
import 'ui_screen_manifest.dart';
import 'ui_screens.dart';
import 'ui_screens_layer.dart';
import 'ui_screens_plugin.dart';

/// The interface's entry points for a game.
///
/// ```dart
/// final engine = Engine(
///   config: const EngineConfig(extensions: [JustGameUi.extension]),
/// );
/// await engine.initialize();
/// await JustGameUi.install(engine);       // reads assets/ui/screens.json
/// JustGameUi.of(engine)!.screens.push('Pause');
/// ```
abstract final class JustGameUi {
  /// How to save and load every interface component — canvases, slots,
  /// panels, controls, world-space text and buttons — for an engine's
  /// context.
  ///
  /// Give it to the engine before loading a scene or screen that uses them
  /// (`EngineConfig(extensions: [JustGameUi.extension])`, or
  /// `context.install(JustGameUi.extension)`); without it the loader stops
  /// with an error naming the first one it meets. Never overrides, so a
  /// project's own replacement stays; installed once per context. [install]
  /// installs it too.
  static const ContextExtension extension = UiComponentsExtension();

  /// Puts the interface into [engine]: the screens listed in [manifest]
  /// (built once, kept across levels, those marked `startOpen` open), drawn
  /// over the game in every `GameWidget` and ticked every frame; and the
  /// systems that keep text and buttons in the level's world working.
  ///
  /// [read] fetches a text asset — the context's bundle when null. A game
  /// with no screen list, one that will not read, or one that names no
  /// screens runs with no screens and says so in the log, as a screen file
  /// that will not read is left out.
  /// [input] names the actions that walk menus from a gamepad; null leaves
  /// them to the keyboard, mouse and touch. [localize] turns `@keys` into
  /// words everywhere — screens and the level's own text and buttons — and
  /// [onSound] plays the theme's sounds. Every font file under [fonts] in
  /// the bundle is loaded (the context's [UiFonts.loadFolder]), so a family the editor
  /// offered is the family the game draws; null loads none. Installing
  /// again replaces the screens.
  static Future<UiScreensPlugin> install(
    Engine engine, {
    String manifest = UiScreenManifest.defaultPath,
    UiScreenManifest? screens,
    UiAssetReader? read,
    UiInputActions? input = const UiInputActions(),
    String Function(String key)? localize,
    void Function(String path)? onSound,
    String? fonts = UiFonts.defaultFolder,
  }) async {
    engine.context.install(extension);
    registerUiSystems(engine.world, localize: localize, onSound: onSound);
    UiWorldStyle.of(engine.context).localize = localize;
    final fetch = read ?? engine.context.bundle.loadString;
    final list = screens ?? await _readList(manifest, fetch);
    if (list.screens.isEmpty) {
      // A game with no HUD and no menus looks fine until someone presses
      // pause: say so where its developer will see it.
      debugPrint(
        'just_ui_editor: the screen list ${screens == null ? manifest : '(given)'} '
        'names no screens: the game runs with no HUD and no menus.',
      );
    }
    if (fonts != null) await UiFonts.of(engine.context).loadFolder(fonts);
    final built = UiScreens(localize: localize, gameWorld: engine.world);
    await built.loadManifest(list, read: fetch);
    final plugin = UiScreensPlugin(built);
    await engine.plugins.register(plugin);
    engine.layers.register(
      UiScreensLayer(built, input: input, localize: localize, onSound: onSound),
    );
    return plugin;
  }

  /// What [install] put into [engine], or null before it ran.
  static UiScreensPlugin? of(Engine engine) =>
      engine.plugins.byId(UiScreensPlugin.pluginId) as UiScreensPlugin?;

  /// Takes the interface out of [engine] again: the screens, their layer,
  /// and the language its world text was given. The components stay known
  /// to the engine (a level may still hold them), and so do the level's
  /// text and button systems, which [install] hands new callbacks to if it
  /// runs again.
  static void uninstall(Engine engine) {
    engine.layers.unregister(UiScreensLayer.layerId);
    engine.plugins.unregister(UiScreensPlugin.pluginId);
    UiWorldStyle.of(engine.context)
      ..localize = null
      ..theme = null;
  }

  /// The screen list at [path], or an empty one when there is none or it
  /// will not read.
  static Future<UiScreenManifest> _readList(
    String path,
    UiAssetReader fetch,
  ) async {
    final String source;
    try {
      source = await fetch(path);
    } on Object catch (error) {
      debugPrint('just_ui_editor: no screen list at $path ($error).');
      return UiScreenManifest();
    }
    try {
      return UiScreenManifest.parse(source);
    } on Object catch (error) {
      debugPrint('just_ui_editor: the screen list $path did not read: $error');
      return UiScreenManifest();
    }
  }
}
