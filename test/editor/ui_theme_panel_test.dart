// The Theme tab of the interface editor: one file for a whole game's look,
// with its own undo and Save.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import 'package:just_ui_editor/src/editor/theme/theme_panel.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  const themePath = 'assets/ui/default.uitheme.json';
  late Directory dir;
  late UiEditorSession session;
  late EditorScope scope;

  File file(String path) => File('${dir.path}/$path');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ui_theme_panel');
    session = UiEditorSession(project: UiProject(dir.path));
    scope = EditorScope(world: _uiWorld()..initialize());
    addTearDown(() {
      session.dispose();
      scope.dispose();
      UiThemes.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  void writeTheme(UiTheme theme) => file(themePath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(theme.toJson()),
    );

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: UiThemePanel(session: session),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no theme in the project, it offers to make one', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(find.text('No theme yet'), findsOneWidget);

    await tester.tap(find.text('Make one'));
    await tester.pump();

    expect(file(themePath).existsSync(), isTrue);
    expect(find.text('primary'), findsOneWidget);
  });

  group('over a project with a theme', () {
    setUp(() {
      writeTheme(
        UiTheme.fallback.copyWith(
          name: 'default',
          palette: const UiPalette(primary: Color(0xFF112233)),
          radius: 10,
        ),
      );
      session.openTheme(themePath);
    });

    testWidgets('every colour, text role and sound, and a sample card', (
      tester,
    ) async {
      await pumpPanel(tester);

      for (final role in UiPalette.roles) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      for (final role in const ['title', 'body', 'caption', 'button']) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      for (final sound in const ['Hover', 'Press', 'Toggle']) {
        expect(find.text(sound), findsOneWidget, reason: sound);
      }
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a change is its own undo step, and Save writes it', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.byTooltip('Not saved'), findsNothing);

      final corner = find.descendant(
        of: find.ancestor(
          of: find.text('Corner'),
          matching: find.byType(ScrubFieldRow),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(corner, '18');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byTooltip('Not saved'), findsOneWidget);

      final doc = session.theme.value!;
      doc.history.undo();
      await tester.pump();
      expect(doc.theme.value.radius, 10);
      expect(find.byTooltip('Not saved'), findsNothing);

      doc.history.redo();
      await tester.pump();
      await tester.tap(find.byTooltip('Save the theme'));
      await tester.pump();

      final onDisk = UiTheme.parse(file(themePath).readAsStringSync());
      expect(onDisk.radius, 18);
      expect(onDisk.name, 'default');
      expect(find.byTooltip('Not saved'), findsNothing);
    });

    testWidgets('an open screen can be drawn with it, as an undoable edit', (
      tester,
    ) async {
      final screen = session.createScreen('Pause');
      await pumpPanel(tester);
      expect(find.textContaining('Pause is drawn with'), findsOneWidget);

      await tester.tap(find.text('Draw Pause with this theme'));
      await tester.pump();

      expect(screen.settings!.theme, themePath);
      expect(find.textContaining('Pause is drawn with'), findsNothing);
      screen.history.undo();
      expect(screen.settings!.theme, isEmpty);
    });

    testWidgets('two presses are two steps, though they change one thing', (
      tester,
    ) async {
      await pumpPanel(tester);
      final doc = session.theme.value!;
      Future<void> press() async {
        await tester.tap(find.text('COLOURS'));
        await tester.pump();
      }

      await press();
      doc.change(doc.theme.value.copyWith(radius: 12), 'Corner');
      doc.change(doc.theme.value.copyWith(radius: 14), 'Corner');
      await press();
      doc.change(doc.theme.value.copyWith(radius: 16), 'Corner');

      expect(doc.history.undoDepth, 2, reason: 'one per press');
      doc.history.undo();
      expect(doc.theme.value.radius, 14);
    });
  });

  group('unsaved edits let go of', () {
    test('are not what the screens go on drawing with', () async {
      writeTheme(UiTheme.fallback.copyWith(name: 'default', radius: 10));
      UiThemes.loader = UiProject(dir.path).loadTheme;
      expect((await UiThemes.load(themePath)).radius, 10);
      session.openTheme(themePath);
      final doc = session.theme.value!;
      doc.change(doc.theme.value.copyWith(radius: 30), 'Corner');
      expect(UiThemes.cached(themePath)!.radius, 30, reason: 'shown at once');

      // Discarded: the Theme tab let go of with the change unsaved.
      session.openTheme(themePath);
      await Future<void>.delayed(Duration.zero);

      expect((await UiThemes.load(themePath)).radius, 10);
    });

    test('but saved ones are kept', () async {
      writeTheme(UiTheme.fallback.copyWith(name: 'default', radius: 10));
      UiThemes.loader = UiProject(dir.path).loadTheme;
      session.openTheme(themePath);
      final doc = session.theme.value!;
      doc.change(doc.theme.value.copyWith(radius: 30), 'Corner');
      expect(session.saveTheme(), isTrue);

      session.openTheme(themePath);

      expect(UiThemes.cached(themePath)!.radius, 30);
    });
  });
}
