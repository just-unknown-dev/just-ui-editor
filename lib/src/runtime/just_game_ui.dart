/// Plugging the interface into a game.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:just_game_engine/just_game_engine.dart';

import 'layer/ui_input_bridge.dart';
import 'screens/ui_screen_manifest.dart';
import 'screens/ui_screens.dart';
import 'screens/ui_screens_layer.dart';
import 'serialization/ui_definitions.dart';
import 'serialization/ui_schemas.dart';
import 'systems/register_ui_systems.dart';

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
  static const ContextExtension extension = _JustGameUiExtension();

  /// Puts the interface into [engine]: the screens listed in [manifest]
  /// (built once, kept across levels, those marked `startOpen` open), drawn
  /// over the game in every `GameWidget` and ticked every frame; and the
  /// systems that keep text and buttons in the level's world working.
  ///
  /// [read] fetches a text asset — the app bundle when null. [input] names
  /// the actions that walk menus from a gamepad; null leaves them to the
  /// keyboard, mouse and touch. Installing again replaces the screens.
  static Future<UiScreensPlugin> install(
    Engine engine, {
    String manifest = UiScreenManifest.defaultPath,
    UiScreenManifest? screens,
    UiAssetReader? read,
    UiInputActions? input = const UiInputActions(),
    String Function(String key)? localise,
    void Function(String path)? onSound,
  }) async {
    engine.context.install(extension);
    registerUiSystems(engine.world, localise: localise, onSound: onSound);
    final fetch = read ?? rootBundle.loadString;
    final list =
        screens ??
        UiScreenManifest.fromJson(
          (jsonDecode(await fetch(manifest)) as Map).cast<String, dynamic>(),
        );
    final built = UiScreens(localise: localise, gameWorld: engine.world);
    await built.loadManifest(list, read: fetch);
    final plugin = UiScreensPlugin(built);
    await engine.plugins.register(plugin);
    engine.layers.register(
      UiScreensLayer(built, input: input, localise: localise, onSound: onSound),
    );
    return plugin;
  }

  /// What [install] put into [engine], or null before it ran.
  static UiScreensPlugin? of(Engine engine) =>
      engine.plugins.byId(UiScreensPlugin.pluginId) as UiScreensPlugin?;

  /// Takes the interface out of [engine] again.
  static void uninstall(Engine engine) {
    engine.layers.unregister(UiScreensLayer.layerId);
    engine.plugins.unregister(UiScreensPlugin.pluginId);
  }
}

final class _JustGameUiExtension implements RefreshableExtension {
  const _JustGameUiExtension();

  @override
  String get id => 'just_ui_editor';

  @override
  void install(EngineContext context) {
    context.definitions
      ..registerAll(UiDefinitions.all, ifAbsent: true)
      ..registerAll(UiSchemas.all, ifAbsent: true);
  }

  /// After a hot reload, in an editor: the interface's components as the
  /// code now makes them.
  @override
  void refresh(EngineContext context) {
    context.definitions
      ..refresh(UiDefinitions.all)
      ..refresh(UiSchemas.all);
  }
}
