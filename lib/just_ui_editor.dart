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

// Text: styles, rich-text tags, painting, fonts.
export 'src/runtime/text/ui_text_style.dart';
export 'src/runtime/text/ui_rich_text.dart';
export 'src/runtime/text/ui_text_painter.dart';
export 'src/runtime/text/ui_fonts.dart';

// Themes.
export 'src/runtime/theme/ui_theme.dart';
export 'src/runtime/theme/ui_world_style.dart';

// What the interface reads from the game and does to it.
export 'src/runtime/logic/ui_bindings.dart';
export 'src/runtime/logic/ui_actions.dart';

// Screens as real widgets.
export 'src/runtime/layer/ui_widgets.dart';
export 'src/runtime/layer/ui_layer.dart';
export 'src/runtime/layer/ui_navigator.dart';
export 'src/runtime/layer/ui_input_bridge.dart';

// Components.
export 'src/runtime/components/ui_component.dart';
export 'src/runtime/components/text_component.dart';
export 'src/runtime/components/button_component.dart';
export 'src/runtime/components/ui_painters.dart';
export 'src/runtime/components/screen/ui_canvas_component.dart';
export 'src/runtime/components/screen/ui_slot_component.dart';
export 'src/runtime/components/screen/ui_elements.dart';

// Systems.
export 'src/runtime/systems/ui_system.dart';
export 'src/runtime/systems/ui_pointer_system.dart';
export 'src/runtime/systems/register_ui_systems.dart';

// How it is saved.
export 'src/runtime/serialization/ui_definitions.dart';
export 'src/runtime/serialization/ui_schemas.dart';
export 'src/runtime/serialization/ui_field_types.dart';

// Plugging it into a game.
export 'src/runtime/just_game_ui.dart';

// Screens as assets: one .ui.json per screen, listed in screens.json.
export 'src/runtime/screens/ui_document.dart';
export 'src/runtime/screens/ui_screen_manifest.dart';
export 'src/runtime/screens/ui_screens.dart';
export 'src/runtime/screens/ui_screens_layer.dart';
export 'src/runtime/screens/ui_scene_extractor.dart';
