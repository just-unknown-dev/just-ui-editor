/// What the interface renamed, so files saved before still load.
library;

import 'package:just_game_engine/just_game_engine.dart';

/// The interface's renamed components, for files saved before the rename.
///
/// Installing `JustGameUi.extension` adds [renamedTypes] to the context's
/// migrations (`context.migrations`), and a scene, a prefab or a timeline
/// is renamed through those on every load, whatever its format. A screen
/// (`.ui.json`) is renamed as it is read: `UiDocument`'s format 2 step, and
/// the reader's hooks after it.
abstract final class UiMigrations {
  /// Old component type → new.
  ///
  /// 0.2.0-alpha.1: the two components a level can hold took the package's
  /// `Ui` prefix, so their saved names no longer collide with a game's own.
  /// Renames chain: keep the old entries when renaming again.
  static const Map<String, String> renamedTypes = {
    'TextComponent': 'UiTextComponent',
    'ButtonComponent': 'UiButtonComponent',
  };

  /// Adds [renamedTypes] to [context]'s migrations. Installing
  /// `JustGameUi.extension` calls it.
  static void install(EngineContext context) =>
      context.migrations.renamedTypes.addAll(renamedTypes);

  /// Migration hooks holding [renamedTypes] and nothing else: what a file
  /// read with no engine context is renamed through.
  static MigrationHooks hooks() =>
      MigrationHooks()..renamedTypes.addAll(renamedTypes);
}
