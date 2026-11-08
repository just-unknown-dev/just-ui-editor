// A screen file: reading, refusing, migrating and building it.

import 'dart:convert';

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

List<String?> _namesUnder(World world, Entity root) => [
  root.name,
  for (final id
      in root.getComponent<ChildrenComponent>()?.childIds ?? const <int>[])
    ..._namesUnder(world, world.getEntity(id)!),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a screen that will not read', () {
    test('leaves nothing behind in the world', () {
      final world = uiWorld();
      final before = world.entityCount;

      expect(
        () => brokenScreen('Pause').instantiate(world),
        throwsA(isA<UnknownComponentTypeException>()),
      );
      expect(world.entityCount, before, reason: 'not half a screen');
    });

    test('is left out of the game: nothing open, nothing in the way', () async {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      await screens.loadManifest(
        UiScreenManifest(screens: const [UiScreenEntry(path: 'pause.ui.json')]),
        read: (_) async => jsonEncode(brokenScreen('Pause').toJson()),
      );

      expect(screens.names, isEmpty);
      expect(screens.navigator.isEmpty, isTrue);
      expect(screens.world.query(const [UiCanvasComponent]), isEmpty);
    });

    test('a replacement that will not read leaves the old one standing', () {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      screens.add(screenDocument('Pause'));

      expect(() => screens.add(brokenScreen('Pause')), throwsA(anything));
      expect(screens.canvasOf('Pause'), isNotNull);
    });
  });

  group('a file of the wrong shape says so', () {
    test('a screen file', () {
      expect(
        () => UiDocument.fromJson({'format': '1', 'entities': []}),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': {'a': 1},
        }),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': [
            {'name': 5, 'components': []},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': [
            {'name': 'Hud', 'components': {}},
          ],
        }),
        throwsFormatException,
      );
    });

    test('a screen list', () {
      expect(
        () => UiScreenManifest.fromJson({'theme': 5}),
        throwsFormatException,
      );
      expect(
        () => UiScreenManifest.fromJson({'screens': {}}),
        throwsFormatException,
      );
      expect(() => UiScreenManifest.parse('[1, 2]'), throwsFormatException);
    });

    test('a game with no screen list runs with no screens', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final plugin = await JustGameUi.install(
        engine,
        read: (path) async => throw FlutterError('Unable to load $path'),
        fonts: null,
      );

      expect(plugin.screens.names, isEmpty);
    });

    test('nor does one that will not read stop it', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final plugin = await JustGameUi.install(
        engine,
        read: (path) async => '{"screens": "hud.ui.json"}',
        fonts: null,
      );

      expect(plugin.screens.names, isEmpty);
    });
  });

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
      final world = uiWorld()..initialize();
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
      final world = uiWorld()..initialize();

      final canvas = doc.instantiate(world);

      expect(_namesUnder(world, canvas), [
        'Pause',
        'PauseCard',
        'PauseTitle',
        'PauseHint',
      ]);
      final title = world.findEntityByName('PauseTitle')!;
      expect(title.getComponent<UiTextComponent>()!.text, 'Pause title');
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
        () => doc.instantiate(uiWorld()..initialize()),
        throwsA(
          isA<UnknownComponentTypeException>()
              .having((e) => e.type, 'type', 'NobodysComponent')
              .having((e) => e.entityName, 'entity', 'Odd'),
        ),
      );
    });
  });
}
