/// The in-game interface for just_game_engine.
///
/// Screens are `.ui.json` assets drawn as real Flutter widgets over the
/// game; text and buttons can also sit in the world itself. Themes,
/// bindings (`{coins}`), actions (`ui.push Pause`) and game-registered
/// widgets tie them to the game.
///
/// This is what a game imports. The editor is `package:just_ui_editor/
/// editor.dart`, which a game never imports, so none of it reaches a
/// release build.
library;

export 'src/text/text.dart';
export 'src/bindings/bindings.dart';
export 'src/theme/theme.dart';
export 'src/layout/layout.dart';
export 'src/controls/controls.dart';
export 'src/world/world.dart';
export 'src/serialization/serialization.dart';
export 'src/screens/screens.dart';
