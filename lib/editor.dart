/// The Interface editor, as a module of `just_game_engine_editor`.
///
/// Design-time only: a game imports `package:just_ui_editor/
/// just_ui_editor.dart` and never this library, so nothing of the editor
/// reaches a release build through here.
library;

export 'src/editor/canvas/ui_canvas_view.dart' show UiCanvasView, UiPaletteDrag;
export 'src/editor/create/ui_create.dart';
export 'src/editor/document/ui_screen_document.dart';
export 'src/editor/project/ui_level_screens.dart';
export 'src/editor/project/ui_project.dart';
export 'src/editor/session/ui_device.dart';
export 'src/editor/session/ui_edit_ops.dart';
export 'src/editor/session/ui_editor_session.dart';
export 'src/editor/theme/ui_theme_document.dart';
export 'src/editor/ui_editor_module.dart';
export 'src/editor/validation/ui_checks.dart';
export 'src/editor/workspace/ui_workspace.dart';
