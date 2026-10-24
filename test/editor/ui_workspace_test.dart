// The interface editor in a window, pressed and dragged as a person would:
// on a 1920×1080 screen shrunk onto a phone, where a drag that forgot the
// scale moved things a fifth as far as the pointer.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import 'package:just_ui_editor/src/editor/canvas/ui_rulers.dart';
import 'package:just_ui_editor/src/editor/panels/hierarchy_panel.dart';
import 'package:just_ui_editor/src/editor/session/ui_slot_edit.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  late Directory dir;
  late EditorScope scope;
  late int closed;
  Future<bool> Function()? guard;

  /// A pause menu at 1920×1080, fitted: a pinned button in the middle, a
  /// column of two texts on the left, a text field.
  Map<String, dynamic> pauseScreen() {
    final world = _uiWorld()..initialize();
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(isScreen: true, modal: true),
    ], name: 'Pause');
    final button = world.createEntityWithComponents([
      ButtonComponent(
        label: 'Resume',
        onPressed: const UiActionList([UiAction('game.resume')]),
      ),
      UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.center,
        size: const Size(400, 120),
      ),
    ], name: 'Resume');
    final column = world.createEntityWithComponents([
      UiLayoutComponent(kind: UiLayoutKind.column),
      UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.centerLeft,
        pivot: const Offset(0, 0.5),
        offset: const Offset(40, 0),
        size: const Size(300, 400),
      ),
    ], name: 'Column');
    final first = world.createEntityWithComponents([
      TextComponent(text: 'First'),
      UiSlotComponent(size: const Size(300, 80)),
    ], name: 'First');
    final second = world.createEntityWithComponents([
      TextComponent(text: 'Second'),
      UiSlotComponent(size: const Size(300, 80)),
    ], name: 'Second');
    final field = world.createEntityWithComponents([
      UiTextFieldComponent(hint: 'Name'),
      UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.bottomCenter,
        pivot: const Offset(0.5, 1),
        size: const Size(500, 90),
      ),
    ], name: 'Field');
    UiDocument.link(button, canvas);
    UiDocument.link(column, canvas);
    UiDocument.link(first, column);
    UiDocument.link(second, column);
    UiDocument.link(field, canvas);
    return UiDocument.capture(canvas, world).toJson();
  }

  String file(String path) => '${dir.path}/$path';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ui_workspace');
    Directory(file('assets/ui')).createSync(recursive: true);
    File(
      file('assets/ui/pause.ui.json'),
    ).writeAsStringSync(jsonEncode(pauseScreen()));
    File(file('assets/ui/screens.json')).writeAsStringSync(
      jsonEncode({
        'screens': [
          {'path': 'assets/ui/pause.ui.json'},
        ],
      }),
    );
    scope = EditorScope(
      world: _uiWorld()..initialize(),
      modules: [UiEditorModule(root: dir.path)],
    );
    closed = 0;
    guard = null;
    addTearDown(() {
      scope.dispose();
      UiThemes.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  Future<UiEditorWorkspaceState> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1500, 950)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<UiEditorWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: UiEditorWorkspace(
              key: key,
              scope: scope,
              project: UiProject(dir.path),
              onClose: () => closed++,
              setCloseGuard: (g) => guard = g,
            ),
          ),
        ),
      ),
    );
    // The canvas reads back its layout a frame after it is drawn.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return key.currentState!;
  }

  Future<void> frames(WidgetTester tester, [int n = 3]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Drags with a mouse from [from] (in the canvas view's own pixels, as
  /// the metrics give them) by [by], in [steps] moves.
  Future<void> drag(
    WidgetTester tester,
    UiEditorWorkspaceState ws,
    Offset viewFrom,
    Offset by, {
    int steps = 5,
  }) async {
    final from = ws.session.metrics!.view.localToGlobal(viewFrom);
    final mouse = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    for (var i = 1; i <= steps; i++) {
      await mouse.moveTo(from + by * (i / steps));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mouse.up();
    await frames(tester);
  }

  testWidgets('opens the game\'s first screen and draws it', (tester) async {
    final ws = await open(tester);

    expect(ws.session.document.value!.name, 'Pause');
    expect(find.text('Resume', findRichText: true), findsWidgets);
    expect(ws.session.metrics, isNotNull);
    expect(ws.session.metrics!.scale, lessThan(0.5), reason: 'shrunk to fit');
  });

  testWidgets('a drag moves as far as the pointer, whatever the scale', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    final button = doc.world.findEntityByName('Resume')!;
    final slot = button.getComponent<UiSlotComponent>()!;
    final m = ws.session.metrics!;
    final at = m.viewRectOf(button)!.center;
    ws.session.snap.value = false;

    await drag(tester, ws, at, const Offset(60, 0));

    expect(slot.offset.dx, closeTo(60 / m.scale, 1.0));
    expect(m.viewRectOf(button)!.center.dx, closeTo(at.dx + 60, 1.5));
  });

  testWidgets('one drag is one undo step, and two are two', (tester) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    final button = doc.world.findEntityByName('Resume')!;
    final slot = button.getComponent<UiSlotComponent>()!;
    ws.session.snap.value = false;

    await drag(
      tester,
      ws,
      ws.session.metrics!.viewRectOf(button)!.center,
      const Offset(40, 0),
    );
    final afterFirst = slot.offset;
    await drag(
      tester,
      ws,
      ws.session.metrics!.viewRectOf(button)!.center,
      const Offset(0, 40),
    );

    expect(doc.history.undoDepth, 2);
    doc.history.undo();
    expect(slot.offset, afterFirst);
    doc.history.undo();
    expect(slot.offset, Offset.zero);
  });

  testWidgets('a click selects and records nothing', (tester) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    final button = doc.world.findEntityByName('Resume')!;

    await drag(
      tester,
      ws,
      ws.session.metrics!.viewRectOf(button)!.center,
      const Offset(1, 1),
      steps: 1,
    );

    expect(doc.sceneState.selectedEntity.value?.id, button.id);
    expect(doc.history.canUndo.value, isFalse);
    expect(doc.dirty.value, isFalse);
  });

  testWidgets('a layer over the whole screen does not take every click', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    // Touch controls, say: stretched over everything, drawn last.
    final overlay = UiCreate.create(doc, 'panel', parent: doc.canvas)!;
    overlay.getComponent<UiSlotComponent>()!
      ..anchor = UiAnchor.stretch
      ..margin = EdgeInsets.zero;
    doc.sceneState.clearSelection();
    await frames(tester, 4);
    final button = doc.world.findEntityByName('Resume')!;

    await drag(
      tester,
      ws,
      ws.session.metrics!.viewRectOf(button)!.center,
      const Offset(1, 1),
      steps: 1,
    );
    expect(doc.sceneState.selectedEntity.value?.id, button.id);

    // Where nothing smaller is, the layer is what is there.
    final corner = ws.session.metrics!.canvasView!.topLeft + const Offset(4, 4);
    await drag(tester, ws, corner, const Offset(1, 1), steps: 1);
    expect(doc.sceneState.selectedEntity.value?.id, overlay.id);
  });

  testWidgets('the right handle moves the right edge, and only it', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    final button = doc.world.findEntityByName('Resume')!;
    doc.sceneState.selectEntity(button);
    ws.session.snap.value = false;
    await frames(tester);
    final m = ws.session.metrics!;
    final before = m.viewRectOf(button)!;

    await drag(tester, ws, before.centerRight, const Offset(30, 0));

    final after = m.viewRectOf(button)!;
    expect(after.left, closeTo(before.left, 1.5));
    expect(after.right, closeTo(before.right + 30, 1.5));
    expect(
      button.getComponent<UiSlotComponent>()!.size.width,
      closeTo(400 + 30 / m.scale, 1.0),
    );
  });

  testWidgets('a text in a column is dragged to a new place in it', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    final column = doc.world.findEntityByName('Column')!;
    final first = doc.world.findEntityByName('First')!;
    final second = doc.world.findEntityByName('Second')!;
    final m = ws.session.metrics!;
    final from = m.viewRectOf(first)!.center;
    final below = m.viewRectOf(second)!.bottomCenter + const Offset(0, 4);

    await drag(tester, ws, from, below - from);

    expect(column.getComponent<ChildrenComponent>()!.childIds, [
      second.id,
      first.id,
    ]);
    expect(doc.history.undoDepth, 1);
  });

  testWidgets('Escape in a text field does not close the editor', (
    tester,
  ) async {
    await open(tester);
    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);

    expect(closed, 0);
  });

  testWidgets('Escape steps back: the selection first, then out', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);
    await frames(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    expect(doc.sceneState.hasAnySelection, isFalse);
    expect(closed, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    expect(closed, 1);
  });

  testWidgets('Ctrl+S saves the screen, and the dot goes', (tester) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames(tester);
    expect(doc.dirty.value, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await frames(tester);

    expect(doc.dirty.value, isFalse);
    final saved = jsonDecode(
      File(file('assets/ui/pause.ui.json')).readAsStringSync(),
    );
    expect((saved['entities'] as List).length, 7, reason: 'the duplicate too');
  });

  testWidgets('closing with unsaved work asks first', (tester) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    UiCreate.create(doc, 'text');
    await frames(tester);

    final leaving = guard!();
    await frames(tester);
    expect(find.text('Save the interface?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await frames(tester);

    expect(await leaving, isFalse);
  });

  testWidgets('in Preview a button is pressed, and says what it would do', (
    tester,
  ) async {
    final ws = await open(tester);
    ws.session.mode.value = UiEditMode.preview;
    await frames(tester, 30);

    await tester.tap(find.text('Resume', findRichText: true).last);
    await frames(tester);

    expect(ws.session.lastAction.value, 'Resumes the game');
    expect(ws.session.document.value!.history.canUndo.value, isFalse);
  });

  testWidgets('a widget from the palette is added where it can be seen', (
    tester,
  ) async {
    final ws = await open(tester);
    final doc = ws.session.document.value!;
    doc.sceneState.clearSelection();
    await frames(tester);

    await tester.ensureVisible(find.text('Slider').first);
    await frames(tester);
    await tester.tap(find.text('Slider').first);
    await frames(tester);

    final made = doc.sceneState.selectedEntity.value!;
    expect(made.hasComponent<UiSliderComponent>(), isTrue);
    final m = ws.session.metrics!;
    expect(m.canvasView!.overlaps(m.viewRectOf(made)!), isTrue);
  });

  testWidgets('a game with a theme opens on it, with nothing built twice', (
    tester,
  ) async {
    File(file('assets/ui/default.uitheme.json')).writeAsStringSync(
      jsonEncode(UiTheme.fallback.copyWith(name: 'default').toJson()),
    );
    File(file('assets/ui/screens.json')).writeAsStringSync(
      jsonEncode({
        'theme': 'assets/ui/default.uitheme.json',
        'screens': [
          {'path': 'assets/ui/pause.ui.json'},
        ],
      }),
    );

    final ws = await open(tester);

    expect(tester.takeException(), isNull);
    expect(ws.session.theme.value?.path, 'assets/ui/default.uitheme.json');
  });

  testWidgets('just opened, the rulers and the zoom know the frame', (
    tester,
  ) async {
    final ws = await open(tester);

    // Nothing but frames has happened since it was built: what is drawn
    // must still have caught up with the laid-out frame.
    final rulers = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<UiRulersPainter>()
        .single;
    expect(rulers.metrics(), isNotNull);
    final fitted = (ws.session.fittedZoom * 100).round();
    expect(fitted, isNot(100));
    expect(find.text('$fitted%'), findsOneWidget);
  });

  /// Writes another screen beside the pause menu: [children] as
  /// `(name, components, parent)`, a parent of null meaning the canvas.
  void otherScreen(
    String name,
    List<(String, List<Component>, String?)> children, {
    bool isScreen = false,
  }) {
    final world = _uiWorld()..initialize();
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(isScreen: isScreen),
    ], name: name);
    for (final (child, components, parent) in children) {
      UiDocument.link(
        world.createEntityWithComponents(components, name: child),
        parent == null ? canvas : world.findEntityByName(parent)!,
      );
    }
    File(
      file('assets/ui/${UiSceneExtractor.fileNameFor(name)}'),
    ).writeAsStringSync(jsonEncode(UiDocument.capture(canvas, world).toJson()));
  }

  UiSlotComponent textSlot() => UiSlotComponent(
    mode: UiSlotMode.anchored,
    anchor: UiAnchor.center,
    size: const Size(600, 100),
  );

  group('unsaved work is asked about', () {
    testWidgets('before a copy opens in its place', (tester) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      UiCreate.create(doc, 'text');
      await frames(tester);

      unawaited(ws.duplicateScreen('assets/ui/pause.ui.json'));
      await frames(tester);
      expect(find.text('Save Pause?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await frames(tester);

      expect(ws.session.document.value, same(doc));
      expect(doc.dirty.value, isTrue);
    });

    testWidgets('before "Open it" opens what a button would', (tester) async {
      otherScreen('Options', const [], isScreen: true);
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      UiCreate.create(doc, 'text');
      ws.session.lastAction.value = 'Opens Options';
      await frames(tester);

      await tester.tap(find.text('Open it'));
      await frames(tester);
      expect(find.text('Save Pause?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await frames(tester);

      expect(ws.session.document.value, same(doc));
    });
  });

  group('dragging', () {
    testWidgets('given up with Escape, leaves nothing behind', (tester) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      final button = doc.world.findEntityByName('Resume')!;
      final slot = button.getComponent<UiSlotComponent>()!;
      final start = slot.offset;
      final m = ws.session.metrics!;
      final from = m.view.localToGlobal(m.viewRectOf(button)!.center);

      final mouse = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      for (var i = 1; i <= 4; i++) {
        await mouse.moveTo(from + Offset(15.0 * i, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(slot.offset, isNot(start), reason: 'it follows the pointer');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await mouse.up();
      await frames(tester);

      expect(slot.offset, start);
      expect(doc.history.canUndo.value, isFalse);
      expect(doc.dirty.value, isFalse);
      expect(closed, 0);
    });

    testWidgets('out and back again is where it began, and no step', (
      tester,
    ) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      final button = doc.world.findEntityByName('Resume')!;
      final slot = button.getComponent<UiSlotComponent>()!;
      final start = UiSlotState.of(slot);
      ws.session.snap.value = false;
      final m = ws.session.metrics!;
      final from = m.view.localToGlobal(m.viewRectOf(button)!.center);

      final mouse = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      await mouse.moveTo(from + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await mouse.moveTo(from + const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await mouse.moveTo(from);
      await tester.pump(const Duration(milliseconds: 16));
      await mouse.up();
      await frames(tester);

      expect(UiSlotState.of(slot), start);
      expect(doc.history.canUndo.value, isFalse);
    });

    testWidgets('a move keeps the size it was given', (tester) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      final button = doc.world.findEntityByName('Resume')!;
      final slot = button.getComponent<UiSlotComponent>()!;
      ws.session.snap.value = false;

      await drag(
        tester,
        ws,
        ws.session.metrics!.viewRectOf(button)!.center,
        const Offset(37, 23),
      );

      expect(slot.size, const Size(400, 120));
      final offset = slot.offset;
      expect((offset.dx * 100).roundToDouble() / 100, offset.dx);
      expect(doc.history.undoDepth, 1);
    });

    testWidgets('a marquee around one element selects that one alone', (
      tester,
    ) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      final button = doc.world.findEntityByName('Resume')!;
      final r = ws.session.metrics!.viewRectOf(button)!;

      await drag(
        tester,
        ws,
        r.topLeft - const Offset(10, 10),
        Offset(r.width + 20, r.height + 20),
      );

      expect(ws.session.selection.map((e) => e.name), ['Resume']);
    });

    testWidgets('a click on empty space selects the screen itself', (
      tester,
    ) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      final r = ws.session.metrics!.viewRectOf(
        doc.world.findEntityByName('Resume')!,
      )!;

      await drag(
        tester,
        ws,
        r.topLeft - const Offset(10, 10),
        const Offset(1, 1),
        steps: 1,
      );

      expect(doc.sceneState.selectedEntity.value?.id, doc.canvas.id);
    });

    testWidgets('a hover redraws the overlay, not the screen', (tester) async {
      final ws = await open(tester);
      final layer = tester.widget<UiLayer>(find.byType(UiLayer).first);
      final m = ws.session.metrics!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: m.view.localToGlobal(Offset.zero));
      for (var i = 1; i <= 6; i++) {
        await mouse.moveTo(m.view.localToGlobal(Offset(60.0 * i, 40.0 * i)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await mouse.removePointer();

      expect(
        identical(tester.widget<UiLayer>(find.byType(UiLayer).first), layer),
        isTrue,
      );
    });
  });

  testWidgets('a second screen chosen to go underneath shows', (tester) async {
    otherScreen('Hud', [
      ('HudText', [TextComponent(text: 'HUDTEXT'), textSlot()], null),
    ]);
    otherScreen('Options', [
      ('OptionsText', [TextComponent(text: 'OPTIONSTEXT'), textSlot()], null),
    ], isScreen: true);
    final ws = await open(tester);

    ws.session.behind.value = ['Hud'];
    await frames(tester, 6);
    expect(find.text('HUDTEXT', findRichText: true), findsWidgets);

    ws.session.behind.value = ['Hud', 'Options'];
    await frames(tester, 6);
    expect(find.text('HUDTEXT', findRichText: true), findsWidgets);
    expect(find.text('OPTIONSTEXT', findRichText: true), findsWidgets);
  });

  testWidgets('what a player does in Preview never reaches the file', (
    tester,
  ) async {
    otherScreen('Settings', [
      (
        'Music',
        [
          UiToggleComponent(label: 'Music'),
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.center,
            offset: const Offset(0, -200),
            size: const Size(600, 100),
          ),
        ],
        null,
      ),
      (
        'Name',
        [
          UiTextFieldComponent(hint: 'Name'),
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.center,
            offset: const Offset(0, 200),
            size: const Size(600, 100),
          ),
        ],
        null,
      ),
    ], isScreen: true);
    final ws = await open(tester);
    await ws.openScreen('assets/ui/settings.ui.json');
    await frames(tester);
    final doc = ws.session.document.value!;
    final before = jsonEncode(doc.capture().toJson());

    ws.session.mode.value = UiEditMode.preview;
    await frames(tester, 20);
    await tester.tap(find.byType(Switch).last);
    await frames(tester);
    await tester.enterText(find.byType(TextField).last, 'abc');
    await frames(tester);
    ws.session.mode.value = UiEditMode.edit;
    await frames(tester, 4);

    expect(jsonEncode(doc.capture().toJson()), before);
    expect(doc.dirty.value, isFalse);
    expect(doc.settings!.visible, isTrue);
  });

  group('what went wrong is said', () {
    testWidgets('a save that fails', (tester) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      UiCreate.create(doc, 'text');
      File(file(doc.path)).deleteSync();
      Directory(file(doc.path)).createSync();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await frames(tester);

      expect(find.text('Not saved'), findsOneWidget);
      expect(doc.dirty.value, isTrue);
    });

    testWidgets('a screen that does not open', (tester) async {
      File(file('assets/ui/broken.ui.json')).writeAsStringSync('{"x": [');
      final ws = await open(tester);

      unawaited(ws.openScreen('assets/ui/broken.ui.json'));
      await frames(tester);

      expect(find.text('That screen does not open'), findsOneWidget);
      expect(ws.session.document.value!.name, 'Pause');
    });

    testWidgets('a new screen\'s name that is taken, offering a free one', (
      tester,
    ) async {
      final ws = await open(tester);
      // Menus and dialogs take a moment to open; the canvas never settles.
      Future<void> opened() => frames(tester, 30);
      await tester.tap(find.byTooltip('New screen'));
      await opened();
      await tester.tap(find.text('Screen — opened and closed'));
      await opened();
      await tester.enterText(find.byType(TextField).last, 'Pause');
      await tester.tap(find.text('OK'));
      await opened();

      expect(find.text('That name is taken'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await opened();
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'Pause2',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await opened();

      expect(ws.session.document.value!.name, 'Pause2');
      expect(
        jsonDecode(File(file('assets/ui/pause.ui.json')).readAsStringSync()),
        containsPair('name', 'Pause'),
        reason: 'the one there is left alone',
      );
    });

    testWidgets('a name the inspector refuses', (tester) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);
      await frames(tester);

      // The title's box, above the button's own label.
      final title = find
          .byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'Resume',
          )
          .first;
      await tester.enterText(title, 'First');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await frames(tester);

      expect(
        find.text('Something else on this screen is called First.'),
        findsOneWidget,
      );
      expect(doc.world.findEntityByName('Resume'), isNotNull);
    });
  });

  testWidgets('what is folded in one screen is not folded in the next', (
    tester,
  ) async {
    otherScreen('Other', [
      ('Lead', [TextComponent(text: 'x'), textSlot()], null),
      ('Strip', [UiLayoutComponent(kind: UiLayoutKind.row), textSlot()], null),
      ('RowChild', [TextComponent(text: 'y'), UiSlotComponent()], 'Strip'),
    ]);
    final ws = await open(tester);
    final column = ws.session.document.value!.world.findEntityByName('Column')!;
    // Its id is the one the other screen's row will have.
    expect(column.id, 2);
    Finder inTree(Finder finder) =>
        find.descendant(of: find.byType(UiHierarchyPanel), matching: finder);
    await tester.tap(inTree(find.byIcon(Icons.expand_more_rounded)).at(1));
    await frames(tester);
    expect(inTree(find.text('First')), findsNothing, reason: 'folded');

    await ws.openScreen('assets/ui/other.ui.json');
    await frames(tester);

    expect(inTree(find.text('RowChild')), findsOneWidget);
  });

  group('on a Mac', () {
    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await frames(tester);
    }

    testWidgets('Cmd makes the shortcuts, and Ctrl does not', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final ws = await open(tester);
        final doc = ws.session.document.value!;
        doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);

        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyD,
        );
        expect(doc.dirty.value, isFalse, reason: 'Ctrl+D is no shortcut here');

        await chord(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyD,
        );
        expect(doc.dirty.value, isTrue);
        await chord(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyS,
        );
        expect(doc.dirty.value, isFalse);
        await chord(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.keyZ,
        );
        expect(doc.dirty.value, isTrue, reason: 'Cmd+Z undid the copy');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Backspace deletes, as the Mac\'s delete key', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final ws = await open(tester);
        final doc = ws.session.document.value!;
        doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);
        await frames(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await frames(tester);

        expect(doc.world.findEntityByName('Resume'), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('elsewhere Backspace leaves the selection alone', (
      tester,
    ) async {
      final ws = await open(tester);
      final doc = ws.session.document.value!;
      doc.sceneState.selectEntity(doc.world.findEntityByName('Resume')!);
      await frames(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await frames(tester);
      expect(doc.world.findEntityByName('Resume'), isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await frames(tester);
      expect(doc.world.findEntityByName('Resume'), isNull);
    });
  });
}
