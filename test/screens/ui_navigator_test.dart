// The navigator: which screens are open, and in what order.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';
import 'package:flutter/foundation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('names two screens share', () {
    test('a screen opens by its name, whatever else is called that', () {
      final world = uiWorld();
      final hud = addCanvas(world, 'Hud');
      // Loaded first, so the oldest entity called "Pause" — a button.
      addUnder(world, hud, [
        UiButtonComponent(label: 'II'),
        UiSlotComponent(),
      ], name: 'Pause');
      addCanvas(world, 'Pause', isScreen: true, visible: false);
      final navigator = UiNavigator(world);

      navigator.push('Pause');

      expect(navigator.top?.name, 'Pause');
      expect(navigator.top?.getComponent<UiCanvasComponent>()?.visible, isTrue);
    });

    test('an element is looked for in the screen on top first', () {
      final world = uiWorld();
      final hud = addCanvas(world, 'Hud');
      final hudTitle = addUnder(world, hud, [
        UiTextComponent(text: 'Hud'),
        UiSlotComponent(),
      ], name: 'Title');
      final settings = addCanvas(world, 'Settings', isScreen: true);
      final settingsTitle = addUnder(world, settings, [
        UiTextComponent(text: 'Settings'),
        UiSlotComponent(),
      ], name: 'Title');
      final navigator = UiNavigator(world)..adopt();

      navigator.show('Title', false);

      expect(settingsTitle.getComponent<UiSlotComponent>()!.visible, isFalse);
      expect(hudTitle.getComponent<UiSlotComponent>()!.visible, isTrue);
    });

    test('a timeline is looked for in the acting screen first', () {
      final world = uiWorld();
      final a = addCanvas(world, 'A');
      final first = TimelinePlayerComponent();
      addUnder(world, a, [first], name: 'Door');
      final b = addCanvas(world, 'B');
      final second = TimelinePlayerComponent();
      addUnder(world, b, [second], name: 'Door');
      final button = addUnder(world, b, [UiButtonComponent()], name: 'Open');

      expect(
        UiActions.findBelow(
          world,
          UiActions.rootOf(button),
          'Door',
        )?.getComponent<TimelinePlayerComponent>(),
        same(second),
      );
    });
  });

  group('the stack of screens', () {
    test('a layer pushed is shown, not stacked', () {
      final world = uiWorld();
      final hud = addCanvas(world, 'Hud', visible: false);
      final navigator = UiNavigator(world);

      navigator.push('Hud');

      expect(hud.getComponent<UiCanvasComponent>()!.visible, isTrue);
      expect(navigator.isEmpty, isTrue);
    });

    test('keeps the order screens were opened in, by sort order', () {
      final world = uiWorld();
      for (final name in ['A', 'B', 'C', 'D']) {
        addCanvas(
          world,
          name,
          isScreen: true,
          visible: false,
          sortOrder: name == 'C' ? 5 : 0,
        );
      }
      final navigator = UiNavigator(world);

      navigator
        ..push('B')
        ..push('A')
        ..push('C')
        ..push('D');
      for (var i = 0; i < 3; i++) {
        navigator.adopt();
      }

      expect([for (final e in navigator.stack) e.name], ['B', 'A', 'D', 'C']);
    });
  });

  group('the navigator on its own', () {
    test('show hides and flips a layer without touching the stack', () {
      final world = uiWorld();
      world.createEntityWithComponents([UiCanvasComponent()], name: 'Hud');
      final navigator = UiNavigator(world);
      final hud = world
          .findEntityByName('Hud')!
          .getComponent<UiCanvasComponent>()!;

      navigator.show('Hud', false);
      expect(hud.visible, isFalse);
      navigator.show('Hud', null);
      expect(hud.visible, isTrue);
      expect(navigator.isEmpty, isTrue);
    });

    test('show hides one element inside a canvas', () {
      final world = uiWorld();
      final slot = UiSlotComponent();
      world.createEntityWithComponents([
        UiTextComponent(text: 'Hint'),
        slot,
      ], name: 'Hint');

      UiNavigator(world).show('Hint', false);

      expect(slot.visible, isFalse);
    });

    test('pushing the same screen twice leaves one of it', () {
      final world = uiWorld();
      world.createEntityWithComponents([
        UiCanvasComponent(isScreen: true, visible: false),
      ], name: 'Pause');
      final navigator = UiNavigator(world);

      navigator
        ..push('Pause')
        ..push('Pause');

      expect(navigator.stack.length, 1);
    });

    test('back with nothing open does nothing', () {
      final navigator = UiNavigator(uiWorld());
      expect(navigator.back, returnsNormally);
      expect(navigator.handleBack(), isFalse);
    });

    test('a player\'s back closes a screen only if it closes on Back', () {
      final world = uiWorld();
      world.createEntityWithComponents([
        UiCanvasComponent(isScreen: true, visible: false),
      ], name: 'Pause');
      world.createEntityWithComponents([
        UiCanvasComponent(isScreen: true, visible: false, closesOnBack: false),
      ], name: 'Complete');
      final navigator = UiNavigator(world)
        ..push('Pause')
        ..push('Complete');

      expect(navigator.canGoBack, isFalse);
      expect(navigator.handleBack(), isFalse);
      expect(navigator.top?.name, 'Complete', reason: 'it stays');

      // A button's `ui.back` closes it all the same.
      navigator.back();
      expect(navigator.top?.name, 'Pause');
      expect(navigator.canGoBack, isTrue);
      expect(navigator.handleBack(), isTrue);
      expect(navigator.isEmpty, isTrue);
    });

    test('a name that is not there is quietly nothing', () {
      final navigator = UiNavigator(uiWorld());
      navigator
        ..push('Missing')
        ..show('Missing', true);
      expect(navigator.isEmpty, isTrue);
    });

    test('what the game already handles is left to the game', () {
      final world = uiWorld();
      var asked = '';
      final host = UiActionHost(pushScreen: (name) => asked = name);
      final filled = UiNavigator(world).fillingIn(host);

      filled.pushScreen!('Shop');

      expect(asked, 'Shop');
      expect(filled.back, isNotNull);
    });
  });

  group('a name nothing has', () {
    test('is said once, in a debug build', () {
      final said = <String>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('just_ui_editor') ?? false) said.add(message!);
      };
      addTearDown(() => debugPrint = saved);
      final world = uiWorld();
      addCanvas(world, 'Hud');
      final navigator = UiNavigator(world);

      navigator
        ..push('Pause')
        ..push('Pause')
        ..show('Pause', true);

      expect(said, hasLength(1));
      expect(said.single, contains('"Pause"'));
      expect(said.single, contains('Hud'), reason: 'what there is instead');
    });

    test('a name that is there says nothing', () {
      final said = <String>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message?.startsWith('just_ui_editor') ?? false) said.add(message!);
      };
      addTearDown(() => debugPrint = saved);
      final world = uiWorld();
      addCanvas(world, 'Pause', isScreen: true, visible: false);

      UiNavigator(world).push('Pause');

      expect(said, isEmpty);
    });
  });
}
