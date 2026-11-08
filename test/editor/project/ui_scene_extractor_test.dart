// Taking the screens out of a scene, into files of their own.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taking screens out of a scene', () {
    test('two parents of one name keep their own children', () {
      Map<String, dynamic> entity(
        String name,
        String? parent,
        List<Map<String, dynamic>> components,
      ) => {'name': name, 'parentName': parent, 'components': components};
      final canvas = [
        {
          'type': 'UiCanvasComponent',
          'fields': {'isScreen': true},
        },
      ];
      final slot = [
        {'type': 'UiSlotComponent', 'fields': <String, Object>{}},
      ];
      final extraction = UiSceneExtractor.extract({
        'version': 5,
        'entities': [
          entity('A', null, canvas),
          entity('Panel', 'A', slot),
          entity('OnlyA', 'Panel', slot),
          entity('B', null, canvas),
          entity('Panel', 'B', slot),
          entity('OnlyB', 'Panel', slot),
        ],
      });

      final names = {
        for (final doc in extraction.documents)
          doc.name: [for (final e in doc.entities) e['name']],
      };
      expect(names['A'], ['A', 'Panel', 'OnlyA']);
      expect(names['B'], ['B', 'Panel', 'OnlyB']);
    });
  });

  group('taking screens out of a scene', () {
    Map<String, dynamic> canvas(bool visible) => {
      'type': 'UiCanvasComponent',
      'fields': {'isScreen': !visible, 'visible': visible},
    };
    Map<String, dynamic> text(String value) => {
      'type': 'UiTextComponent',
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
      expect(types, ['UiCanvasComponent', 'UiTextComponent']);
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
