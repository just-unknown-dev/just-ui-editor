// The interface's field types: what they save, and what a hand-edited
// value of the wrong shape reads as.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  const constraints = FieldConstraints();

  test('each type round-trips its value', () {
    const style = UiTextStyle(size: 18, color: Color(0xFF112233));
    expect(
      UiFieldTypes.uiTextStyle.decode(
        UiFieldTypes.uiTextStyle.encode(style),
        constraints,
      ),
      style,
    );
    const actions = UiActionList([UiAction('ui.push', 'Pause')]);
    expect(
      UiFieldTypes.uiActions.decode(
        UiFieldTypes.uiActions.encode(actions),
        constraints,
      ),
      actions,
    );
    expect(
      UiFieldTypes.uiAnchor.decode(
        UiFieldTypes.uiAnchor.encode(UiAnchor.center),
        constraints,
      ),
      UiAnchor.center,
    );
    expect(
      UiFieldTypes.uiText.decode('Coins: {coins}', constraints),
      'Coins: {coins}',
    );
  });

  test('a value of the wrong shape is handed back as it is', () {
    // So a hand edit gone wrong is a type error on write, naming the field,
    // never a default that quietly replaces what was there.
    expect(UiFieldTypes.uiTextStyle.decode('big', constraints), 'big');
    expect(UiFieldTypes.uiActions.decode({'kind': 'x'}, constraints), {
      'kind': 'x',
    });
    expect(UiFieldTypes.uiAnchor.decode(3, constraints), 3);
  });

  test('every type has an id of its own', () {
    final ids = [for (final t in UiFieldTypes.all) t.id];
    expect(ids.toSet(), hasLength(ids.length));
  });
}
