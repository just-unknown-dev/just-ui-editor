// The interface's components after a hot reload, in an editor: put in place
// again as the code now makes them (EngineContext.refreshDefinitions), as
// often as the editor asks.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  test('the interface extension is refreshable', () {
    expect(JustGameUi.extension, isA<RefreshableExtension>());
  });

  test('refreshing puts each component in place again, every time', () {
    final context = EngineContext(extensions: [JustGameUi.extension]);
    final before = {
      for (final d in context.definitions.definitions) d.type: d,
    };

    context
      ..refreshDefinitions()
      ..refreshDefinitions();

    final after = {for (final d in context.definitions.definitions) d.type: d};
    expect(after.keys, unorderedEquals(before.keys));
    for (final type in ['UiCanvasComponent', 'UiLayoutComponent']) {
      expect(after[type], isNotNull, reason: type);
      expect(identical(after[type], before[type]), isFalse, reason: type);
    }
  });
}
