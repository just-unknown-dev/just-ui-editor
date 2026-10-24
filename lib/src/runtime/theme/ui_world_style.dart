/// What text and buttons placed in a level are drawn with.
library;

import 'package:just_game_engine/just_game_engine.dart';

import 'ui_theme.dart';

/// The theme and the language for one engine's world-space text and
/// buttons, kept on its [EngineContext] rather than in a static, so two
/// engines (a game and an editor's preview) never share them.
///
/// `JustGameUi.install` fills this in from what it is given: the screen
/// list's theme and the `localise` function. Left alone, world text draws
/// with [UiThemes.fallback] and shows a `@key` as written — what an editor
/// wants to see.
final class UiWorldStyle {
  UiWorldStyle._();

  static final Object _slot = Object();

  /// The style of [context]'s worlds, made the first time it is asked for.
  static UiWorldStyle of(EngineContext context) =>
      context.slot(_slot, UiWorldStyle._);

  /// The theme world text and buttons are drawn with; null follows
  /// [UiThemes.fallback], which is the screen list's theme once the
  /// interface is installed.
  UiTheme? theme;

  /// How a `@key` becomes words; null shows the key.
  String Function(String key)? localise;

  /// The theme in use right now.
  UiTheme get resolvedTheme => theme ?? UiThemes.fallback;
}
