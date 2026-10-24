// The inspector rows the Interface module brings — for screens and for the
// text and buttons a level holds itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import 'package:just_ui_editor/src/editor/inspector/ui_field_editors.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  setUp(() {
    UiBindings.clear();
    UiWidgets.clear();
  });
  tearDown(() {
    UiBindings.clear();
    UiWidgets.clear();
  });

  /// One row on its own, at inspector width.
  Future<void> pumpRow(WidgetTester tester, Widget row) async {
    tester.view
      ..physicalSize = const Size(360, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(8), child: row),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the anchor grid', () {
    testWidgets('a preset sets both corners', (tester) async {
      UiAnchor? chosen;
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.topLeft,
          onChanged: (a) => chosen = a,
        ),
      );

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pump();
      await tester.tap(find.byTooltip('bottomRight'));
      await tester.pump();

      expect(chosen, UiAnchor.bottomRight);
      expect(chosen!.min, const Offset(1, 1));
      expect(chosen!.max, const Offset(1, 1));
    });

    testWidgets('a stretch is one of the choices', (tester) async {
      UiAnchor? chosen;
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.topLeft,
          onChanged: (a) => chosen = a,
        ),
      );
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pump();

      await tester.tap(find.text('The whole parent'));
      await tester.pump();

      expect(chosen, UiAnchor.stretch);
      expect(chosen!.stretchesX, isTrue);
      expect(chosen!.stretchesY, isTrue);
    });

    testWidgets('the row says which preset it is on — or that it is none', (
      tester,
    ) async {
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.centerRight,
          onChanged: (_) {},
        ),
      );
      expect(find.text('centerRight'), findsOneWidget);

      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: const UiAnchor(Offset(0.3, 0.7), Offset(0.3, 0.7)),
          onChanged: (_) {},
        ),
      );
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('open, it fits at inspector width', (tester) async {
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.stretch,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('the text row', () {
    testWidgets('a tag button writes the markup at the caret', (tester) async {
      var written = '';
      await pumpRow(
        tester,
        UiTextEditorRow(
          label: 'Text',
          value: 'Go',
          onChanged: (v) => written = v,
        ),
      );
      await tester.tap(find.text('Text'));
      await tester.pump();

      await tester.tap(find.text('B'));
      await tester.pump();

      expect(written, 'Go[b][/b]');
    });

    testWidgets('what the game reads is offered, and the rest is flagged', (
      tester,
    ) async {
      var written = '';
      await pumpRow(
        tester,
        UiTextEditorRow(
          label: 'Text',
          value: 'Coins: {gems}',
          bindings: const ['coins', 'time'],
          onChanged: (v) => written = v,
        ),
      );

      expect(
        find.textContaining('Nothing in the game reads {gems}'),
        findsOneWidget,
      );

      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.tap(find.text('{coins}'));
      await tester.pump();

      expect(written, contains('{coins}'));
    });

    testWidgets('a text beginning @ says it is a key', (tester) async {
      await pumpRow(
        tester,
        UiTextEditorRow(label: 'Text', value: '@hud.coins', onChanged: (_) {}),
      );

      expect(find.textContaining('hud.coins'), findsWidgets);
      expect(find.textContaining('current language'), findsOneWidget);
    });

    testWidgets('a label column as wide as every other row', (tester) async {
      await pumpRow(
        tester,
        UiTextEditorRow(label: 'Text', value: 'Hi', onChanged: (_) {}),
      );

      final field = tester.getRect(find.byType(TextField));
      expect(field.left, closeTo(8 + InspectorField.labelWidth, 1));
    });
  });

  group('in the inspector, through the module', () {
    late EditorScope scope;

    setUp(() {
      scope = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        world: _uiWorld()..initialize(),
        modules: [UiEditorModule()],
      );
      addTearDown(scope.dispose);
    });

    Future<void> pumpSections(WidgetTester tester, Entity entity) async {
      tester.view
        ..physicalSize = const Size(360, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a slot shows its anchor as a grid', (tester) async {
      final entity = scope.world.createEntityWithComponents([
        UiSlotComponent(mode: UiSlotMode.anchored),
      ], name: 'Badge');

      await pumpSections(tester, entity);

      expect(find.byType(UiAnchorEditorRow), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Its value sits where every other row's does: the Mode dropdown's.
      expect(
        tester.getTopLeft(find.text('topLeft')).dx,
        tester.getTopLeft(find.text('anchored')).dx,
      );
    });

    testWidgets('world-space text keeps its rows in a level', (tester) async {
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(),
        TextComponent(text: 'Welcome'),
      ], name: 'Sign');

      await pumpSections(tester, entity);

      expect(find.byType(UiTextEditorRow), findsOneWidget);
      expect(find.byType(UiTextStyleEditorRow), findsOneWidget);
    });

    testWidgets('a custom widget offers the properties it said it takes', (
      tester,
    ) async {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'inventory_grid',
          label: 'Inventory',
          props: const [
            UiWidgetProp(
              'columns',
              'Columns',
              UiPropKind.number,
              defaultValue: '4',
            ),
            UiWidgetProp('title', 'Title', UiPropKind.text),
          ],
          build: (context) => const SizedBox.shrink(),
        ),
      );
      final entity = scope.world.createEntityWithComponents([
        UiCustomComponent(widgetId: 'inventory_grid'),
      ], name: 'Bag');

      await pumpSections(tester, entity);

      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      // Chosen from what was registered.
      expect(find.text('inventory_grid'), findsWidgets);
    });

    testWidgets('a canvas offers no Visible box that would not be saved', (
      tester,
    ) async {
      final entity = scope.world.createEntityWithComponents([
        UiCanvasComponent(),
      ], name: 'Hud');

      await pumpSections(tester, entity);

      expect(find.text('Showing'), findsOneWidget);
      expect(find.textContaining('in Screens starts it open'), findsOneWidget);
    });

    testWidgets('align self offers the words the layout knows', (tester) async {
      final slot = UiSlotComponent();
      final entity = scope.world.createEntityWithComponents([
        slot,
      ], name: 'Item');

      await pumpSections(tester, entity);

      expect(find.text('as the parent lays it'), findsOneWidget);
      await tester.tap(find.text('as the parent lays it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('stretch').last);
      await tester.pumpAndSettle();
      expect(slot.alignSelf, 'stretch');
    });

    testWidgets('a folded canvas says what it is at a glance', (tester) async {
      final entity = scope.world.createEntityWithComponents([
        UiCanvasComponent(isScreen: true),
      ], name: 'Pause');

      scope.chrome.toggleCollapsed('UiCanvasComponent');
      await pumpSections(tester, entity);

      // Folded away, its header still says what it is.
      expect(find.textContaining('screen, 1920×1080'), findsOneWidget);
    });

    testWidgets('a role a file left empty reads as the default, not primary', (
      tester,
    ) async {
      final entity = scope.world.createEntityWithComponents([
        UiPanelComponent(colorRole: ''),
        UiSlotComponent(),
      ], name: 'Card');

      await pumpSections(tester, entity);

      expect(find.text('(its default)'), findsOneWidget);
    });

    testWidgets('a gradient is colours to pick, one more at a time', (
      tester,
    ) async {
      final panel = UiPanelComponent(
        gradient: const [Color(0xFF112233), Color(0xFF445566)],
      );
      final entity = scope.world.createEntityWithComponents([
        panel,
        UiSlotComponent(),
      ], name: 'Card');

      await pumpSections(tester, entity);

      final row = find.ancestor(
        of: find.text('Gradient'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row.first, matching: find.byType(MiniColorField)),
        findsNWidgets(2),
      );
      await tester.tap(find.byTooltip('Add a colour'));
      await tester.pump();
      expect(panel.gradient, hasLength(3));
      expect(panel.gradient!.last, const Color(0xFF445566));

      // Built again, as the inspector is after an edit.
      await pumpSections(tester, entity);
      await tester.tap(find.byTooltip('Take this colour out').first);
      await tester.pump();
      expect(panel.gradient, const [Color(0xFF445566), Color(0xFF445566)]);
    });

    testWidgets('a custom widget not chosen yet says so', (tester) async {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'inventory_grid',
          label: 'Inventory',
          build: (context) => const SizedBox.shrink(),
        ),
      );
      final entity = scope.world.createEntityWithComponents([
        UiCustomComponent(),
      ], name: 'Bag');

      await pumpSections(tester, entity);

      expect(find.text('(none chosen)'), findsOneWidget);
    });
  });

  testWidgets('a game action this build has not registered still reads', (
    tester,
  ) async {
    await pumpRow(
      tester,
      UiActionsEditorRow(
        label: 'On press',
        actions: const UiActionList([UiAction('custom:openShop', 'weapons')]),
        onChanged: (_) {},
      ),
    );

    expect(find.text('custom:openShop'), findsOneWidget);
  });
}
