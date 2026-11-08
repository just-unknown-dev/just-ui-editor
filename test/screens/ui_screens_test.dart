// Screens as assets: each one a `.ui.json` of its own, every one a game has
// listed in `screens.json`, all built once into a world of their own and kept
// across levels.

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import '../support/ui_test_support.dart';

/// A canvas called [name] holding a card with a title, built in [world].
Entity _screen(World world, String name, {bool isScreen = true}) {
  final canvas = world.createEntityWithComponents([
    UiCanvasComponent(isScreen: isScreen, modal: isScreen),
  ], name: name);
  final card = world.createEntityWithComponents([
    UiPanelComponent(),
    UiLayoutComponent(),
    UiSlotComponent(size: const Size(400, 200)),
  ], name: '${name}Card');
  final title = world.createEntityWithComponents([
    UiTextComponent(text: '$name title'),
    UiSlotComponent(),
  ], name: '${name}Title');
  final hint = world.createEntityWithComponents([
    UiTextComponent(text: '$name hint'),
    UiSlotComponent(),
  ], name: '${name}Hint');
  UiDocument.link(card, canvas);
  UiDocument.link(title, card);
  UiDocument.link(hint, card);
  return canvas;
}

UiDocument _document(String name, {bool isScreen = true}) {
  final world = uiWorld();
  final canvas = _screen(world, name, isScreen: isScreen);
  return UiDocument.capture(canvas, world);
}

void main() {
  group('the screens', () {
    late UiScreens screens;
    late Map<String, String> files;
    Future<String> read(String path) async => files[path]!;

    setUp(() async {
      // Built here, not where the tests are declared: the codecs are
      // registered in setUpAll, after declaration.
      files = {
        'hud.ui.json': jsonEncode(_document('Hud', isScreen: false).toJson()),
        'pause.ui.json': jsonEncode(_document('Pause').toJson()),
      };
      screens = UiScreens();
      await screens.loadManifest(
        UiScreenManifest(
          screens: const [
            UiScreenEntry(path: 'hud.ui.json', startOpen: true),
            UiScreenEntry(path: 'pause.ui.json'),
          ],
        ),
        read: read,
      );
    });
    tearDown(() => screens.dispose());

    test('start as the list says', () {
      expect(screens.names, ['Hud', 'Pause']);
      expect(screens.isOpen('Hud'), isTrue);
      expect(screens.isOpen('Pause'), isFalse);
    });

    test('open and close by name', () {
      screens.push('Pause');
      expect(screens.isOpen('Pause'), isTrue);
      expect(screens.navigator.top?.name, 'Pause');

      screens.back();
      expect(screens.isOpen('Pause'), isFalse);

      screens.hide('Hud');
      expect(screens.isOpen('Hud'), isFalse);
    });

    test('reset puts every screen back as it started', () {
      screens.push('Pause');
      screens.hide('Hud');
      screens.world
              .findEntityByName('PauseTitle')!
              .getComponent<UiTextComponent>()!
              .text =
          'changed';

      screens.reset();

      expect(screens.isOpen('Pause'), isFalse);
      expect(screens.isOpen('Hud'), isTrue);
      expect(
        screens.world
            .findEntityByName('PauseTitle')!
            .getComponent<UiTextComponent>()!
            .text,
        'Pause title',
      );
      expect(
        screens.world.entities.where((e) => e.name == 'PauseTitle'),
        hasLength(1),
        reason: 'rebuilt, not doubled',
      );
    });
  });

  group('installed in an engine', () {
    late Engine engine;
    late Map<String, String> files;
    Future<String> read(String path) async => files[path]!;

    setUp(() async {
      files = {
        'screens.json': jsonEncode({
          'screens': [
            {'path': 'hud.ui.json', 'startOpen': true},
            {'path': 'pause.ui.json'},
          ],
        }),
        'hud.ui.json': jsonEncode(_document('Hud', isScreen: false).toJson()),
        'pause.ui.json': jsonEncode(_document('Pause').toJson()),
      };
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      await JustGameUi.install(engine, manifest: 'screens.json', read: read);
    });
    test('ui.push works with nothing on screen', () {
      final screens = JustGameUi.of(engine)!.screens;

      UiActions.of(engine.context).run(
        const UiAction('ui.push', 'Pause'),
        UiActionContext(world: engine.world),
      );

      expect(screens.isOpen('Pause'), isTrue);
    });

    test('a game host set afterwards leaves the screens answering', () {
      var paused = false;
      // What a game sets at boot: its own pause, nothing about screens.
      UiActions.of(engine.context).host = UiActionHost(
        pause: () => paused = true,
      );

      UiActions.of(engine.context).run(
        const UiAction('ui.push', 'Pause'),
        UiActionContext(world: engine.world),
      );
      UiActions.of(
        engine.context,
      ).run(const UiAction('game.pause'), UiActionContext(world: engine.world));

      expect(JustGameUi.of(engine)!.screens.isOpen('Pause'), isTrue);
      expect(paused, isTrue);
    });

    test("the screens' world shares the engine's context", () {
      final screens = JustGameUi.of(engine)!.screens;
      expect(screens.world, isNot(same(engine.world)));
      expect(screens.world.context, same(engine.context));
      expect(engine.context.isInstalled(JustGameUi.extension.id), isTrue);

      // So a button's signal reaches the level's timelines.
      final heard = <String>[];
      final stop = engine.world.context.signals.stream.listen(heard.add);
      addTearDown(stop.cancel);
      UiActions.of(engine.context).run(
        const UiAction('signal', 'door'),
        UiActionContext(world: screens.world),
      );
      expect(heard, ['door']);
    });

    test('the screens keep their own world, whatever the level does', () {
      engine.world.destroyAllEntities();

      expect(JustGameUi.of(engine)!.screens.isOpen('Hud'), isTrue);
    });

    test('the engine ticks them every frame', () {
      final screens = JustGameUi.of(engine)!.screens;
      final title = screens.world
          .findEntityByName('HudTitle')!
          .getComponent<UiTextComponent>()!;
      final before = title.elapsed;

      engine.plugins.update(0.5);

      expect(title.elapsed, closeTo(before + 0.5, 1e-9));
    });

    test('uninstalling hands the actions back', () {
      JustGameUi.uninstall(engine);

      expect(JustGameUi.of(engine), isNull);
      expect(UiActions.of(engine.context).defaults.pushScreen, isNull);
      expect(engine.layers.byId(UiScreensLayer.layerId), isNull);
    });

    testWidgets('a game widget draws them over the game', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();

      expect(find.text('Hud title', findRichText: true), findsOneWidget);
      expect(find.text('Pause title', findRichText: true), findsNothing);

      JustGameUi.of(engine)!.screens.push('Pause');
      // The game's ticker never stops, so nothing ever settles: give the
      // screen's transition its time instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Pause title', findRichText: true), findsOneWidget);
    });

    testWidgets('the pointer over the game reaches buttons in the world', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      final system = engine.world.getSystem<UiPointerSystem>()!;
      expect(system.pointer.position, isNull);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(100, 100));
      await mouse.moveTo(const Offset(120, 110));
      await tester.pump();

      expect(system.pointer.position, isNotNull);
      expect(system.pointer.isDown, isFalse);
      await mouse.down(const Offset(120, 110));
      expect(system.pointer.isDown, isTrue);
      await mouse.up();
    });

    testWidgets('a layer switched off is not drawn', (tester) async {
      engine.layers.setEnabled(UiScreensLayer.layerId, false);
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();

      expect(find.text('Hud title', findRichText: true), findsNothing);

      engine.layers.setEnabled(UiScreensLayer.layerId, true);
      await tester.pump();
      await tester.pump();

      expect(find.text('Hud title', findRichText: true), findsOneWidget);
    });
  });

  group('a press on a screen', () {
    test('is kept for one frame, then let go', () {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      final hud = addCanvas(screens.world, 'Hud');
      final button = UiButtonComponent(
        onPressed: const UiActionList([UiAction('none')]),
      );
      addUnder(screens.world, hud, [button, UiSlotComponent()]);

      button.press(UiActionContext(world: screens.world));
      screens.update(1 / 60);
      expect(button.wasPressed, isTrue);
      screens.update(1 / 60);
      expect(button.wasPressed, isFalse);
    });
  });
}
