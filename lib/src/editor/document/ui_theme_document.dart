/// One theme open in the interface editor's Theme tab.
library;

import 'dart:async';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../theme/theme.dart';
import '../project/ui_project.dart';

/// A `.uitheme.json` being edited, with an undo history of its own.
///
/// Every edit is put straight into [themes], so each screen drawn with the
/// theme — the one on the canvas included — shows it at once, saved or not.
class UiThemeDocument {
  /// [theme], as read from [path], edited for the engine whose [themes]
  /// show it.
  UiThemeDocument(this.path, UiTheme theme, {required this.themes})
    : theme = Signal(theme, debugLabel: 'uiTheme') {
    history.markSaved();
  }

  /// Reads [path] from [project], for the engine whose [themes] show it.
  static UiThemeDocument? open(
    UiProject project,
    String path, {
    required UiThemes themes,
  }) {
    final text = project.readSync(path);
    if (text == null) return null;
    try {
      return UiThemeDocument(path, UiTheme.parse(text), themes: themes);
    } on Object {
      return null;
    }
  }

  /// Where the theme is saved.
  final String path;

  /// The edited engine's themes: what every edit is shown through.
  final UiThemes themes;

  /// The theme as edited.
  final Signal<UiTheme> theme;
  final EditorHistory history = EditorHistory();

  /// Whether it holds edits not yet saved.
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
    themes.put(path, value);
  }

  /// Writes it, and records that what is shown is what is saved.
  void save(UiProject project) {
    project.writeJsonSync(path, theme.value.toJson());
    history.markSaved();
  }

  /// Lets the theme go. Edits it was showing unsaved go with it: every
  /// screen, the level's text and the next play-test read the file again,
  /// not what was dropped.
  void dispose() {
    if (dirty.value) {
      themes.evict(path);
      unawaited(themes.load(path));
    }
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
