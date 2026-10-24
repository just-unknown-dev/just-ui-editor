/// Keeps the interface in step with the game.
///
/// Text that reads the game is re-read here, text that types itself out is
/// advanced here, and the screen layer is told when any of it changed —
/// once a frame, in one place, so the widgets rebuild only when they must.
/// Moving letters are not a change: whoever draws them animates them.
library;

import '../logic/ui_bindings.dart';
import 'package:just_game_engine/just_game_engine.dart';
import '../components/text_component.dart';
import '../theme/ui_world_style.dart';

class UiSystem extends System {
  UiSystem({this.localise});

  /// How a `@key` becomes words; null takes the engine's
  /// ([UiWorldStyle.localise]), and with neither a key shows as written.
  String Function(String key)? localise;

  /// Called when something about the interface changed — the screen layer's
  /// `sync`. Set by whoever mounts the layer.
  void Function()? onChanged;

  /// Goes up by one every frame a text reads differently or types on. For
  /// more than one view of the same screens: each compares it with the
  /// count it last saw.
  int changes = 0;

  // What each text last resolved to, so a binding that reads the same is
  // not a change. Comparing strings beats rebuilding widgets.
  final Map<Entity, String> _lastText = {};
  final Set<Entity> _live = {};

  // Just before rendering: what a system did this frame shows this frame.
  @override
  int get priority => SystemPriorities.render + 1;

  @override
  List<Type> get requiredComponents => [TextComponent];

  @override
  void update(double deltaTime) {
    final words = localise ?? UiWorldStyle.of(world.context).localise;
    _live.clear();
    var changed = false;
    forEach((entity) {
      _live.add(entity);
      final text = entity.getComponent<TextComponent>()!;
      text.elapsed += deltaTime;

      // Once a frame: the painter and the screen layer reuse it.
      final resolved = text.resolve(self: entity, localise: words);
      if (_lastText[entity] != resolved.plain) {
        _lastText[entity] = resolved.plain;
        changed = true;
      }

      if (text.revealSpeed > 0) {
        final total = resolved.length;
        if (text.revealed < total) {
          text.revealed += deltaTime * text.revealSpeed;
          if (text.revealed > total) text.revealed = total.toDouble();
          changed = true;
        }
      }
    });
    // Texts that have gone: only when there are some.
    if (_lastText.length != _live.length) {
      _lastText.removeWhere((entity, _) => !_live.contains(entity));
    }

    if (changed) {
      changes++;
      onChanged?.call();
    }
  }

  /// Reads every binding a text asks for, for the editor's Problems dock.
  static List<String> missingBindings(World world) {
    final missing = <String>{};
    for (final entity in world.query([TextComponent])) {
      final text = entity.getComponent<TextComponent>()!;
      for (final name in UiBindings.namesIn(text.text)) {
        if (!UiBindings.has(name)) missing.add(name);
      }
    }
    return missing.toList()..sort();
  }
}
