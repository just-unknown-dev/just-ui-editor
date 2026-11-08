/// How an engine learns the interface's components: `JustGameUi.extension`.
library;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:meta/meta.dart';

import 'ui_migrations.dart';
import 'ui_screen_definitions.dart';
import 'ui_world_definitions.dart';

/// Installs every interface component's definition into a context — the
/// screen-space ones and the world-space text and buttons — and the
/// interface's renamed components into its migrations ([UiMigrations]).
///
/// Never overrides, so a project's own replacement stays; installed once per
/// context. What `JustGameUi.extension` is.
@internal
final class UiComponentsExtension implements RefreshableExtension {
  /// The one there is.
  const UiComponentsExtension();

  @override
  String get id => 'just_ui_editor';

  @override
  void install(EngineContext context) {
    context.definitions
      ..registerAll(UiScreenDefinitions.all, ifAbsent: true)
      ..registerAll(UiWorldDefinitions.all, ifAbsent: true);
    UiMigrations.install(context);
  }

  /// After a hot reload, in an editor: the interface's components as the
  /// code now makes them.
  @override
  void refresh(EngineContext context) {
    context.definitions
      ..refresh(UiScreenDefinitions.all)
      ..refresh(UiWorldDefinitions.all);
  }
}
