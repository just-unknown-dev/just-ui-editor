/// Keeps the interface in step with the game.
///
/// Text that reads the game is re-read here, text that types itself out is
/// advanced here, and the screen layer is told when any of it changed —
/// once a frame, in one place, so the widgets rebuild only when they must.
/// Moving letters are not a change: whoever draws them animates them.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import '../theme/theme.dart';
import 'ui_text_component.dart';

/// Re-reads every text's bindings and types text out, once a frame, and
/// says when any of it changed.
class UiTextSystem extends System {
  /// [localize] turns `@keys` into words; null takes the engine's.
  UiTextSystem({this.localize});

  /// How a `@key` becomes words; null takes the engine's
  /// ([UiWorldStyle.localize]), and with neither a key shows as written.
  String Function(String key)? localize;

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
  List<Type> get requiredComponents => [UiTextComponent];

  @override
  void update(double deltaTime) {
    final words = localize ?? UiWorldStyle.of(world.context).localize;
    final bindings = UiBindings.of(world.context);
    _live.clear();
    var changed = false;
    forEach((entity) {
      _live.add(entity);
      final text = entity.getComponent<UiTextComponent>()!;
      text.elapsed += deltaTime;

      // Once a frame: the painter and the screen layer reuse it.
      final resolved = text.resolve(bindings, self: entity, localize: words);
      text.resolvedIn = world.updateCount;
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
}
