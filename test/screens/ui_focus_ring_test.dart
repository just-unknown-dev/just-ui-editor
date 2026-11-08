// The ring round whatever holds the focus: drawn in the theme's primary
// colour, outside the control, on every kind of control a screen makes, so
// a player walking a menu with a pad can see where they are.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  const ringColor = Color(0xFFE5484D);
  const theme = UiTheme(palette: UiPalette(primary: ringColor), radius: 6);

  /// A 400×300 canvas holding [controls], each 160×48, one under the
  /// other, 80 apart down the middle; the first takes the focus.
  World screenOf(List<(String, Component)> controls) {
    final world = uiWorld(engineContext);
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(
        designSize: const Size(400, 300),
        safeArea: false,
        initialFocus: controls.first.$1,
      ),
    ], name: 'Menu');
    for (var i = 0; i < controls.length; i++) {
      final (name, control) = controls[i];
      addUnder(world, canvas, [
        control,
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          anchor: UiAnchor.topCenter,
          pivot: const Offset(0.5, 0),
          offset: Offset(0, 40.0 + i * 80),
          size: const Size(160, 48),
        ),
      ], name: name);
    }
    return world;
  }

  final boundary = GlobalKey();

  Future<void> show(WidgetTester tester, World world) async {
    tester.view
      ..physicalSize = const Size(400, 300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: UiLayer(world: world, themeOverride: theme),
        ),
      ),
    );
    await tester.pump();
  }

  /// The colour drawn at [at], in the layer's own pixels.
  Future<Color> pixelAt(WidgetTester tester, Offset at) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!;
    });
    final i = (at.dy.floor() * 400 + at.dx.floor()) * 4;
    return Color.fromARGB(
      bytes!.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  }

  /// Where the ring round the control called [name] runs: half way across
  /// it, just left of the control's slot.
  Offset ringOf(String name) {
    final i = int.parse(name.substring(name.length - 1));
    // The slot's left edge is (400 - 160) / 2; the ring is 3 clear of it
    // and 3 thick.
    return Offset(120 - 4.5, 40.0 + i * 80 + 24);
  }

  testWidgets('the focused button is ringed; the others are not', (
    tester,
  ) async {
    await show(
      tester,
      screenOf([
        ('Button0', UiButtonComponent(label: 'Play')),
        ('Button1', UiButtonComponent(label: 'Quit')),
      ]),
    );

    expect(await pixelAt(tester, ringOf('Button0')), ringColor);
    expect(await pixelAt(tester, ringOf('Button1')), isNot(ringColor));

    // Walked down, the ring goes with the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(await pixelAt(tester, ringOf('Button0')), isNot(ringColor));
    expect(await pixelAt(tester, ringOf('Button1')), ringColor);
  });

  testWidgets('a button filled with the ring\'s own colour still shows it', (
    tester,
  ) async {
    await show(
      tester,
      screenOf([
        ('Button0', UiButtonComponent(label: 'Play', colorRole: 'primary')),
      ]),
    );
    final edge = ringOf('Button0');

    // The ring, then the gap between it and the button, then the button.
    expect(await pixelAt(tester, edge), ringColor);
    expect(await pixelAt(tester, edge + const Offset(3, 0)), isNot(ringColor));
  });

  for (final (kind, control) in <(String, Component Function())>[
    ('toggle', () => UiToggleComponent(label: 'Music')),
    ('slider', () => UiSliderComponent(value: 0.5)),
    ('text field', () => UiTextFieldComponent(hint: 'Name')),
    ('dropdown', () => UiDropdownComponent(options: const ['Easy', 'Hard'])),
  ]) {
    testWidgets('a focused $kind is ringed the same way', (tester) async {
      await show(
        tester,
        screenOf([('Control0', control()), ('Control1', control())]),
      );

      expect(await pixelAt(tester, ringOf('Control0')), ringColor);
      expect(await pixelAt(tester, ringOf('Control1')), isNot(ringColor));
    });
  }
}
