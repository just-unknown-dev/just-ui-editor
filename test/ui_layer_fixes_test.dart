// What the screen layer got wrong, each pinned down: one placement rule
// wherever a child sits, nothing taking room that is not there, the canvas
// findable, alignSelf honoured, Hero flights flying, a route following its
// canvas, themes arriving on their own, and world buttons feeling the
// pointer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    UiActions.clear();
    UiThemes.reset();
  });

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
    final world = _uiWorld()..initialize();
    final root = canvas(world);
    final onCanvas = make(world, 'OnCanvas', [
      TextComponent(text: 'a'),
      centred(),
    ]);
    final stack = make(world, 'Stack', [
      UiLayoutComponent(kind: UiLayoutKind.stack),
      UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch),
    ]);
    final inStack = make(world, 'InStack', [
      TextComponent(text: 'b'),
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
    final world = _uiWorld()..initialize();
    final root = canvas(world);
    final slot = centred()..visible = false;
    final hint = make(world, 'Hint', [TextComponent(text: 'hint'), slot]);
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
    final world = _uiWorld()..initialize();
    final root = canvas(world);

    final (_, nodes) = await show(tester, world);

    expect(rectOf(tester, nodes, root), const Rect.fromLTWH(0, 0, 400, 300));
  });

  testWidgets('kept to the safe area, a canvas is scaled the same both ways', (
    tester,
  ) async {
    final world = _uiWorld()..initialize();
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
    expect(box.width, closeTo(box.height, 0.01), reason: 'a square stays one');
    final canvasRect = shown(root);
    expect(canvasRect.left, 59);
    expect(canvasRect.bottom, closeTo(393 - 21, 0.01));
  });

  testWidgets('alignSelf moves one child across a column', (tester) async {
    final world = _uiWorld()..initialize();
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
    final world = _uiWorld()..initialize();
    final screen = canvas(world, isScreen: true);
    screen.getComponent<UiCanvasComponent>()!.visible = true;

    await show(tester, world);

    final navigator = tester.element(find.byType(Navigator).last);
    expect(HeroControllerScope.maybeOf(navigator), isNotNull);
  });

  testWidgets('making an open screen modal takes effect at once', (
    tester,
  ) async {
    final world = _uiWorld()..initialize();
    final screen = canvas(world, isScreen: true);
    final settings = screen.getComponent<UiCanvasComponent>()!..visible = true;
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

  testWidgets('a screen opened again while it closes is built twice, safely', (
    tester,
  ) async {
    final world = _uiWorld()..initialize();
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
  });

  testWidgets('a theme a canvas names is read when it is first drawn', (
    tester,
  ) async {
    UiThemes.loader = (path) async => UiTheme(
      name: path,
      palette: const UiPalette(primary: Color(0xFF00FF00)),
    );
    final world = _uiWorld()..initialize();
    final root = canvas(world);
    root.getComponent<UiCanvasComponent>()!.theme =
        'assets/ui/green.uitheme.json';

    await show(tester, world);
    await tester.pump();

    expect(UiThemes.cached('assets/ui/green.uitheme.json'), isNotNull);
  });

  test('a changed theme file refreshes what tools preview', () async {
    var colour = const Color(0xFF111111);
    UiThemes.loader = (path) async => UiTheme(
      name: path,
      palette: UiPalette(primary: colour),
    );
    await UiThemes.usePreview('assets/ui/a.uitheme.json');
    expect(UiThemes.preview.palette.primary, const Color(0xFF111111));

    colour = const Color(0xFF222222);
    UiThemes.evict('assets/ui/a.uitheme.json');
    await Future<void>.delayed(Duration.zero);

    expect(UiThemes.preview.palette.primary, const Color(0xFF222222));
  });
}
