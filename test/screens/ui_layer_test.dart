// Screen-space UI: entities in a scene become real Flutter widgets, a game
// puts its own widgets among them, and a frame that changes one thing
// rebuilds one thing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import '../support/ui_test_support.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'dart:convert';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  /// A canvas with [children] under it, as the scene loader would leave it.
  Entity canvasWith(
    World world,
    List<List<Component>> children, {
    UiCanvasComponent? canvas,
  }) {
    final root = world.createEntityWithComponents([
      canvas ?? UiCanvasComponent(designSize: const Size(400, 300)),
      ChildrenComponent(),
    ], name: 'Hud');
    for (var i = 0; i < children.length; i++) {
      final child = world.createEntityWithComponents([
        ...children[i],
        ParentComponent(parentId: root.id),
      ], name: 'Child$i');
      root.getComponent<ChildrenComponent>()!.addChild(child.id);
    }
    return root;
  }

  /// Puts [world]'s UI on a 400×300 screen and hands back the layer, so a
  /// test can drive it the way the game loop does.
  Future<UiLayerState> showUi(WidgetTester tester, World world) async {
    final key = GlobalKey<UiLayerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: UiLayer(key: key, world: world),
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  group('a screen in the scene', () {
    testWidgets('a world with no editor shows its HUD', (tester) async {
      UiBindings.of(engineContext).register('coins', () => 7);
      final world = uiWorld(engineContext);
      canvasWith(world, [
        [
          UiTextComponent(text: 'Coins: {coins}'),
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.topLeft,
            offset: const Offset(16, 16),
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Coins: 7', findRichText: true), findsOneWidget);
    });

    testWidgets('nothing on screen when every canvas is hidden', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      canvasWith(world, [
        [UiTextComponent(text: 'Hidden')],
      ], canvas: UiCanvasComponent(visible: false));

      await showUi(tester, world);

      expect(find.text('Hidden', findRichText: true), findsNothing);
    });

    testWidgets('a canvas appearing later is picked up by sync', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final layer = await showUi(tester, world);
      expect(find.text('Later', findRichText: true), findsNothing);

      canvasWith(world, [
        [UiTextComponent(text: 'Later')],
      ]);
      layer.sync();
      await tester.pump();

      expect(find.text('Later', findRichText: true), findsOneWidget);
    });

    testWidgets('a row lays its children out in the order the scene holds '
        'them', (tester) async {
      final world = uiWorld(engineContext);
      final root = world.createEntityWithComponents([
        UiCanvasComponent(designSize: const Size(400, 300)),
        ChildrenComponent(),
      ], name: 'Hud');
      final row = world.createEntityWithComponents([
        UiLayoutComponent(kind: UiLayoutKind.row, spacing: 8),
        ParentComponent(parentId: root.id),
        ChildrenComponent(),
      ], name: 'Row');
      root.getComponent<ChildrenComponent>()!.addChild(row.id);
      for (final word in ['one', 'two', 'three']) {
        final child = world.createEntityWithComponents([
          UiTextComponent(text: word),
          ParentComponent(parentId: row.id),
        ], name: word);
        row.getComponent<ChildrenComponent>()!.addChild(child.id);
      }

      await showUi(tester, world);

      final xs = [
        for (final word in ['one', 'two', 'three'])
          tester.getTopLeft(find.text(word, findRichText: true)).dx,
      ];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
    });
  });

  group('widgets a game brings', () {
    testWidgets('a registered widget is built with its props', (tester) async {
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [
            UiWidgetProp('caption', 'Caption', UiPropKind.text),
            UiWidgetProp(
              'count',
              'Count',
              UiPropKind.number,
              defaultValue: '1',
            ),
          ],
          build: (context) => Text(
            '${context.text('caption')} ×${context.number('count')!.toInt()}',
          ),
        ),
      );

      final world = uiWorld(engineContext);
      canvasWith(world, [
        [
          UiCustomComponent(
            widgetId: 'badge',
            props: {'caption': 'Keys', 'count': '3'},
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Keys ×3'), findsOneWidget);
    });

    testWidgets('a prop the scene left out falls back to the default', (
      tester,
    ) async {
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [
            UiWidgetProp(
              'count',
              'Count',
              UiPropKind.number,
              defaultValue: '9',
            ),
          ],
          build: (context) => Text('count=${context.props['count']}'),
        ),
      );

      final world = uiWorld(engineContext);
      canvasWith(world, [
        [UiCustomComponent(widgetId: 'badge')],
      ]);

      await showUi(tester, world);

      expect(find.text('count=9'), findsOneWidget);
    });

    testWidgets('a widget this game does not have leaves a gap, not a crash', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      canvasWith(world, [
        [UiCustomComponent(widgetId: 'nothing_registered')],
      ]);

      await showUi(tester, world);

      expect(tester.takeException(), isNull);
    });

    testWidgets('a prop reads a binding', (tester) async {
      UiBindings.of(engineContext).register('lives', () => 2);
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'badge',
          label: 'Badge',
          props: const [UiWidgetProp('caption', 'Caption', UiPropKind.text)],
          build: (context) => Text(context.text('caption')),
        ),
      );

      final world = uiWorld(engineContext);
      canvasWith(world, [
        [
          UiCustomComponent(
            widgetId: 'badge',
            props: {'caption': 'Lives: {lives}'},
          ),
        ],
      ]);

      await showUi(tester, world);

      expect(find.text('Lives: 2'), findsOneWidget);
    });
  });

  group('rebuilding', () {
    /// A widget that counts how often it was built, registered under [id].
    int builds = 0;

    setUp(() {
      builds = 0;
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'counter',
          label: 'Counter',
          props: const [UiWidgetProp('note', 'Note', UiPropKind.text)],
          build: (context) {
            builds++;
            return Text('note=${context.props['note']}');
          },
        ),
      );
    });

    testWidgets('one field change rebuilds one node', (tester) async {
      final world = uiWorld(engineContext);
      final canvas = canvasWith(world, [
        [UiTextComponent(text: 'first'), UiSlotComponent()],
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final textEntity = world.getEntity(
        canvas.getComponent<ChildrenComponent>()!.childIds.first,
      )!;
      final after = builds;

      // A neighbour changes: the counter must not be built again.
      textEntity.getComponent<UiTextComponent>()!.text = 'second';
      layer.sync();
      await tester.pump();

      expect(find.text('second', findRichText: true), findsOneWidget);
      expect(builds, after, reason: 'a sibling changed, not this node');
    });

    testWidgets('a node is rebuilt when its own field changes', (tester) async {
      final world = uiWorld(engineContext);
      final canvas = canvasWith(world, [
        [UiTextComponent(text: 'first')],
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final custom = world
          .getEntity(canvas.getComponent<ChildrenComponent>()!.childIds.last)!
          .getComponent<UiCustomComponent>()!;
      final after = builds;

      custom.props['note'] = 'b';
      layer.sync();
      await tester.pump();

      expect(builds, after + 1);
      expect(find.text('note=b'), findsOneWidget);
    });

    testWidgets('a frame that changes nothing rebuilds nothing', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      canvasWith(world, [
        [
          UiCustomComponent(widgetId: 'counter', props: {'note': 'a'}),
        ],
      ]);
      final layer = await showUi(tester, world);
      final after = builds;

      for (var i = 0; i < 5; i++) {
        layer.sync();
        await tester.pump();
      }

      expect(builds, after);
    });

    testWidgets('a binding reading a new number redraws the text', (
      tester,
    ) async {
      var coins = 1;
      UiBindings.of(engineContext).register('coins', () => coins);
      final world = uiWorld(engineContext);
      canvasWith(world, [
        [UiTextComponent(text: '{coins}')],
      ]);
      final layer = await showUi(tester, world);
      expect(find.text('1', findRichText: true), findsOneWidget);

      // Nothing was edited: only the game moved on.
      coins = 2;
      layer.sync();
      await tester.pump();

      expect(find.text('2', findRichText: true), findsOneWidget);
    });
  });

  group("walking the tree only when the world's shape changed", () {
    testWidgets('a still screen is walked once, and again only as its shape '
        'changes', (tester) async {
      final world = uiWorld(engineContext);
      world.addSystem(UiTextSystem());
      final canvas = canvasWith(world, [
        [UiTextComponent(text: 'first'), UiSlotComponent()],
        [UiTextComponent(text: 'second'), UiSlotComponent()],
      ]);
      final layer = await showUi(tester, world);
      layer.sync();
      final walked = layer.walks;
      for (var i = 0; i < 5; i++) {
        world.update(1 / 60);
        layer.sync();
        await tester.pump();
      }
      expect(layer.walks, walked, reason: 'nothing changed shape');

      // Made under the canvas: walked, and shown.
      final third = world.createEntityWithComponents([
        UiTextComponent(text: 'third'),
        UiSlotComponent(),
        ParentComponent(parentId: canvas.id),
      ]);
      layer.sync();
      await tester.pump();
      expect(layer.walks, walked + 1);
      expect(find.text('third', findRichText: true), findsOneWidget);

      // Switched off, then on: gone, then back.
      third.isActive = false;
      layer.sync();
      await tester.pump();
      expect(find.text('third', findRichText: true), findsNothing);
      third.isActive = true;
      layer.sync();
      await tester.pump();
      expect(find.text('third', findRichText: true), findsOneWidget);

      // Destroyed.
      world.destroyEntity(third);
      layer.sync();
      await tester.pump();
      expect(find.text('third', findRichText: true), findsNothing);
      expect(layer.walks, walked + 4);
    });

    testWidgets('a node moved to another parent, or another place, is drawn '
        'there', (tester) async {
      final world = uiWorld(engineContext);
      final canvas = canvasWith(world, [
        [
          UiLayoutComponent(kind: UiLayoutKind.column),
          UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch),
        ],
      ]);
      final column = world.getEntity(
        canvas.getComponent<ChildrenComponent>()!.childIds.single,
      )!;
      final a = addUnder(world, column, [
        UiTextComponent(text: 'A'),
        UiSlotComponent(),
      ]);
      final b = addUnder(world, column, [
        UiTextComponent(text: 'B'),
        UiSlotComponent(),
      ]);
      final layer = await showUi(tester, world);
      layer.sync();
      await tester.pump();
      double y(String words) =>
          tester.getTopLeft(find.text(words, findRichText: true)).dy;
      expect(y('A'), lessThan(y('B')));

      // Reordered in place, as an editor does, then settled.
      column.getComponent<ChildrenComponent>()!.childIds
        ..remove(b.id)
        ..insert(0, b.id);
      world.transformHierarchy.adopt(b);
      layer.sync();
      await tester.pump();
      expect(y('B'), lessThan(y('A')), reason: 'the new order is drawn');

      // Re-parented by its link, onto the canvas itself.
      a.getComponent<ParentComponent>()!.parentId = canvas.id;
      layer.sync();
      await tester.pump();
      expect(find.text('A', findRichText: true), findsOneWidget);
      expect(
        column.getComponent<ChildrenComponent>()!.childIds,
        isNot(contains(a.id)),
      );
    });

    testWidgets('field edits show without a walk: a text, a slot, a canvas', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final canvas = canvasWith(world, [
        [UiTextComponent(text: 'first'), UiSlotComponent()],
      ]);
      final text = world
          .getEntity(canvas.getComponent<ChildrenComponent>()!.childIds.single)!
          .getComponent<UiTextComponent>()!;
      final slot = world
          .getEntity(canvas.getComponent<ChildrenComponent>()!.childIds.single)!
          .getComponent<UiSlotComponent>()!;
      final layer = await showUi(tester, world);
      layer.sync();
      final walked = layer.walks;

      text.text = 'edited';
      layer.sync();
      await tester.pump();
      expect(find.text('edited', findRichText: true), findsOneWidget);

      slot.visible = false;
      layer.sync();
      await tester.pump();
      expect(find.text('edited', findRichText: true), findsNothing);
      slot.visible = true;
      layer.sync();
      await tester.pump();
      expect(find.text('edited', findRichText: true), findsOneWidget);
      expect(layer.walks, walked, reason: 'fields, not shape');

      // A canvas hidden is no longer drawn: its visibility decides the walk.
      canvas.getComponent<UiCanvasComponent>()!.visible = false;
      layer.sync();
      await tester.pump();
      expect(find.text('edited', findRichText: true), findsNothing);
      expect(layer.walks, greaterThan(walked));
    });

    testWidgets('a binding read anew shows at a sync, though the text system '
        'has not ticked since', (tester) async {
      var coins = 0;
      UiBindings.of(engineContext).register('coins', () => coins);
      final world = uiWorld(engineContext);
      world.addSystem(UiTextSystem());
      canvasWith(world, [
        [UiTextComponent(text: '{coins} coins')],
      ]);
      world.update(1 / 60);
      final layer = await showUi(tester, world);
      layer.sync();
      await tester.pump();
      expect(find.text('0 coins', findRichText: true), findsOneWidget);

      // The game moved on, and its loop syncs before the world ticks again
      // (a paused game, a preview, a test).
      coins = 3;
      layer.sync();
      await tester.pump();
      expect(find.text('3 coins', findRichText: true), findsOneWidget);

      // And with the world ticking first, as a game loop does.
      coins = 4;
      world.update(1 / 60);
      layer.sync();
      await tester.pump();
      expect(find.text('4 coins', findRichText: true), findsOneWidget);
    });

    testWidgets('right after the text system ticks, its text is reused', (
      tester,
    ) async {
      var reads = 0;
      UiBindings.of(engineContext).register('n', () {
        reads++;
        return 7;
      });
      final world = uiWorld(engineContext);
      world.addSystem(UiTextSystem());
      canvasWith(world, [
        [UiTextComponent(text: '{n}')],
      ]);
      final layer = await showUi(tester, world);
      world.update(1 / 60);
      layer.sync();
      await tester.pump();

      final before = reads;
      world.update(1 / 60);
      layer.sync();
      expect(reads, before + 1, reason: "the system's read, not the layer's");
      layer.sync();
      expect(reads, before + 2, reason: 'no tick since: read again');
    });
  });

  group('the canvas scaler', () {
    test('fit keeps the whole design on screen, at three sizes', () {
      const design = Size(800, 600);
      expect(UiScaleMode.fit.scaleFor(design, const Size(800, 600)), 1);
      expect(UiScaleMode.fit.scaleFor(design, const Size(400, 600)), 0.5);
      expect(UiScaleMode.fit.scaleFor(design, const Size(1600, 600)), 1);
      expect(UiScaleMode.none.scaleFor(design, const Size(400, 300)), 1);
      expect(UiScaleMode.width.scaleFor(design, const Size(400, 900)), 0.5);
      expect(UiScaleMode.height.scaleFor(design, const Size(400, 300)), 0.5);
    });

    testWidgets('a HUD drawn for a big screen is scaled down to a small one', (
      tester,
    ) async {
      // A widget that fills its slot exactly, so what is measured is where
      // the scaler put the slot and nothing else.
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (context) => const SizedBox.expand(key: ValueKey('probe')),
        ),
      );
      final world = uiWorld(engineContext);
      canvasWith(
        world,
        [
          [
            UiCustomComponent(widgetId: 'probe'),
            UiSlotComponent(
              mode: UiSlotMode.anchored,
              anchor: UiAnchor.topLeft,
              pivot: Offset.zero,
              offset: const Offset(100, 100),
              size: const Size(80, 20),
            ),
          ],
        ],
        // Twice the 400×300 the test screen is.
        canvas: UiCanvasComponent(
          designSize: const Size(800, 600),
          safeArea: false,
        ),
      );

      await showUi(tester, world);

      // 100 design pixels in, on a screen at half scale: 50 real pixels,
      // and an 80×20 slot comes out 40×10.
      final box = tester.getTopLeft(find.byType(UiLayer));
      final probe = find.byKey(const ValueKey('probe'));
      expect(tester.getTopLeft(probe) - box, const Offset(50, 50));
      // On screen, not in the widget's own coordinates — the scale lives
      // in a Transform above it, so `getSize` would still say 80×20.
      expect(
        tester.getBottomRight(probe) - tester.getTopLeft(probe),
        const Offset(40, 10),
      );
    });
  });

  group('the system behind it', () {
    test('a text that types itself out advances with the world', () {
      final world = uiWorld(engineContext);
      registerUiSystems(world);
      final text = UiTextComponent(text: 'Hello', revealSpeed: 10);
      world.createEntityWithComponents([text], name: 'Line');

      world.update(0.2);

      expect(text.revealed, closeTo(2, 0.001));
    });

    test('the layer is told when a binding reads something new', () {
      var coins = 0;
      UiBindings.of(engineContext).register('coins', () => coins);
      final world = uiWorld(engineContext);
      final system = UiTextSystem();
      world.addSystem(system);
      var told = 0;
      system.onChanged = () => told++;
      world.createEntityWithComponents([
        UiTextComponent(text: '{coins}'),
      ], name: 'Coins');

      world.update(1 / 60);
      final afterFirst = told;
      world.update(1 / 60);
      expect(told, afterFirst, reason: 'nothing changed');

      coins = 5;
      world.update(1 / 60);
      expect(told, afterFirst + 1);
    });
  });

  group('what a scene file means by a parent', () {
    /// A scene the way a hand-written file — or a generator — leaves it:
    /// the child names its parent and carries nothing else about it.
    Map<String, dynamic> sceneJson() => {
      'version': SceneFormat.current,
      'name': 'level_test',
      'entities': [
        {
          'name': 'Hud',
          'parentName': null,
          'components': [
            {
              'type': 'UiCanvasComponent',
              'fields': {'designW': 400.0, 'designH': 300.0},
            },
          ],
        },
        {
          'name': 'Label',
          'parentName': 'Hud',
          'components': [
            {
              'type': 'UiTextComponent',
              'fields': {'textValue': 'Coins'},
            },
          ],
        },
      ],
    };

    test('an entity the file switches off starts switched off', () {
      final world = uiWorld(engineContext)..initialize();
      addTearDown(world.dispose);
      final json = sceneJson();
      (json['entities'] as List)[1]['enabled'] = false;

      SceneLoader.load(world, json);

      final label = world.findEntityByName('Label')!;
      // In the world and part of the scene; the systems pass it by.
      expect(label.isAlive, isTrue);
      expect(label.isActive, isFalse);
      // And saying nothing about it means on.
      expect(world.findEntityByName('Hud')!.isActive, isTrue);
    });

    test('the child is linked both ways, whatever the file listed', () {
      final world = uiWorld(engineContext)..initialize();
      addTearDown(world.dispose);

      SceneLoader.load(world, sceneJson());

      final hud = world.findEntityByName('Hud')!;
      final label = world.findEntityByName('Label')!;
      // Down: the parent holds it…
      expect(hud.getComponent<ChildrenComponent>()!.childIds, [label.id]);
      // …and up, which is what tells everything else it is not a root.
      expect(label.getComponent<ParentComponent>()?.parentId, hud.id);
    });

    test('and the link survives being saved again', () {
      final world = uiWorld(engineContext)..initialize();
      addTearDown(world.dispose);
      SceneLoader.load(world, sceneJson());

      // What a save writes is read back from `ParentComponent`; without
      // one the hierarchy was lost on the way out.
      final label = world.findEntityByName('Label')!;
      final parentId = label.getComponent<ParentComponent>()!.parentId;
      expect(world.getEntity(parentId!)!.name, 'Hud');
    });

    testWidgets('a child with no ParentComponent still draws in place', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      addTearDown(world.dispose);
      SceneLoader.load(world, sceneJson());

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 400, height: 300, child: UiLayer(world: world)),
        ),
      );

      expect(find.text('Coins', findRichText: true), findsOneWidget);
    });
  });

  group('a label in the current language', () {
    testWidgets('on a button, a toggle and a field', (tester) async {
      String tr(String key) => switch (key) {
        'menu.resume' => 'Resume',
        'menu.music' => 'Music',
        'menu.name' => 'Your name',
        _ => key,
      };
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      final column = addUnder(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column),
        fillSlot(),
      ]);
      addUnder(world, column, [
        UiButtonComponent(label: '@menu.resume'),
        UiSlotComponent(),
      ]);
      addUnder(world, column, [
        UiToggleComponent(label: '@menu.music'),
        UiSlotComponent(size: const Size(200, 40)),
      ]);
      addUnder(world, column, [
        UiTextFieldComponent(hint: '@menu.name'),
        UiSlotComponent(size: const Size(200, 48)),
      ]);

      await showLayer(tester, world, localize: tr);

      expect(find.text('Resume', findRichText: true), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.textContaining('@menu'), findsNothing);
    });
  });

  group('text on a screen', () {
    testWidgets('that moves is painted, and moves on its own', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiTextComponent(text: '[wave]Wavy[/wave]'),
        fillSlot(),
      ]);

      await showLayer(tester, world);

      expect(find.text('Wavy', findRichText: true), findsNothing);
      expect(paintedText('Wavy'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it ticks');
    });

    testWidgets('that shrinks, or has an outline, is painted too', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiTextComponent(text: 'Fits', overflow: UiTextOverflow.shrink),
        fillSlot(),
      ]);
      addUnder(world, hud, [
        UiTextComponent(
          text: 'Edged',
          style: const UiTextStyle(outline: UiTextOutline()),
        ),
        fillSlot(),
      ]);

      await showLayer(tester, world);

      expect(paintedText('Fits'), findsOneWidget);
      expect(paintedText('Edged'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an icon is drawn in the line', (tester) async {
      UiIcons.of(engineContext).register('heart', Icons.favorite);
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiTextComponent(text: 'Lives [icon=heart]'),
        fillSlot(),
      ]);

      await showLayer(tester, world);

      final glyph = String.fromCharCode(Icons.favorite.codePoint);
      expect(find.text('Lives $glyph', findRichText: true), findsOneWidget);
    });

    testWidgets('a link runs its action when tapped', (tester) async {
      final ran = <String>[];
      UiActions.of(engineContext).register('shop', (_) => ran.add('shop'));
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiTextComponent(text: '[link=shop]Shop[/link]'),
        fillSlot(),
      ]);

      await showLayer(tester, world);
      await tester.tap(find.text('Shop', findRichText: true));
      await tester.pump();

      expect(ran, ['shop']);
    });

    test('a link names a built-in with its argument, or the game\'s own', () {
      expect(UiActions.linkAction('shop'), const UiAction('custom:shop'));
      expect(
        UiActions.linkAction('ui.push Credits'),
        const UiAction('ui.push', 'Credits'),
      );
    });

    test('a colour that changes is a change, though the words are not', () {
      final red = UiRichText.parse('[color=red]Go[/color]');
      final green = UiRichText.parse('[color=green]Go[/color]');

      expect(red.sameAs(green), isFalse);
      expect(red.sameAs(UiRichText.parse('[color=red]Go[/color]')), isTrue);
    });

    test('letters that move wrap as still text does', () {
      final painter = UiTextPainter()
        ..set(
          text: UiRichText.parse('[wave]one two three four five[/wave]'),
          style: const UiTextStyle(size: 16),
          layout: const UiTextLayout(maxWidth: 60),
        );
      addTearDown(painter.dispose);
      final recorder = ui.PictureRecorder();

      painter.paint(
        Canvas(recorder),
        const Offset(100, 100),
        animation: const UiTextAnimation(seconds: 1),
      );
      recorder.endRecording().dispose();

      expect(painter.size.height, greaterThan(16 * 2));
    });
  });

  group('typing in a screen', () {
    testWidgets('the arrows move the caret, not the focus', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      final column = addUnder(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column),
        fillSlot(),
      ]);
      addUnder(world, column, [
        UiTextFieldComponent(),
        UiSlotComponent(size: const Size(200, 48)),
      ]);
      addUnder(world, column, [
        UiButtonComponent(label: 'Next'),
        UiSlotComponent(),
      ]);

      await showLayer(tester, world);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.selection.baseOffset, 2);
      expect(field.focusNode.hasFocus, isTrue);
    });
  });

  group('what a screen is given that does not fit', () {
    testWidgets('a slider the wrong way round', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiSliderComponent(value: 3, min: 10, max: 0),
        UiSlotComponent(size: const Size(300, 40)),
      ]);

      await showLayer(tester, world);

      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect((slider.min, slider.max, slider.value), (0, 10, 3));
    });

    testWidgets('a share of the room where there is none to share', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      final wrap = addUnder(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.wrap),
        fillSlot(),
      ]);
      addUnder(world, wrap, [
        UiTextComponent(text: 'Grows'),
        UiSlotComponent(flex: 1),
      ]);
      addUnder(world, wrap, [
        UiSpacerComponent(expand: true),
        UiSlotComponent(),
      ]);

      await showLayer(tester, world);

      expect(tester.takeException(), isNull);
      expect(find.byType(Expanded), findsNothing);
    });

    testWidgets('a choice given twice', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiDropdownComponent(value: 'Easy', options: ['Easy', 'Hard', 'Easy']),
        UiSlotComponent(size: const Size(200, 48)),
      ]);

      await showLayer(tester, world);

      expect(tester.takeException(), isNull);
    });

    testWidgets('no room at all', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [UiTextComponent(text: 'Hi'), fillSlot()]);

      await showLayer(tester, world, size: Size.zero);

      expect(
        tester.takeException(),
        isNull,
        reason: 'nothing to scale to: nothing drawn',
      );
    });
  });

  group('a slot changed on its own', () {
    // A timeline sliding a panel in, or code growing a bar: only the
    // child's slot changes, and nothing else tells the layer to rebuild.
    testWidgets('moves and sizes what it places, at the next sync', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.topLeft,
        pivot: Offset.zero,
        offset: const Offset(10, 10),
        size: const Size(100, 40),
      );
      addUnder(world, hud, [UiPanelComponent(), slot], name: 'Card');
      final key = await showLayer(tester, world);
      final card = find.byType(DecoratedBox).last;
      final before = tester.getRect(card);

      slot
        ..offset = const Offset(110, 60)
        ..size = const Size(150, 50);
      key.currentState!.sync();
      await tester.pump();

      final after = tester.getRect(card);
      expect(after.topLeft - before.topLeft, const Offset(100, 50));
      expect(after.size, const Size(150, 50));
    });

    testWidgets('resizes what a column lays out', (tester) async {
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      final column = addUnder(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column, tight: true),
        fillSlot(),
      ]);
      final slot = UiSlotComponent(size: const Size(100, 40));
      addUnder(world, column, [UiPanelComponent(), slot]);
      final key = await showLayer(tester, world);
      final bar = find.byType(DecoratedBox).last;
      expect(tester.getSize(bar), const Size(100, 40));

      slot.size = const Size(220, 60);
      key.currentState!.sync();
      await tester.pump();

      expect(tester.getSize(bar), const Size(220, 60));
    });
  });

  group('the system\'s back', () {
    testWidgets('closes the screen on top, not the game', (tester) async {
      final world = uiWorld(engineContext);
      final pause = addCanvas(world, 'Pause', isScreen: true, modal: true);
      addUnder(world, pause, [UiTextComponent(text: 'Paused'), fillSlot()]);

      final key = await showLayer(tester, world, handlesBack: true);
      await tester.pump();
      expect(key.currentState!.navigator.isEmpty, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump();
      key.currentState!.sync();
      await tester.pump();

      expect(key.currentState!.navigator.isEmpty, isTrue);
      expect(find.byType(UiLayer), findsOneWidget, reason: 'still there');
    });

    testWidgets('leaves a screen that does not close on Back, in the game', (
      tester,
    ) async {
      final world = uiWorld(engineContext);
      final done = addCanvas(world, 'Complete', isScreen: true, modal: true);
      done.getComponent<UiCanvasComponent>()!.closesOnBack = false;
      addUnder(world, done, [UiTextComponent(text: 'Well done'), fillSlot()]);

      final key = await showLayer(tester, world, handlesBack: true);
      await tester.pump();

      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      key.currentState!.sync();
      await tester.pump();

      expect(handled, isTrue, reason: 'the app was not left either');
      expect(key.currentState!.navigator.top?.name, 'Complete');
      expect(find.text('Well done', findRichText: true), findsOneWidget);
    });
  });

  group('placing, routing and theming', () {
    Entity make(World world, String name, List<Component> components) =>
        world.createEntityWithComponents(components, name: name);
    Entity canvas(World world, {bool isScreen = false, bool modal = false}) =>
        make(world, 'Canvas', [
          UiCanvasComponent(
            designSize: const Size(400, 300),
            scaleMode: UiScaleMode.none,
            isScreen: isScreen,
            modal: modal,
            visible: !isScreen,
          ),
        ]);

    /// The layer on a 400×300 screen, with each entity's node findable.
    Future<(UiLayerState, UiNodeBoxes)> show(
      WidgetTester tester,
      World world,
    ) async {
      final key = GlobalKey<UiLayerState>();
      final nodes = UiNodeBoxes();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: UiLayer(key: key, world: world, nodes: nodes),
            ),
          ),
        ),
      );
      return (key.currentState!, nodes);
    }

    Rect rectOf(WidgetTester tester, UiNodeBoxes nodes, Entity e) {
      final box = nodes[e.id]!;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    UiSlotComponent centred() => UiSlotComponent(
      mode: UiSlotMode.anchored,
      anchor: UiAnchor.center,
      size: const Size(100, 50),
    );

    testWidgets('a child sits by the same rule in a canvas and in a stack', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      final root = canvas(world);
      final onCanvas = make(world, 'OnCanvas', [
        UiTextComponent(text: 'a'),
        centred(),
      ]);
      final stack = make(world, 'Stack', [
        UiLayoutComponent(kind: UiLayoutKind.stack),
        UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch),
      ]);
      final inStack = make(world, 'InStack', [
        UiTextComponent(text: 'b'),
        centred(),
      ]);
      UiDocument.link(onCanvas, root);
      UiDocument.link(stack, root);
      UiDocument.link(inStack, stack);

      final (_, nodes) = await show(tester, world);

      // Pivot and all: centred on the same point, the same size.
      expect(rectOf(tester, nodes, inStack), rectOf(tester, nodes, onCanvas));
      expect(
        rectOf(tester, nodes, onCanvas),
        const Rect.fromLTWH(150, 125, 100, 50),
      );
    });

    testWidgets('a hidden element takes no room and cannot be found', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      final root = canvas(world);
      final slot = centred()..visible = false;
      final hint = make(world, 'Hint', [UiTextComponent(text: 'hint'), slot]);
      UiDocument.link(hint, root);

      final (layer, nodes) = await show(tester, world);
      expect(nodes[hint.id], isNull);

      // Shown again with nothing but the flag: the layer notices by itself.
      slot.visible = true;
      layer.sync();
      await tester.pump();
      expect(rectOf(tester, nodes, hint).size, const Size(100, 50));
    });

    testWidgets('the canvas itself is findable: its whole design area', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      final root = canvas(world);

      final (_, nodes) = await show(tester, world);

      expect(rectOf(tester, nodes, root), const Rect.fromLTWH(0, 0, 400, 300));
    });

    testWidgets(
      'kept to the safe area, a canvas is scaled the same both ways',
      (tester) async {
        final world = uiWorld(engineContext)..initialize();
        final root = make(world, 'Hud', [
          UiCanvasComponent(designSize: const Size(1920, 1080)),
        ]);
        final element = make(world, 'Box', [
          UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.center,
            size: const Size(400, 400),
          ),
        ]);
        UiDocument.link(element, root);
        final nodes = UiNodeBoxes();
        // A phone on its side: the notch on the left and right, a bar below.
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 852,
                height: 393,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(852, 393),
                    padding: EdgeInsets.fromLTRB(59, 0, 59, 21),
                  ),
                  child: UiLayer(world: world, nodes: nodes),
                ),
              ),
            ),
          ),
        );

        // As drawn, scaled: not the design-pixel box.
        Rect shown(Entity e) {
          final box = nodes[e.id]!;
          return MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          );
        }

        final box = shown(element);
        expect(
          box.width,
          closeTo(box.height, 0.01),
          reason: 'a square stays one',
        );
        final canvasRect = shown(root);
        expect(canvasRect.left, 59);
        expect(canvasRect.bottom, closeTo(393 - 21, 0.01));
      },
    );

    testWidgets('alignSelf moves one child across a column', (tester) async {
      final world = uiWorld(engineContext)..initialize();
      final root = canvas(world);
      final column = make(world, 'Column', [
        UiLayoutComponent(kind: UiLayoutKind.column),
        UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch),
      ]);
      final left = make(world, 'Left', [
        UiSpacerComponent(size: 20),
        UiSlotComponent(alignSelf: 'start'),
      ]);
      final middle = make(world, 'Middle', [
        UiSpacerComponent(size: 20),
        UiSlotComponent(),
      ]);
      UiDocument.link(column, root);
      UiDocument.link(left, column);
      UiDocument.link(middle, column);

      final (_, nodes) = await show(tester, world);

      expect(rectOf(tester, nodes, middle).center.dx, 200);
      expect(rectOf(tester, nodes, left).left, 0);
    });

    testWidgets('screens fly Heroes: their navigator has a controller', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      final screen = canvas(world, isScreen: true);
      screen.getComponent<UiCanvasComponent>()!.visible = true;

      await show(tester, world);

      final navigator = tester.element(find.byType(Navigator).last);
      expect(HeroControllerScope.maybeOf(navigator), isNotNull);
    });

    testWidgets('making an open screen modal takes effect at once', (
      tester,
    ) async {
      final world = uiWorld(engineContext)..initialize();
      final screen = canvas(world, isScreen: true);
      final settings = screen.getComponent<UiCanvasComponent>()!
        ..visible = true;
      final (layer, _) = await show(tester, world);
      await tester.pumpAndSettle();
      final barriers = find.byType(ModalBarrier).evaluate().length;

      settings.modal = true;
      layer.sync();
      await tester.pumpAndSettle();

      expect(
        find.byType(ModalBarrier).evaluate().length,
        greaterThan(barriers),
        reason: 'the new route gates the pointer',
      );
    });

    testWidgets(
      'a screen opened again while it closes is built twice, safely',
      (tester) async {
        final world = uiWorld(engineContext)..initialize();
        final screen = make(world, 'Pause', [
          // Scaled, so the canvas sits in a FittedBox, as in the editor.
          UiCanvasComponent(designSize: const Size(800, 600), isScreen: true),
        ]);
        final settings = screen.getComponent<UiCanvasComponent>()!;
        final (layer, nodes) = await show(tester, world);
        await tester.pumpAndSettle();

        // Closed, and opened again before its fade out has finished: the
        // navigator holds the leaving route and a new one, both building it.
        settings.visible = false;
        layer.sync();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        settings.visible = true;
        layer.sync();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        // Still findable, where it is drawn: the design scaled to the screen.
        final box = nodes[screen.id]!;
        expect(
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
          const Rect.fromLTWH(0, 0, 400, 300),
        );
      },
    );

    testWidgets('a theme a canvas names is read when it is first drawn', (
      tester,
    ) async {
      UiThemes.of(engineContext).loader = (path) async => UiTheme(
        name: path,
        palette: const UiPalette(primary: Color(0xFF00FF00)),
      );
      final world = uiWorld(engineContext)..initialize();
      final root = canvas(world);
      root.getComponent<UiCanvasComponent>()!.theme =
          'assets/ui/green.uitheme.json';

      await show(tester, world);
      await tester.pump();

      expect(
        UiThemes.of(engineContext).cached('assets/ui/green.uitheme.json'),
        isNotNull,
      );
    });
  });

  group('what a layer is given', () {
    testWidgets('another world: it shows that one, not the first', (
      tester,
    ) async {
      World screen(String words) {
        final world = uiWorld();
        final hud = addCanvas(world, 'Hud');
        addUnder(world, hud, [UiTextComponent(text: words), fillSlot()]);
        return world;
      }

      final first = screen('From the first');
      final second = screen('From the second');
      final key = GlobalKey<UiLayerState>();
      Widget layer(World world) => MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: UiLayer(key: key, world: world),
        ),
      );

      await tester.pumpWidget(layer(first));
      expect(find.text('From the first', findRichText: true), findsOneWidget);

      await tester.pumpWidget(layer(second));
      await tester.pump();

      expect(find.text('From the second', findRichText: true), findsOneWidget);
      expect(find.text('From the first', findRichText: true), findsNothing);
      expect(key.currentState!.navigator.world, same(second));
    });

    testWidgets('nine-slice set on a panel that shows a picture keeps it', (
      tester,
    ) async {
      final world = uiWorld();
      final hud = addCanvas(world, 'Hud');
      final panel = UiPanelComponent(image: 'panel.png');
      addUnder(world, hud, [panel, fillSlot()]);
      final key = GlobalKey<UiLayerState>();
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: _PictureBundle(),
          child: MaterialApp(
            home: SizedBox(
              width: 400,
              height: 300,
              child: UiLayer(key: key, world: world),
            ),
          ),
        ),
      );
      bool pictured() => find
          .byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration?)?.image != null,
          )
          .evaluate()
          .isNotEmpty;
      expect(pictured(), isTrue, reason: 'stretched, before any slices');

      panel.nineSlice = const EdgeInsets.all(8);
      key.currentState!
        ..markDirty()
        ..sync();
      await tester.pump();
      // The picture's size is read before it can be sliced.
      for (var i = 0; i < 20 && !pictured(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(pictured(), isTrue, reason: 'sliced, not gone');
    });
  });
}

/// A bundle holding one picture, `panel.png`: a white 1×1 PNG.
class _PictureBundle extends CachingAssetBundle {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
  );

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        'panel.png': [
          {'asset': 'panel.png'},
        ],
      })!;
    }
    return ByteData.sublistView(_png);
  }
}
