/// The Interface editor: the module, its workspace, and what they edit
/// with — the project's files, the open screen, the session and its edits.
///
/// Its canvas, inspector rows and panels are internal; they are reached
/// through the workspace.
library;

export 'canvas/ui_canvas_view.dart';
export 'document/ui_screen_document.dart';
export 'document/ui_theme_document.dart';
export 'geometry/ui_canvas_metrics.dart';
export 'project/ui_checks.dart';
export 'project/ui_level_screens.dart';
export 'project/ui_project.dart';
export 'project/ui_scene_extractor.dart';
export 'session/ui_create.dart';
export 'session/ui_device.dart';
export 'session/ui_editor_session.dart';
export 'session/ui_editor_session_edits.dart';
export 'ui_editor_module.dart';
export 'ui_editor_workspace.dart';
