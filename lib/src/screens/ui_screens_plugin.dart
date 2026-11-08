/// What ticks a game's screens every frame.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import 'ui_screens.dart';

/// Ticks the screens every frame — paused or not, since a pause menu has to
/// work while the game it paused is stopped — and makes them the actions'
/// defaults while attached.
class UiScreensPlugin extends EnginePlugin {
  UiScreensPlugin(this.screens);

  /// What it is registered on [Engine.plugins] as.
  static const String pluginId = 'just_ui_editor.screens';

  final UiScreens screens;

  late final UiActionHost _host = screens.host;

  @override
  String get id => pluginId;

  @override
  Future<void> attach(Engine engine) async {
    UiActions.of(screens.world.context).defaults = _host;
  }

  @override
  void update(double deltaTime) => screens.update(deltaTime);

  @override
  void detach() {
    final actions = UiActions.of(screens.world.context);
    if (identical(actions.defaults, _host)) {
      actions.defaults = const UiActionHost();
    }
    screens.dispose();
  }
}
