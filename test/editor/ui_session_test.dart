// The interface editor's session, off screen: screens as files on the
// game's list, a screen as a document with its own undo, and what is done
// to its elements.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import 'package:just_ui_editor/src/editor/session/ui_slot_edit.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  late Directory dir;
  late UiEditorSession session;

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File('${dir.path}/$path').readAsStringSync())
          as Map<String, dynamic>;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ui_session');
    session = UiEditorSession(project: UiProject(dir.path));
    addTearDown(() {
      session.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  group('screens as files', () {
    test('a new screen is a file on the game\'s list, open', () {
      final doc = session.createScreen('Pause');

      expect(doc.path, 'assets/ui/pause.ui.json');
      expect(File('${dir.path}/${doc.path}').existsSync(), isTrue);
      expect(session.manifest.value.screens.single.path, doc.path);
      expect(session.document.value, same(doc));
      expect(doc.dirty.value, isFalse);
    });

    test('a layer — a HUD — starts open; a screen waits', () {
      session.createScreen('Hud', isScreen: false, startOpen: true);
      session.createScreen('Pause');

      final list = session.manifest.value;
      expect(list.entryFor('assets/ui/hud.ui.json')!.startOpen, isTrue);
      expect(list.entryFor('assets/ui/pause.ui.json')!.startOpen, isFalse);
    });

    test('renaming renames the canvas, the file and the entry', () {
      session.createScreen('Pause');

      expect(
        session.renameScreen('assets/ui/pause.ui.json', 'PauseMenu'),
        isTrue,
      );

      expect(File('${dir.path}/assets/ui/pause.ui.json').existsSync(), isFalse);
      final json = readJson('assets/ui/pause_menu.ui.json');
      expect(json['name'], 'PauseMenu');
      expect(
        session.manifest.value.screens.single.path,
        'assets/ui/pause_menu.ui.json',
      );
      expect(session.document.value!.name, 'PauseMenu');
    });

    test('a name another screen has is refused', () {
      session.createScreen('Pause');
      session.createScreen('Options');

      expect(
        session.renameScreen('assets/ui/options.ui.json', 'Pause'),
        isFalse,
      );
    });

    test('a duplicate is a screen of its own, children and all', () {
      final doc = session.createScreen('Pause');
      UiCreate.create(doc, 'button');
      session.save();

      final path = session.duplicateScreen(doc.path);
      expect(path, 'assets/ui/pause_copy.ui.json');
      expect(
        session.document.value,
        same(doc),
        reason: 'opening the copy is the editor\'s, once it has asked',
      );

      expect(session.open(path!), isTrue);
      final copy = session.document.value!;
      expect(copy.name, 'PauseCopy');
      expect(copy.entities.length, 2);
      expect(session.manifest.value.screens, hasLength(2));
    });

    test('a screen is listed by its name, not by its file name', () {
      final doc = session.createScreen('DeviceLost');
      session.save();

      expect(doc.path, 'assets/ui/device_lost.ui.json');
      expect(session.nameOf(doc.path), 'DeviceLost');
    });

    test('a screen designed wider than tall opens on its side', () {
      session.createScreen('Hud');
      expect(session.landscape.value, isTrue, reason: '1920×1080');

      session.landscape.value = false;
      session.createScreen('Pause');
      expect(session.landscape.value, isTrue);
    });

    test('deleting takes it off the disk and the list', () {
      final doc = session.createScreen('Pause');
      session.deleteScreen(doc.path);

      expect(File('${dir.path}/${doc.path}').existsSync(), isFalse);
      expect(session.manifest.value.screens, isEmpty);
      expect(session.document.value, isNull);
    });
  });

  group('a screen as a document', () {
    test('an edit is dirty, undoing it is clean, saving writes it', () {
      final doc = session.createScreen('Pause');
      UiCreate.create(doc, 'text');
      expect(doc.dirty.value, isTrue);

      doc.history.undo();
      expect(doc.dirty.value, isFalse);

      doc.history.redo();
      session.save();
      expect(doc.dirty.value, isFalse);
      expect(
        (readJson(doc.path)['entities'] as List).map((e) => (e as Map)['name']),
        ['Pause', 'Text'],
      );
    });

    test('it is not the level: its world and history are its own', () {
      final doc = session.createScreen('Pause');
      final level = _uiWorld()..initialize();
      addTearDown(level.dispose);

      UiCreate.create(doc, 'text');

      expect(level.entities, isEmpty);
      expect(doc.world.entities, hasLength(2));
    });

    test('guides and samples are kept with it, and undo like edits', () {
      final doc = session.createScreen('Hud');
      session.setGuides(const [UiGuide(vertical: true, at: 120)]);
      session.setSample('coins', '12');

      expect(session.guides.single.at, 120);
      expect(session.samples, {'coins': '12'});
      doc.history.undo();
      expect(session.samples, isEmpty);
      doc.history.redo();
      session.save();
      expect((readJson(doc.path)['editor'] as Map)['samples'], {'coins': '12'});
    });

    test('what nothing registered can read is kept and written back', () {
      final doc = session.createScreen('Pause');
      session.save();
      final json = readJson(doc.path);
      (json['entities'] as List).add({
        'name': 'Odd',
        'parentName': 'Pause',
        'components': [
          {
            'type': 'SomebodysWidget',
            'fields': {'x': 1},
          },
        ],
      });
      File('${dir.path}/${doc.path}').writeAsStringSync(jsonEncode(json));

      expect(session.open(doc.path), isTrue);
      session.document.value!.history.markSaved();
      session.save();

      final saved = readJson(doc.path)['entities'] as List;
      expect(
        saved.any(
          (e) => ((e as Map)['components'] as List).any(
            (c) => (c as Map)['type'] == 'SomebodysWidget',
          ),
        ),
        isTrue,
      );
    });
  });

  group('making things', () {
    test('into the canvas, pinned in the middle — on the screen', () {
      final doc = session.createScreen('Pause');
      final made = UiCreate.create(doc, 'button')!;

      final slot = made.getComponent<UiSlotComponent>()!;
      expect(slot.mode, UiSlotMode.anchored);
      expect(slot.anchor, UiAnchor.center);
      expect(
        slot.rectIn(const Size(1920, 1080)).center,
        const Offset(960, 540),
      );
    });

    test('with a container selected, into it, in the flow', () {
      final doc = session.createScreen('Pause');
      final column = UiCreate.create(doc, 'column')!;
      final text = UiCreate.create(doc, 'text')!;

      expect(text.getComponent<ParentComponent>()!.parentId, column.id);
      expect(text.getComponent<UiSlotComponent>()!.mode, UiSlotMode.flow);
    });

    test('with an element selected, beside it — never into a button', () {
      final doc = session.createScreen('Pause');
      final button = UiCreate.create(doc, 'button')!;
      final next = UiCreate.create(doc, 'text')!;

      expect(
        button.getComponent<ChildrenComponent>()?.childIds ?? const [],
        isEmpty,
      );
      expect(next.getComponent<ParentComponent>()!.parentId, doc.canvas.id);
    });

    test('names are never shared, and making is undone in one step', () {
      final doc = session.createScreen('Pause');
      final a = UiCreate.create(doc, 'button')!;
      doc.sceneState.clearSelection();
      final b = UiCreate.create(doc, 'button')!;

      expect(a.name, isNot(b.name));
      doc.history.undo();
      expect(doc.world.findEntityByName(b.name!), isNull);
    });
  });

  group('editing elements', () {
    test('delete takes the selection but never the canvas', () {
      final doc = session.createScreen('Pause');
      UiCreate.create(doc, 'panel');
      doc.sceneState.selectEntity(doc.canvas);
      session.deleteSelection();
      expect(doc.entities, hasLength(2), reason: 'the canvas stays');

      doc.sceneState.selectEntity(doc.entities.last);
      session.deleteSelection();
      expect(doc.entities, hasLength(1));
    });

    test('duplicate copies children, with names of their own, beside it', () {
      final doc = session.createScreen('Pause');
      final card = UiCreate.create(doc, 'column')!;
      UiCreate.create(doc, 'text');
      doc.sceneState.selectEntity(card);

      session.duplicateSelection();

      final copy = doc.sceneState.selectedEntity.value!;
      expect(copy.name, isNot(card.name));
      final children = copy.getComponent<ChildrenComponent>()!.childIds;
      expect(children, hasLength(1));
      expect(doc.world.getEntity(children.single)!.name, isNot('Text'));
      expect(
        doc.canvas.getComponent<ChildrenComponent>()!.childIds.indexOf(copy.id),
        doc.canvas.getComponent<ChildrenComponent>()!.childIds.indexOf(
              card.id,
            ) +
            1,
      );
    });

    test('copy and paste into another screen', () {
      final first = session.createScreen('Pause');
      UiCreate.create(first, 'button');
      session.copySelection();
      session.save();

      final second = session.createScreen('Options');
      session.paste();

      expect(second.entities.map((e) => e.name), contains('Button'));
    });

    test('moving into a row turns pinned into flow; into a stack, back', () {
      final doc = session.createScreen('Pause');
      final row = UiCreate.create(doc, 'row')!;
      doc.sceneState.clearSelection();
      final button = UiCreate.create(doc, 'button')!;
      final stack = UiCreate.create(doc, 'stack', parent: doc.canvas)!;

      session.reparent([button], row);
      expect(button.getComponent<ParentComponent>()!.parentId, row.id);
      expect(button.getComponent<UiSlotComponent>()!.mode, UiSlotMode.flow);

      session.reparent([button], stack);
      expect(button.getComponent<UiSlotComponent>()!.mode, UiSlotMode.anchored);

      doc.history.undo();
      expect(button.getComponent<ParentComponent>()!.parentId, row.id);
      expect(button.getComponent<UiSlotComponent>()!.mode, UiSlotMode.flow);
    });

    test('reorder moves one among its siblings', () {
      final doc = session.createScreen('Pause');
      final column = UiCreate.create(doc, 'column')!;
      final a = UiCreate.create(doc, 'text')!;
      doc.sceneState.selectEntity(column);
      final b = UiCreate.create(doc, 'button')!;

      session.reorder(b, 0);

      expect(column.getComponent<ChildrenComponent>()!.childIds, [b.id, a.id]);
    });

    test('renaming the canvas renames the screen', () {
      final doc = session.createScreen('Pause');
      expect(session.rename(doc.canvas, 'Paused'), isTrue);
      expect(session.document.value!.path, 'assets/ui/paused.ui.json');
    });

    test('an element\'s name must be free', () {
      final doc = session.createScreen('Pause');
      final a = UiCreate.create(doc, 'button')!;
      doc.sceneState.clearSelection();
      UiCreate.create(doc, 'text');

      expect(session.rename(a, 'Text'), isFalse);
      expect(session.rename(a, 'Resume'), isTrue);
    });

    test('hiding is saved and undone', () {
      final doc = session.createScreen('Pause');
      final hint = UiCreate.create(doc, 'text')!;
      session.setVisible(hint, false);
      expect(hint.getComponent<UiSlotComponent>()!.visible, isFalse);
      doc.history.undo();
      expect(hint.getComponent<UiSlotComponent>()!.visible, isTrue);
    });

    test('switching off is saved, undone, and copied as it is', () {
      final doc = session.createScreen('Pause');
      final hint = UiCreate.create(doc, 'text')!;
      session.setEnabled(hint, false);
      expect(hint.isActive, isFalse);

      doc.sceneState.selectEntity(hint);
      session.duplicateSelection();
      final copy = doc.sceneState.selectedEntity.value!;
      expect(copy.id, isNot(hint.id));
      expect(copy.isActive, isFalse, reason: 'a copy of something off');

      session.copySelection();
      session.paste();
      expect(doc.sceneState.selectedEntity.value!.isActive, isFalse);

      doc.history.undo();
      doc.history.undo();
      doc.history.undo();
      expect(hint.isActive, isTrue);
    });

    test('duplicates go beside their own originals, whatever parents', () {
      final doc = session.createScreen('Pause');
      final column = UiCreate.create(doc, 'column', parent: doc.canvas)!;
      final inColumn = UiCreate.create(doc, 'text', parent: column)!;
      final panel = UiCreate.create(doc, 'panel', parent: doc.canvas)!;
      final inPanel = UiCreate.create(doc, 'button', parent: panel)!;
      doc.sceneState.selectEntity(inColumn);
      doc.sceneState.toggleMultiSelect(inPanel);

      session.duplicateSelection();

      List<String?> names(Entity parent) => [
        for (final id in parent.getComponent<ChildrenComponent>()!.childIds)
          doc.world.getEntity(id)!.name,
      ];
      expect(names(column), hasLength(2));
      expect(names(panel), hasLength(2));
      expect(names(column).first, inColumn.name);
      expect(names(panel).first, inPanel.name);
    });

    test('two copies in one parent each land after their original', () {
      final doc = session.createScreen('Pause');
      final column = UiCreate.create(doc, 'column', parent: doc.canvas)!;
      final a = UiCreate.create(doc, 'text', parent: column)!;
      final b = UiCreate.create(doc, 'button', parent: column)!;
      doc.sceneState.selectEntity(a);
      doc.sceneState.toggleMultiSelect(b);

      session.duplicateSelection();

      final order = [
        for (final id in column.getComponent<ChildrenComponent>()!.childIds)
          doc.world.getEntity(id)!.name,
      ];
      expect(order, ['Text', 'Text2', 'Button', 'Button2']);
    });
  });

  group('undo reaches an element made again', () {
    UiSlotState moved(UiSlotState s) =>
        s.copyWith(offset: s.offset + const Offset(100, 0));

    test('a move undone with its making, and both made again', () {
      final doc = session.createScreen('Pause');
      final button = UiCreate.create(doc, 'button')!;
      final before = UiSlotState.of(button.getComponent<UiSlotComponent>()!);
      doc.history.push(
        UiSlotEditCommand(
          label: 'Move',
          sceneState: doc.sceneState,
          changes: {button: (before, moved(before))},
        ),
      );

      doc.history
        ..undo()
        ..undo()
        ..redo()
        ..redo();

      final again = doc.world.findEntityByName(button.name!)!;
      expect(again.id, isNot(button.id), reason: 'made again, a new entity');
      expect(
        again.getComponent<UiSlotComponent>()!.offset,
        moved(before).offset,
      );
    });

    test('a move before a delete is undone after the delete is', () {
      final doc = session.createScreen('Pause');
      final button = UiCreate.create(doc, 'button')!;
      final before = UiSlotState.of(button.getComponent<UiSlotComponent>()!);
      doc.history.push(
        UiSlotEditCommand(
          label: 'Move',
          sceneState: doc.sceneState,
          changes: {button: (before, moved(before))},
        ),
      );
      doc.sceneState.selectEntity(button);
      session.deleteSelection();

      doc.history
        ..undo()
        ..undo();

      final again = doc.world.findEntityByName(button.name!)!;
      expect(again.getComponent<UiSlotComponent>()!.offset, before.offset);
    });
  });

  group('names that share a file', () {
    test('a new screen never takes a file another one has', () {
      session.createScreen('MainMenu');
      final path = 'assets/ui/main_menu.ui.json';
      final bytes = File('${dir.path}/$path').readAsBytesSync();

      for (final typed in const ['Main Menu', 'main_menu', 'MAIN MENU']) {
        expect(session.freeScreenName(typed), '${typed}2', reason: typed);
        expect(
          () => session.createScreen(typed),
          throwsA(isA<FileSystemException>()),
          reason: typed,
        );
      }
      expect(File('${dir.path}/$path').readAsBytesSync(), bytes);
    });

    test('duplicating twice makes two copies', () {
      final doc = session.createScreen('Main Menu');
      final first = session.duplicateScreen(doc.path);
      final second = session.duplicateScreen(doc.path);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second, isNot(first));
      expect(session.manifest.value.screens, hasLength(3));
    });
  });

  group('a screen list that does not read', () {
    late List<int> bytes;

    setUp(() {
      session.createScreen('Pause');
      final list = File('${dir.path}/${UiScreenManifest.defaultPath}');
      list.writeAsStringSync('{"format": 1, "screens": [,]}');
      bytes = list.readAsBytesSync();
      session.refreshFiles();
    });

    List<int> onDisk() =>
        File('${dir.path}/${UiScreenManifest.defaultPath}').readAsBytesSync();

    test('says so, and is never written over', () {
      expect(session.manifestProblem.value, isNotNull);

      expect(session.setStartOpen('assets/ui/pause.ui.json', true), isFalse);
      expect(session.lastError, contains('does not read'));
      expect(session.setListed('assets/ui/pause.ui.json', false), isFalse);
      expect(session.renameScreen('assets/ui/pause.ui.json', 'Paws'), isFalse);
      expect(session.deleteScreen('assets/ui/pause.ui.json'), isFalse);
      expect(session.duplicateScreen('assets/ui/pause.ui.json'), isNull);
      expect(
        () => session.createScreen('Options'),
        throwsA(isA<FormatException>()),
      );

      expect(onDisk(), bytes);
      expect(File('${dir.path}/assets/ui/pause.ui.json').existsSync(), isTrue);
      expect(
        File('${dir.path}/assets/ui/options.ui.json').existsSync(),
        isFalse,
      );
    });

    test('nor by the project itself', () {
      expect(
        () => UiProject(dir.path).writeManifest(UiScreenManifest()),
        throwsA(isA<FormatException>()),
      );
      expect(onDisk(), bytes);
    });
  });

  group('a screen list with keys it does not know', () {
    final json = {
      'format': 1,
      'notes': 'kept by hand',
      'screens': [
        {'path': 'assets/ui/pause.ui.json', 'group': 'menus'},
      ],
    };

    test('reads and writes them back as they were', () {
      final list = UiScreenManifest.fromJson(json);
      expect(list.extra, {'notes': 'kept by hand'});
      expect(list.screens.single.extra, {'group': 'menus'});
      expect(list.toJson(), json);
      expect(
        list.withScreens([
          list.screens.single.copyWith(startOpen: true),
        ]).toJson(),
        {
          'format': 1,
          'notes': 'kept by hand',
          'screens': [
            {
              'path': 'assets/ui/pause.ui.json',
              'group': 'menus',
              'startOpen': true,
            },
          ],
        },
      );
    });

    test('and the editor keeps them through its changes', () {
      session.createScreen('Pause');
      File(
        '${dir.path}/${UiScreenManifest.defaultPath}',
      ).writeAsStringSync(jsonEncode(json));
      session.refreshFiles();

      expect(session.setStartOpen('assets/ui/pause.ui.json', true), isTrue);
      expect(session.renameScreen('assets/ui/pause.ui.json', 'Paws'), isTrue);

      final saved = readJson(UiScreenManifest.defaultPath);
      expect(saved['notes'], 'kept by hand');
      expect(saved['screens'], [
        {'path': 'assets/ui/paws.ui.json', 'group': 'menus', 'startOpen': true},
      ]);
    });
  });

  group('renaming a screen', () {
    test('to the name another screen has, in a file of another name', () {
      session.createScreen('Options');
      // A file named for one thing, holding a screen called another.
      final pause = UiDocument.capture(
        (_uiWorld()..initialize()).createEntityWithComponents([
          UiCanvasComponent(),
        ], name: 'Pause'),
        _uiWorld()..initialize(),
      );
      UiProject(dir.path).writeScreen('assets/ui/pause_menu.ui.json', pause);
      session.refreshFiles();

      expect(
        session.renameScreen('assets/ui/options.ui.json', 'Pause'),
        isFalse,
      );
      expect(session.lastError, contains('Another screen is already called'));
    });

    test('to the name of one of its own elements', () {
      final doc = session.createScreen('Hud');
      UiCreate.create(doc, 'text', parent: doc.canvas);

      expect(session.rename(doc.canvas, 'Text'), isFalse);
      expect(session.lastError, contains('its own elements'));
      expect(doc.name, 'Hud');
    });

    test('what is shown under the open one follows the new name', () {
      session.createScreen('Hud');
      session.createScreen('Pause');
      session.behind.value = ['Hud'];

      expect(session.renameScreen('assets/ui/hud.ui.json', 'Overlay'), isTrue);
      expect(session.behind.value, ['Overlay']);
    });
  });

  group('every file written is told of', () {
    test('saving, listing, renaming, copying and deleting', () {
      final heard = <String>[];
      final told = UiEditorSession(
        project: UiProject(dir.path),
        onFilesChanged: heard.addAll,
      );
      addTearDown(told.dispose);

      final doc = told.createScreen('Pause');
      expect(heard, contains(doc.path));
      heard.clear();

      UiCreate.create(doc, 'text');
      told.save();
      expect(heard, [doc.path]);
      heard.clear();

      told.setStartOpen(doc.path, true);
      expect(heard, [UiScreenManifest.defaultPath]);
      heard.clear();

      final copy = told.duplicateScreen(doc.path)!;
      expect(heard, containsAll([copy, UiScreenManifest.defaultPath]));
      heard.clear();

      told.renameScreen(copy, 'Paws');
      expect(
        heard,
        containsAll([
          'assets/ui/paws.ui.json',
          copy,
          UiScreenManifest.defaultPath,
        ]),
      );
      heard.clear();

      told.deleteScreen('assets/ui/paws.ui.json');
      expect(heard, contains('assets/ui/paws.ui.json'));
    });
  });

  group('files that do not read, and writes that fail', () {
    test('a screen that does not read says why', () {
      File('${dir.path}/assets/ui/broken.ui.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"entities": [');

      expect(session.open('assets/ui/broken.ui.json'), isFalse);
      expect(session.lastError, startsWith('assets/ui/broken.ui.json'));
    });

    test('a save that fails says so, and the screen stays unsaved', () {
      final doc = session.createScreen('Pause');
      UiCreate.create(doc, 'text');
      // Something that is no file stands where it is saved.
      File('${dir.path}/${doc.path}').deleteSync();
      Directory('${dir.path}/${doc.path}').createSync();

      expect(session.save(), isFalse);
      expect(session.lastError, contains(doc.path));
      expect(doc.dirty.value, isTrue);
      expect(
        File('${dir.path}/${doc.path}.saving').existsSync(),
        isFalse,
        reason: 'what was half written is cleared away',
      );
    });

    test('nothing is written outside the project', () {
      final project = UiProject(dir.path);
      expect(project.isWritable('../elsewhere.ui.json'), isFalse);
      expect(
        () => project.writeSync('../elsewhere.ui.json', '{}'),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File('${dir.parent.path}/elsewhere.ui.json').existsSync(),
        isFalse,
      );
    });

    test('an editor section edited by hand opens all the same', () {
      final doc = session.createScreen('Pause');
      session.save();
      final json = readJson(doc.path)
        ..['editor'] = {
          'guides': {'at': 3},
          'samples': ['coins'],
          'device': {'name': 'Mine', 'width': '390', 'height': 0},
        };
      File('${dir.path}/${doc.path}').writeAsStringSync(jsonEncode(json));

      expect(session.open(doc.path), isTrue);
      expect(session.guides, isEmpty);
      expect(session.samples, isEmpty);
      final device = session.device.value;
      expect(device.width, 1280, reason: 'a size that is not a number');
      expect(device.height, UiDevice.minSide);
    });

    test('guides that are half right keep what is right', () {
      final doc = session.createScreen('Pause');
      session.save();
      final json = readJson(doc.path)
        ..['editor'] = {
          'guides': [
            {'axis': 'x', 'at': 12},
            {'axis': 'y', 'at': 'twelve'},
            'nonsense',
          ],
        };
      File('${dir.path}/${doc.path}').writeAsStringSync(jsonEncode(json));

      expect(session.open(doc.path), isTrue);
      expect(session.guides, const [UiGuide(vertical: true, at: 12)]);
    });
  });
}
