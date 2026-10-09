// A world-space button seen through a camera in space: the pointer's ray
// crosses the button's own depth, which is where it must hit.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  late World world;
  late UiPointerSystem pointer;
  late Entity entity;

  setUp(() {
    world = _uiWorld();
    pointer = UiPointerSystem();
    world.addSystem(pointer);
    entity = world.createEntityWithComponents([
      // 10 units into the scene, off to the right.
      TransformComponent(position: Vector3(10, 0, 10)),
      ButtonComponent(label: 'Play', size: const Size(4, 4)),
    ], name: 'PlayButton');
  });
  tearDown(() => world.dispose());

  test('a ray finds a button at its own depth', () {
    final camera = Camera(
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
}
