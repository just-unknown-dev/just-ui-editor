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

      expect(session.duplicateScreen(doc.path), isTrue);

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
  });
}
