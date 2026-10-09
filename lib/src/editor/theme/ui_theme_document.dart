/// One theme open in the interface editor's Theme tab.
library;

import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/theme/ui_theme.dart';
import '../project/ui_project.dart';

/// A `.uitheme.json` being edited, with an undo history of its own.
///
/// Every edit is put straight into `UiThemes`, so each screen drawn with the
/// theme — the one on the canvas included — shows it at once, saved or not.
class UiThemeDocument {
  UiThemeDocument(this.path, UiTheme theme)
    : theme = Signal(theme, debugLabel: 'uiTheme') {
    history.markSaved();
  }

  /// Reads [path] from [project].
  static UiThemeDocument? open(UiProject project, String path) {
    final text = project.readSync(path);
    if (text == null) return null;
    try {
      return UiThemeDocument(path, UiTheme.parse(text));
    } on Object {
      return null;
    }
  }

  final String path;
  final Signal<UiTheme> theme;
  final EditorHistory history = EditorHistory();

  Signal<bool> get dirty => history.dirty;

  /// Changes the theme as one undoable step; consecutive changes with the
  /// same [label] — a colour being dragged — are one step.
  void change(UiTheme next, String label) {
    if (next == theme.value) return;
    history.push(
      _ThemeCommand(
        document: this,
        before: theme.value,
        after: next,
        label: label,
      ),
    );
  }

  void _apply(UiTheme value) {
    theme.value = value;
    UiThemes.put(path, value);
  }

  /// Writes it, and records that what is shown is what is saved.
  void save(UiProject project) {
    project.writeJsonSync(path, theme.value.toJson());
    history.markSaved();
  }

  void dispose() {
    history.dispose();
    theme.dispose();
  }
}

class _ThemeCommand extends EditorCommand {
  _ThemeCommand({
    required this.document,
    required this.before,
    required this.after,
    required this.label,
  });

  final UiThemeDocument document;
  final UiTheme before;
  UiTheme after;

  @override
  final String label;

  @override
  void redo() => document._apply(after);

  @override
  void undo() => document._apply(before);

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! _ThemeCommand || next.label != label) return false;
    after = next.after;
    return true;
  }
}
