// The interface installed in a game, taken out and installed again.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  group('installed again, and taken out', () {
    test('takes the new callbacks, and gives the theme back', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      UiThemes.of(engine.context).loader = (path) async =>
          const UiTheme(name: 'mine');
      final list = UiScreenManifest(theme: 'mine.uitheme.json');

      await JustGameUi.install(engine, screens: list, fonts: null);
      String second(String key) => 'second';
      await JustGameUi.install(
        engine,
        screens: list,
        localize: second,
        fonts: null,
      );

      expect(engine.world.getSystem<UiTextSystem>()!.localize, same(second));
      expect(UiWorldStyle.of(engine.context).localize, same(second));
      expect(UiWorldStyle.of(engine.context).resolvedTheme.name, 'mine');

      JustGameUi.uninstall(engine);

      expect(UiThemes.of(engine.context).fallback, same(UiTheme.fallback));
      expect(UiWorldStyle.of(engine.context).localize, isNull);
    });

    test('a game\'s own self.name is kept', () {
      UiBindings.of(engineContext).registerForEntity('name', (_) => 'mine');
      registerUiSystems(uiWorld(engineContext));
      final entity = uiWorld(engineContext).createEntity(name: 'Entity');

      expect(
        UiBindings.of(engineContext).read('self.name', self: entity),
        'mine',
      );
    });
  });

  group('installed in a game', () {
    late Engine engine;
    late Map<String, String> files;
    var tick = 0;
    var probeBuilds = 0;

    setUp(() async {
      tick = 0;
      probeBuilds = 0;
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      UiBindings.of(engine.context).register('tick', () => tick);
      UiWidgets.of(engine.context).register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (_) {
            probeBuilds++;
            return const SizedBox.expand();
          },
        ),
      );
      final hudWorld = uiWorld(engineContext);
      final hud = addCanvas(hudWorld, 'Hud');
      addUnder(hudWorld, hud, [
        UiTextComponent(text: 'Tick {tick}'),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          size: const Size(200, 40),
          pivot: Offset.zero,
        ),
      ]);
      addUnder(hudWorld, hud, [
        UiCustomComponent(widgetId: 'probe'),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          size: const Size(10, 10),
          pivot: Offset.zero,
          offset: const Offset(300, 0),
        ),
      ]);
      addUnder(hudWorld, hud, [
        UiButtonComponent(
          label: 'Hud',
          onPressed: const UiActionList([UiAction('custom:hudPressed')]),
        ),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          anchor: UiAnchor.center,
          size: const Size(80, 40),
        ),
      ], name: 'HudButton');
      files = {
        'screens.json': jsonEncode({
          'screens': [
            {'path': 'hud.ui.json', 'startOpen': true},
            {'path': 'pause.ui.json'},
          ],
        }),
        'hud.ui.json': jsonEncode(documentOf(hudWorld, 'Hud').toJson()),
        'pause.ui.json': jsonEncode(
          screenDocument('Pause', modal: true).toJson(),
        ),
      };
      await JustGameUi.install(
        engine,
        manifest: 'screens.json',
        read: (path) async => files[path]!,
        localize: (key) => key == 'sign' ? 'Welcome' : key,
        fonts: null,
      );
    });

    testWidgets('restarting with a screen open throws nothing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      final screens = JustGameUi.of(engine)!.screens;
      screens.push('Pause');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Pause title', findRichText: true), findsOneWidget);

      // What the template's Restart does from the pause menu.
      screens.reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(screens.isOpen('Pause'), isFalse);
    });

    testWidgets('a reading that changes rebuilds its text, nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      expect(find.text('Tick 0', findRichText: true), findsOneWidget);
      final before = probeBuilds;

      for (var i = 1; i <= 5; i++) {
        tick = i;
        engine.plugins.update(1 / 60);
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('Tick 5', findRichText: true), findsOneWidget);
      expect(probeBuilds, before, reason: 'the rest of the screen sat still');
    });

    test('the level\'s text gets the game\'s language and theme', () {
      final look = UiWorldStyle.of(engine.context);
      expect(look.localize?.call('sign'), 'Welcome');
      expect(look.resolvedTheme, same(UiThemes.of(engine.context).fallback));

      final text = UiTextComponent(text: '@sign');
      final sign = engine.world.createEntityWithComponents([
        TransformComponent(),
        text,
      ]);
      engine.world.update(1 / 60);
      final recorder = ui.PictureRecorder();
      const UiTextComponentPainter().paint(
        Canvas(recorder),
        sign,
        text,
        RenderContext(world: engine.world, size: const Size(400, 300)),
      );
      recorder.endRecording().dispose();

      expect(
        text
            .resolve(
              UiBindings.of(engine.context),
              self: sign,
              localize: look.localize,
            )
            .plain,
        'Welcome',
      );
    });

    testWidgets('a world button hears what the screens let through', (
      tester,
    ) async {
      final pressed = <String>[];
      UiActions.of(
        engine.context,
      ).register('worldPressed', (_) => pressed.add('world'));
      UiActions.of(
        engine.context,
      ).register('hudPressed', (_) => pressed.add('hud'));
      // A world button as big as the whole view: wherever the camera is.
      engine.world.createEntityWithComponents([
        TransformComponent(),
        UiButtonComponent(
          size: const Size(100000, 100000),
          onPressed: const UiActionList([UiAction('custom:worldPressed')]),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      final view = tester.getRect(find.byType(GameWidget));
      final hud = tester.getCenter(find.text('Hud', findRichText: true));

      // Away from the HUD's button: the world's is pressed.
      await tester.tapAt(view.topLeft + const Offset(20, 200));
      engine.world.update(1 / 60);
      expect(pressed, ['world']);

      // On the HUD's button: only it.
      pressed.clear();
      await tester.tapAt(hud);
      await tester.pump();
      engine.world.update(1 / 60);
      expect(pressed, ['hud']);

      // Under a modal screen: nothing in the world.
      pressed.clear();
      JustGameUi.of(engine)!.screens.push('Pause');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(view.topLeft + const Offset(20, 200));
      await tester.pump();
      engine.world.update(1 / 60);
      expect(pressed, isEmpty);
    });
  });

  group('two engines', () {
    Future<Engine> withPause() async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      await JustGameUi.install(
        engine,
        screens: UiScreenManifest(
          screens: const [UiScreenEntry(path: 'pause.ui.json')],
        ),
        read: (_) async => jsonEncode(screenDocument('Pause').toJson()),
        fonts: null,
      );
      return engine;
    }

    test("a screen's ui.push opens a screen of its own engine", () async {
      final first = await withPause();
      final second = await withPause();
      final firstScreens = JustGameUi.of(first)!.screens;
      final secondScreens = JustGameUi.of(second)!.screens;

      // What a button on the first engine's screens does.
      const UiActionList(
        [UiAction('ui.push', 'Pause')],
      ).run(UiActionContext(world: firstScreens.world, gameWorld: first.world));

      expect(firstScreens.isOpen('Pause'), isTrue);
      expect(
        secondScreens.isOpen('Pause'),
        isFalse,
        reason: 'not the last installed',
      );
    });

    test("one engine's registrations are not another's", () async {
      final first = await withPause();
      final second = await withPause();
      UiActions.of(first.context).register('cheer', (_) {});
      UiWidgets.of(first.context).register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (_) => const SizedBox(),
        ),
      );

      expect(UiActions.of(second.context).has('cheer'), isFalse);
      expect(UiWidgets.of(second.context).has('probe'), isFalse);
      expect(UiActions.of(first.context).defaults.pushScreen, isNotNull);
      expect(
        identical(
          UiActions.of(first.context).defaults.pushScreen,
          UiActions.of(second.context).defaults.pushScreen,
        ),
        isFalse,
      );
    });

    test("one engine's screen list theme is not another's fallback", () async {
      final first = Engine();
      addTearDown(first.dispose);
      await first.initialize();
      final second = Engine();
      addTearDown(second.dispose);
      await second.initialize();
      UiThemes.of(first.context).loader = (_) async =>
          const UiTheme(name: 'first');

      await JustGameUi.install(
        first,
        screens: UiScreenManifest(theme: 'first.uitheme.json'),
        fonts: null,
      );

      expect(UiThemes.of(first.context).fallback.name, 'first');
      expect(UiThemes.of(second.context).fallback, same(UiTheme.fallback));
    });
  });

  group('a game with no screens', () {
    test('says so when it is installed', () async {
      final said = <String>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) => said.add(message ?? '');
      addTearDown(() => debugPrint = saved);
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      await JustGameUi.install(
        engine,
        screens: UiScreenManifest(),
        fonts: null,
      );

      expect(said, contains(contains('names no screens')));
    });
  });
}
