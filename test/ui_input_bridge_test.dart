// A menu worked from a gamepad: the d-pad walks it, Ⓐ presses, Ⓑ goes back —
// through input actions, while a screen is open, and never the keyboard's
// way twice.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_inputs/just_inputs.dart';
import 'package:just_inputs/testing.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);

/// W3C button indices by control name.
const _b = GamepadControls.buttonIndex;

const _asset = InputActionAsset(
  nextId: 20,
  maps: [
    ActionMapDef(
      id: 'm1',
      name: 'ui',
      actions: [
        InputActionDef(
          id: 'a2',
          name: 'navigate',
          type: ActionValueType.vector2,
          bindings: [
            ControlBindingDef(id: 'b3', path: '<Gamepad>/dpad'),
            CompositeBindingDef(
              id: 'b4',
              composite: CompositeKinds.vector2,
              parts: [
                CompositePartDef(
                  id: 'b5',
                  part: 'down',
                  path: '<Keyboard>/downArrow',
                ),
              ],
            ),
          ],
        ),
        InputActionDef(
          id: 'a6',
          name: 'submit',
          bindings: [
            ControlBindingDef(id: 'b7', path: '<Gamepad>/buttonSouth'),
          ],
        ),
        InputActionDef(
          id: 'a8',
          name: 'cancel',
          bindings: [ControlBindingDef(id: 'b9', path: '<Gamepad>/buttonEast')],
        ),
      ],
    ),
  ],
);

void main() {
  setUp(() {
    UiActions.clear();
    UiWidgets.clear();
  });

  /// A menu of [labels] in a column, open, the first focused.
  World menu(List<String> labels, {bool open = true}) {
    final world = _uiWorld();
    final root = world.createEntityWithComponents([
      UiCanvasComponent(
        designSize: const Size(400, 300),
        safeArea: false,
        isScreen: true,
        visible: open,
        initialFocus: labels.first,
      ),
      ChildrenComponent(),
    ], name: 'Menu');
    final column = world.createEntityWithComponents([
      UiLayoutComponent(kind: UiLayoutKind.column, tight: true),
      ParentComponent(parentId: root.id),
      ChildrenComponent(),
    ], name: 'Column');
    root.getComponent<ChildrenComponent>()!.addChild(column.id);
    for (final label in labels) {
      final child = world.createEntityWithComponents([
        ButtonComponent(
          label: label,
          onPressed: UiActionList([UiAction('custom:$label')]),
        ),
        ParentComponent(parentId: column.id),
      ], name: label);
      column.getComponent<ChildrenComponent>()!.addChild(child.id);
    }
    return world;
  }

  String focusedText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return '';
    final texts = find.descendant(
      of: find.byElementPredicate((e) => identical(e, context)),
      matching: find.byType(Text),
    );
    return [
      for (final e in texts.evaluate())
        (e.widget as Text).data ??
            (e.widget as Text).textSpan?.toPlainText() ??
            '',
    ].join();
  }

  /// The menu on screen, a service with a pad, and the bridge between.
  Future<(InputService, FakeGamepadSource, GlobalKey<UiLayerState>)> show(
    WidgetTester tester,
    World world, {
    bool Function(UiLayerState ui)? takesPad,
  }) async {
    final input = InputService()..loadAsset(_asset);
    final pads = FakeGamepadSource();
    await input.attachGamepads(pads);
    pads.connect('p');
    final key = GlobalKey<UiLayerState>();
    final bridge = UiInputBridge(
      input: input,
      layer: () => key.currentState,
      takesPad: takesPad,
    );
    addTearDown(() {
      bridge.dispose();
      input.dispose();
      pads.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: UiLayer(key: key, world: world),
        ),
      ),
    );
    // A screen opens as a page: let its transition finish and its first
    // control take focus.
    await tester.pumpAndSettle();
    return (input, pads, key);
  }

  testWidgets('the d-pad walks the menu', (tester) async {
    final (input, pads, _) = await show(
      tester,
      menu(['Play', 'Options', 'Quit']),
    );
    expect(focusedText(), 'Play');

    pads.press('p', _b['dpad/down']!);
    input.update(1);
    await tester.pump();
    expect(focusedText(), 'Options');

    input.update(1.1);
    await tester.pump();
    expect(focusedText(), 'Options', reason: 'held, it waits before repeating');
    input.update(1.4);
    await tester.pump();
    expect(focusedText(), 'Quit', reason: 'then repeats');

    pads.release('p');
    input.update(1.5);
    pads.press('p', _b['dpad/up']!);
    input.update(1.6);
    await tester.pump();
    expect(focusedText(), 'Options');
  });

  testWidgets('Ⓐ presses what is focused', (tester) async {
    final pressed = <String>[];
    UiActions.register('Play', (_) => pressed.add('Play'));
    final (input, pads, _) = await show(tester, menu(['Play', 'Quit']));
    pads.press('p', _b['buttonSouth']!);
    input.update(1);
    await tester.pump();
    expect(pressed, ['Play']);
    input.update(1.1);
    await tester.pump();
    expect(pressed, ['Play'], reason: 'once per press, not per frame');
  });

  testWidgets('Ⓑ goes back', (tester) async {
    final (input, pads, key) = await show(tester, menu(['Play']));
    expect(key.currentState!.navigator.isEmpty, isFalse);
    pads.press('p', _b['buttonEast']!);
    input.update(1);
    await tester.pump();
    expect(key.currentState!.navigator.isEmpty, isTrue);
  });

  testWidgets('the keyboard is the UI\'s own business: not moved twice', (
    tester,
  ) async {
    final (input, _, _) = await show(tester, menu(['Play', 'Options', 'Quit']));
    input.handleKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowDown,
        logicalKey: LogicalKeyboardKey.arrowDown,
        timeStamp: Duration.zero,
      ),
    );
    input.update(1);
    await tester.pump();
    expect(focusedText(), 'Play');
  });

  testWidgets('with no screen open, the stick is moving a character', (
    tester,
  ) async {
    final world = menu(['Play', 'Quit'], open: false)
      ..createEntityWithComponents([
        UiCanvasComponent(safeArea: false),
      ], name: 'Hud');
    final (input, pads, key) = await show(tester, world);
    expect(key.currentState!.navigator.isEmpty, isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    pads.press('p', _b['buttonEast']!);
    input.update(1);
    await tester.pump();
    expect(key.currentState!.navigator.isEmpty, isTrue);
  });

  testWidgets('a focused slider slides with the d-pad', (tester) async {
    final world = _uiWorld();
    final root = world.createEntityWithComponents([
      UiCanvasComponent(
        designSize: const Size(400, 300),
        safeArea: false,
        isScreen: true,
        initialFocus: 'Volume',
      ),
      ChildrenComponent(),
    ], name: 'Settings');
    final slider = UiSliderComponent(value: 0.5, steps: 10);
    final entity = world.createEntityWithComponents([
      slider,
      UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.center,
        size: const Size(300, 48),
      ),
      ParentComponent(parentId: root.id),
    ], name: 'Volume');
    root.getComponent<ChildrenComponent>()!.addChild(entity.id);

    final (input, pads, _) = await show(tester, world);
    pads.press('p', _b['dpad/right']!);
    input.update(1);
    await tester.pump();

    expect(slider.value, closeTo(0.6, 1e-9));
  });

  testWidgets('a screen that does not take the pad leaves it alone', (
    tester,
  ) async {
    final (input, pads, _) = await show(
      tester,
      menu(['Play', 'Options', 'Quit']),
      takesPad: (_) => false,
    );
    pads.press('p', _b['dpad/down']!);
    input.update(1);
    await tester.pump();

    expect(focusedText(), 'Play');
  });

  testWidgets('while a rebind listens, the bridge stands aside', (
    tester,
  ) async {
    final (input, pads, _) = await show(tester, menu(['Play', 'Quit']));
    input.suspendActions();
    pads.press('p', _b['dpad/down']!);
    input.update(1);
    await tester.pump();
    expect(focusedText(), 'Play');
  });
}
