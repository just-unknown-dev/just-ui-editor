// Screens as assets: each one a `.ui.json` of its own, every one a game has
// listed in `screens.json`, all built once into a world of their own and kept
// across levels.

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);

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
    TextComponent(text: '$name title'),
    UiSlotComponent(),
  ], name: '${name}Title');
  final hint = world.createEntityWithComponents([
    TextComponent(text: '$name hint'),
    UiSlotComponent(),
  ], name: '${name}Hint');
  UiDocument.link(card, canvas);
  UiDocument.link(title, card);
  UiDocument.link(hint, card);
  return canvas;
}

UiDocument _document(String name, {bool isScreen = true}) {
  final world = _uiWorld()..initialize();
  final canvas = _screen(world, name, isScreen: isScreen);
  return UiDocument.capture(canvas, world);
}

List<String?> _namesUnder(World world, Entity root) => [
  root.name,
  for (final id
      in root.getComponent<ChildrenComponent>()?.childIds ?? const <int>[])
    ..._namesUnder(world, world.getEntity(id)!),
];

void main() {
  tearDown(UiActions.clear);

  group('a screen file', () {
    test('holds the canvas first, parents by name, and no ids', () {
      final doc = _document('Pause');
      final json = doc.toJson();

      expect(json['format'], UiDocument.currentFormat);
      expect(json['name'], 'Pause');
      final entities = (json['entities'] as List).cast<Map>();
      expect(entities.map((e) => e['name']), [
        'Pause',
        'PauseCard',
        'PauseTitle',
        'PauseHint',
      ]);
      expect(entities.map((e) => e['parentName']), [
        null,
        'Pause',
        'PauseCard',
        'PauseCard',
      ]);
      final types = {
        for (final e in entities)
          for (final c in (e['components'] as List).cast<Map>()) c['type'],
      };
      expect(types, isNot(contains('ParentComponent')));
      expect(types, isNot(contains('ChildrenComponent')));
    });

    test('does not save whether the screen is open', () {
      final world = _uiWorld()..initialize();
      final canvas = _screen(world, 'Pause');
      canvas.getComponent<UiCanvasComponent>()!.visible = true;

      final saved = UiDocument.capture(canvas, world).toJson();
      final root = (saved['entities'] as List).first as Map;
      final fields = [
        for (final c in (root['components'] as List).cast<Map>())
          if (c['type'] == 'UiCanvasComponent') c['fields'] as Map,
      ].single;

      expect(fields, isNot(contains('visible')));
      expect(fields['isScreen'], isTrue, reason: 'the rest is kept');
    });

    test('builds back into the same tree, siblings in order', () {
      final doc = UiDocument.fromJson(
        jsonDecode(jsonEncode(_document('Pause').toJson())),
      );
      final world = _uiWorld()..initialize();

      final canvas = doc.instantiate(world);

      expect(_namesUnder(world, canvas), [
        'Pause',
        'PauseCard',
        'PauseTitle',
        'PauseHint',
      ]);
      final title = world.findEntityByName('PauseTitle')!;
      expect(title.getComponent<TextComponent>()!.text, 'Pause title');
    });

    test('from a newer version is refused, not half read', () {
      expect(
        () => UiDocument.fromJson({
          'format': UiDocument.currentFormat + 1,
          'entities': [
            {'name': 'X', 'components': <Object>[]},
          ],
        }),
        throwsFormatException,
      );
    });

    test('naming a component nothing registered stops, naming it', () {
      final doc = UiDocument.fromJson({
        'name': 'Odd',
        'entities': [
          {
            'name': 'Odd',
            'components': [
              {'type': 'NobodysComponent', 'fields': <String, Object>{}},
            ],
          },
        ],
      });

      expect(
        () => doc.instantiate(_uiWorld()..initialize()),
        throwsA(
          isA<UnknownComponentTypeException>()
              .having((e) => e.type, 'type', 'NobodysComponent')
              .having((e) => e.entityName, 'entity', 'Odd'),
        ),
      );
    });
  });

  test('the screen list reads and writes itself', () {
    final manifest = UiScreenManifest.fromJson({
      'theme': 'assets/ui/default.uitheme.json',
      'screens': [
        {'path': 'assets/ui/hud.ui.json', 'startOpen': true},
        {'path': 'assets/ui/pause.ui.json'},
      ],
    });

    expect(manifest.theme, 'assets/ui/default.uitheme.json');
    expect(manifest.screens, const [
      UiScreenEntry(path: 'assets/ui/hud.ui.json', startOpen: true),
      UiScreenEntry(path: 'assets/ui/pause.ui.json'),
    ]);
    expect(
      UiScreenManifest.fromJson(manifest.toJson()).screens,
      manifest.screens,
    );
  });

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
              .getComponent<TextComponent>()!
              .text =
          'changed';

      screens.reset();

      expect(screens.isOpen('Pause'), isFalse);
      expect(screens.isOpen('Hud'), isTrue);
      expect(
        screens.world
            .findEntityByName('PauseTitle')!
            .getComponent<TextComponent>()!
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

      UiActions.run(
        const UiAction('ui.push', 'Pause'),
        UiActionContext(world: engine.world),
      );

      expect(screens.isOpen('Pause'), isTrue);
    });

    test('a game host set afterwards leaves the screens answering', () {
      var paused = false;
      // What a game sets at boot: its own pause, nothing about screens.
      UiActions.host = UiActionHost(pause: () => paused = true);

      UiActions.run(
        const UiAction('ui.push', 'Pause'),
        UiActionContext(world: engine.world),
      );
      UiActions.run(
        const UiAction('game.pause'),
        UiActionContext(world: engine.world),
      );

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
      UiActions.run(
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
          .getComponent<TextComponent>()!;
      final before = title.elapsed;

      engine.plugins.update(0.5);

      expect(title.elapsed, closeTo(before + 0.5, 1e-9));
    });

    test('uninstalling hands the actions back', () {
      JustGameUi.uninstall(engine);

      expect(JustGameUi.of(engine), isNull);
      expect(UiActions.defaults.pushScreen, isNull);
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

  group('taking screens out of a scene', () {
    Map<String, dynamic> canvas(bool visible) => {
      'type': 'UiCanvasComponent',
      'fields': {'isScreen': !visible, 'visible': visible},
    };
    Map<String, dynamic> text(String value) => {
      'type': 'TextComponent',
      'fields': {'textValue': value},
    };
    final scene = {
      'version': 5,
      'name': 'level_test',
      'root': {
        'name': 'root',
        'children': [
          {'name': 'Platform'},
        ],
      },
      'entities': [
        {
          'name': 'Platform',
          'parentName': null,
          'components': [
            {'type': 'TransformComponent', 'fields': <String, Object>{}},
          ],
        },
        {
          'name': 'Hud',
          'parentName': null,
          'components': [
            canvas(true),
            {
              'type': 'ChildrenComponent',
              'fields': {
                'childIds': [2],
              },
            },
          ],
        },
        {
          'name': 'HudCoins',
          'parentName': 'Hud',
          'components': [
            text('{coins}'),
            {
              'type': 'ParentComponent',
              'fields': {'parentId': 1},
            },
          ],
        },
        {
          'name': 'Sign',
          'parentName': null,
          'components': [text('Welcome')],
        },
        {
          'name': 'Pause',
          'parentName': null,
          'components': [canvas(false)],
        },
        {
          'name': 'PauseTitle',
          'parentName': 'Pause',
          'components': [text('Paused')],
        },
      ],
    };

    test('every canvas becomes a screen, the rest stays', () {
      final out = UiSceneExtractor.extract(scene);

      expect(out.documents.map((d) => d.name), ['Hud', 'Pause']);
      expect(out.entries, const [
        UiScreenEntry(path: 'assets/ui/hud.ui.json', startOpen: true),
        UiScreenEntry(path: 'assets/ui/pause.ui.json'),
      ]);
      expect((out.scene['entities'] as List).map((e) => (e as Map)['name']), [
        'Platform',
        'Sign',
      ], reason: 'world-space text is the level\'s');
    });

    test('a screen keeps its tree and loses its ids and open flag', () {
      final hud = UiSceneExtractor.extract(scene).documents.first;

      expect(hud.entities.map((e) => e['parentName']), [null, 'Hud']);
      final types = [
        for (final e in hud.entities)
          for (final c in (e['components'] as List).cast<Map>()) c['type'],
      ];
      expect(types, ['UiCanvasComponent', 'TextComponent']);
      final fields =
          ((hud.entities.first['components'] as List).first as Map)['fields']
              as Map;
      expect(fields.containsKey('visible'), isFalse);
    });

    test('files are named after their screens', () {
      expect(UiSceneExtractor.fileNameFor('DeviceLost'), 'device_lost.ui.json');
      expect(UiSceneExtractor.fileNameFor('Hud'), 'hud.ui.json');
    });

    test('a scene with no screens is left alone', () {
      final plain = {
        'entities': [
          {'name': 'Platform', 'components': <Object>[]},
        ],
      };

      final out = UiSceneExtractor.extract(plain);

      expect(out.isEmpty, isTrue);
      expect(out.scene, same(plain));
    });
  });
}
