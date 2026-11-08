// A world-space button seen through a camera in space: the pointer's ray
// crosses the button's own depth, which is where it must hit.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import '../support/ui_test_support.dart';
import 'package:flutter/services.dart';

void main() {
  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );
  late World world;
  late UiPointerSystem pointer;
  late Entity entity;

  setUp(() {
    world = uiWorld(engineContext);
    pointer = UiPointerSystem();
    world.addSystem(pointer);
    entity = world.createEntityWithComponents([
      // 10 units into the scene, off to the right.
      TransformComponent(position: Vector3(10, 0, 10)),
      UiButtonComponent(label: 'Play', size: const Size(4, 4)),
    ], name: 'PlayButton');
  });
  tearDown(() => world.dispose());

  test('a ray finds a button at its own depth', () {
    final camera = OutputCamera(
      viewportSize: const Size(100, 100),
      z: -10,
      lens: const CameraLens.perspective(fieldOfView: math.pi / 2),
    );
    // The button's centre is 20 ahead and 10 right: a quarter of the way
    // from the middle of a 90° view towards its right edge.
    const screen = Offset(75, 50);
    final ray = camera.screenToWorldRay(screen);
    pointer.pointer = UiPointer(
      position: camera.screenToWorld(screen),
      ray: ray,
    );
    expect(pointer.buttonAt(camera.screenToWorld(screen), ray: ray), entity);
    // On the world plane z = 0 the same pixel is 5 right: a miss there.
    expect(pointer.buttonAt(camera.screenToWorld(screen)), isNull);
  });

  test('a 2-D pointer (no ray) hits as it always has', () {
    expect(pointer.buttonAt(const Offset(10, 0)), entity);
    expect(pointer.buttonAt(const Offset(30, 0)), isNull);
  });

  group('a world button', () {
    late World world;
    late UiPointerSystem system;
    late UiButtonComponent button;
    late TransformComponent transform;
    late List<String> sounds;
    late List<String> pressed;

    setUp(() {
      sounds = [];
      pressed = [];
      UiActions.of(engineContext).register('hit', (_) => pressed.add('hit'));
      world = uiWorld(engineContext);
      system = UiPointerSystem(onSound: sounds.add);
      world.addSystem(system);
      transform = TransformComponent(position: Vector3(100, 100, 0));
      button = UiButtonComponent(
        size: const Size(40, 20),
        onPressed: const UiActionList([UiAction('custom:hit')]),
      );
      world.createEntityWithComponents([transform, button], name: 'B');
    });

    void at(double x, double y, {bool down = false}) =>
        system.pointer = UiPointer(position: Offset(x, y), isDown: down);

    test('is pressed where it is drawn, scaled', () {
      transform.scale.setValues(2, 2, 1);

      at(135, 100);
      world.update(1 / 60);

      expect(button.state, UiInteractionState.hovered);
    });

    test('is pressed where it is drawn, turned', () {
      transform.angle = math.pi / 2;

      at(100, 118); // past its height unturned, inside its width turned
      world.update(1 / 60);
      expect(button.state, UiInteractionState.hovered);

      at(118, 100); // inside unturned, outside turned
      world.update(1 / 60);
      expect(button.state, UiInteractionState.normal);
    });

    test('a tap between two frames still presses it', () {
      at(100, 100, down: true);
      at(100, 100);
      world.update(1 / 60);

      expect(pressed, ['hit']);
    });

    test('presses made while the world waits can be let go', () {
      at(100, 100, down: true);
      at(100, 100);
      system.discardPending();
      world.update(1 / 60);

      expect(pressed, isEmpty);
    });

    test('sounds as the theme says', () {
      UiWorldStyle.of(world.context).theme = const UiTheme(
        sounds: UiSounds(hover: 'over.wav', press: 'down.wav'),
      );

      at(100, 100);
      world.update(1 / 60);
      at(100, 100, down: true);
      world.update(1 / 60);

      expect(sounds, ['over.wav', 'down.wav']);
    });
  });
}
