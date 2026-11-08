// Files saved before the interface's components took the Ui prefix: scenes
// and screens load with the new names.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// An engine context with the interface installed, as a game's.
  EngineContext game() =>
      EngineContext(extensions: const [JustGameUi.extension]);

  test('the renames, old name to new', () {
    expect(UiMigrations.renamedTypes, {
      'TextComponent': 'UiTextComponent',
      'ButtonComponent': 'UiButtonComponent',
    });
    expect(
      game().migrations.renamedTypes,
      containsPair('TextComponent', 'UiTextComponent'),
    );
  });

  test('a scene saved at the current format with the old names loads', () {
    final context = game();
    final scene = SceneFormat.migrate({
      'version': SceneFormat.current,
      'name': 'level',
      'entities': [
        {
          'name': 'Sign',
          'components': [
            {
              'type': 'TextComponent',
              'fields': {'textValue': 'Welcome'},
            },
            {
              'type': 'ButtonComponent',
              'fields': {'label': 'Go'},
            },
          ],
        },
      ],
    }, hooks: context.migrations);

    final components =
        ((scene['entities'] as List).single as Map)['components'] as List;
    expect(
      [for (final c in components) (c as Map)['type']],
      ['UiTextComponent', 'UiButtonComponent'],
    );
    final text = context.definitions.decode(
      (components.first as Map).cast<String, dynamic>(),
    );
    expect(text, isA<UiTextComponent>());
    expect((text! as UiTextComponent).text, 'Welcome');
  });

  /// A screen file the way format 1 saved it.
  Map<String, dynamic> formatOne() => {
    'format': 1,
    'name': 'Hud',
    'entities': [
      {
        'name': 'Hud',
        'parentName': null,
        'components': [
          {'type': 'UiCanvasComponent', 'fields': <String, Object>{}},
        ],
      },
      {
        'name': 'Coins',
        'parentName': 'Hud',
        'components': [
          {
            'type': 'TextComponent',
            'fields': {'textValue': 'Coins: {coins}'},
          },
          {'type': 'UiSlotComponent', 'fields': <String, Object>{}},
        ],
      },
      {
        'name': 'Pause',
        'parentName': 'Hud',
        'components': [
          {
            'type': 'ButtonComponent',
            'fields': {'label': 'Pause'},
          },
          {'type': 'UiSlotComponent', 'fields': <String, Object>{}},
        ],
      },
    ],
  };

  test('a format 1 screen reads with the new names, and builds', () {
    final document = UiDocument.fromJson(formatOne());
    final types = [
      for (final e in document.entities)
        for (final c in (e['components'] as List).cast<Map>()) c['type'],
    ];
    expect(types, contains('UiTextComponent'));
    expect(types, contains('UiButtonComponent'));
    expect(types, isNot(contains('TextComponent')));

    final world = World(context: game())..initialize();
    document.instantiate(world);
    expect(
      world.findEntityByName('Coins')!.getComponent<UiTextComponent>()!.text,
      'Coins: {coins}',
    );
    expect(
      world.findEntityByName('Pause')!.getComponent<UiButtonComponent>()!.label,
      'Pause',
    );
    expect(document.toJson()['format'], UiDocument.currentFormat);
    expect(UiDocument.currentFormat, 2);
  });

  test("the reader's renames apply to a screen of any format", () {
    final hooks = MigrationHooks()
      ..renamedTypes['UiCanvasComponent'] = 'RenamedCanvasComponent';
    final current =
        jsonDecode(jsonEncode(UiDocument.fromJson(formatOne()).toJson()))
            as Map<String, dynamic>;

    final read = UiDocument.fromJson(current, hooks: hooks);

    expect(
      ((read.entities.first['components'] as List).first as Map)['type'],
      'RenamedCanvasComponent',
    );
  });

  test('screens loaded by a game take its renames', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final files = {
      'screens.json': jsonEncode({
        'screens': [
          {'path': 'hud.ui.json', 'startOpen': true},
        ],
      }),
      'hud.ui.json': jsonEncode(formatOne()),
    };

    await JustGameUi.install(
      engine,
      manifest: 'screens.json',
      read: (path) async => files[path]!,
      fonts: null,
    );

    final world = JustGameUi.of(engine)!.screens.world;
    expect(
      world.findEntityByName('Coins')!.getComponent<UiTextComponent>(),
      isNotNull,
    );
  });
}
