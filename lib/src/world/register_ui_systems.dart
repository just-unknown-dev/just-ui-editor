/// Everything the interface needs to run.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../controls/controls.dart';
import 'ui_pointer_system.dart';

/// Adds what keeps the interface alive: bindings re-read, text typed out,
/// world buttons pressed. A game that shows any UI calls this once at boot.
///
/// Systems already in [world] are kept, and given [localize] and [onSound]
/// when those are passed — so calling it again (installing the interface
/// again) takes the new ones rather than leaving the first.
void registerUiSystems(
  World world, {
  String Function(String key)? localize,
  void Function(String path)? onSound,
}) {
  final text = world.getSystem<UiTextSystem>();
  if (text == null) {
    world.addSystem(UiTextSystem(localize: localize));
  } else if (localize != null) {
    text.localize = localize;
  }
  final pointer = world.getSystem<UiPointerSystem>();
  if (pointer == null) {
    world.addSystem(UiPointerSystem(onSound: onSound));
  } else if (onSound != null) {
    pointer.onSound = onSound;
  }
}
