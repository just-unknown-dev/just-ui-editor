/// Everything the interface needs to run.
library;

import '../logic/ui_bindings.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'ui_pointer_system.dart';
import 'ui_system.dart';

/// Adds what keeps the interface alive: bindings re-read, text typed out,
/// world buttons pressed. A game that shows any UI calls this once at boot.
///
/// Systems already in [world] are kept, and given [localise] and [onSound]
/// when those are passed — so calling it again (installing the interface
/// again) takes the new ones rather than leaving the first.
void registerUiSystems(
  World world, {
  String Function(String key)? localise,
  void Function(String path)? onSound,
}) {
  UiBindings.registerBuiltIns();
  final text = world.getSystem<UiSystem>();
  if (text == null) {
    world.addSystem(UiSystem(localise: localise));
  } else if (localise != null) {
    text.localise = localise;
  }
  final pointer = world.getSystem<UiPointerSystem>();
  if (pointer == null) {
    world.addSystem(UiPointerSystem(onSound: onSound));
  } else if (onSound != null) {
    pointer.onSound = onSound;
  }
}
