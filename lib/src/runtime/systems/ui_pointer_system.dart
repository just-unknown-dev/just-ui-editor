/// Pressing the UI that lives in the world.
///
/// World-space buttons were drawn but never pressed: nothing hit-tested
/// them, and what they did was a closure no scene could hold. This turns a
/// pointer into hover, press and release, and a release inside a button
/// into its [UiActionList].
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../logic/ui_actions.dart';
import 'package:just_game_engine/just_game_engine.dart';
import '../components/button_component.dart';
import '../theme/ui_world_style.dart';

/// Where the pointer is, in world units, and whether it is down.
///
/// The engine's input is screen-space and per-platform; whoever owns the
/// camera converts and hands the result here, which keeps this system
/// testable without a window.
class UiPointer {
  const UiPointer({this.position, this.isDown = false, this.ray});

  static const UiPointer away = UiPointer();

  /// Null when the pointer is off the game — a touch that has lifted, a
  /// mouse outside the window.
  final Offset? position;
  final bool isDown;

  /// The camera's ray through the pointer, when the camera is in space (not
  /// a plain 2-D one): a button is then hit where the ray crosses its own
  /// depth, not the world plane. Null for a 2-D camera, whose [position]
  /// is right at every depth.
  final Ray3? ray;
}

class UiPointerSystem extends System {
  UiPointerSystem({this.onSound});

  /// Plays a UI sound by path — hover and press, from the theme.
  void Function(String path)? onSound;

  /// Sounds to make when a button is first hovered or pressed. Empty takes
  /// the theme's ([UiWorldStyle.resolvedTheme]'s `sounds`).
  String hoverSound = '';
  String pressSound = '';

  /// Where the pointer is now, in world units. Set by the game or the
  /// editor whenever it moves — or, to follow a camera that moves under a
  /// still pointer, every frame.
  ///
  /// Each time it goes down or comes up is kept until the next [update],
  /// so a tap that starts and ends between two frames still presses.
  UiPointer get pointer => _pointer;
  set pointer(UiPointer next) {
    if (next.isDown != _pointer.isDown && next.position != null) {
      _edges.add(next);
    } else if (!next.isDown && _pointer.isDown) {
      // Lifted off the game: a release that lands on nothing.
      _edges.add(const UiPointer());
    }
    // A world that is not being updated keeps only the latest few.
    if (_edges.length > 8) _edges.removeAt(0);
    _pointer = next;
  }

  /// Forgets the presses and releases not yet acted on — what a view does
  /// while the game is paused, so a click on a menu does not press a
  /// button in the world when the game resumes.
  void discardPending() => _edges.clear();

  UiPointer _pointer = UiPointer.away;

  /// Presses and releases since the last [update], in order.
  final List<UiPointer> _edges = [];

  /// The button being held, so a release only counts on the one it began
  /// on — dragging off a button and letting go must not press it.
  Entity? _pressing;
  Entity? _hovering;
  final Vector3 _crossing = Vector3.zero();

  // After gameplay, before rendering: a press this frame shows this frame.
  @override
  int get priority => SystemPriorities.gameplay - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, ButtonComponent];

  /// The button under [point], topmost first — a button on a higher layer
  /// takes the press. With a [ray], each button is tried where the ray
  /// crosses its depth.
  ///
  /// The point is taken into the button's own space first — its turn and
  /// its scale — so a button is pressed where it is drawn.
  Entity? buttonAt(Offset point, {Ray3? ray}) {
    Entity? best;
    var bestLayer = -1 << 30;
    forEach((entity) {
      final button = entity.getComponent<ButtonComponent>()!;
      if (!button.isInteractive) return;
      final transform = entity.getComponent<TransformComponent>()!;
      final at = transform.position;
      var here = point;
      if (ray != null) {
        final t = ray.intersectZ(at.z);
        if (t == null) return;
        ray.atInto(t, _crossing);
        here = Offset(_crossing.x, _crossing.y);
      }
      final local = _toLocal(here, transform);
      if (local == null || !button.containsPoint(local, Offset.zero)) return;
      if (button.layer >= bestLayer) {
        bestLayer = button.layer;
        best = entity;
      }
    });
    return best;
  }

  /// [point] in the button's own space: its position taken off, its turn
  /// undone, its scale divided out — the inverse of how it is painted.
  /// Null for a button scaled flat, which nothing can hit.
  static Offset? _toLocal(Offset point, TransformComponent transform) {
    final dx = point.dx - transform.position.x;
    final dy = point.dy - transform.position.y;
    final angle = transform.angle;
    var x = dx, y = dy;
    if (angle != 0) {
      final c = math.cos(-angle), s = math.sin(-angle);
      x = dx * c - dy * s;
      y = dx * s + dy * c;
    }
    final sx = transform.scale.x, sy = transform.scale.y;
    if (sx == 0 || sy == 0) return null;
    return Offset(x / sx, y / sy);
  }

  @override
  void update(double deltaTime) {
    // Every button starts the frame as it will stay unless the pointer says
    // otherwise, so a button left behind by a pointer does not stick.
    var anyLive = false;
    forEach((entity) {
      anyLive = true;
      final button = entity.getComponent<ButtonComponent>()!;
      button.wasPressed = false;
      if (!button.isInteractive) {
        button.state = UiInteractionState.disabled;
      } else if (button.state == UiInteractionState.disabled) {
        button.state = UiInteractionState.normal;
      }
    });
    if (_pressing != null && !world.isEntityAlive(_pressing!)) _pressing = null;
    if (_hovering != null && !world.isEntityAlive(_hovering!)) {
      _hovering = null;
    }
    if (!anyLive) {
      _edges.clear();
      _pressing = null;
      _hovering = null;
      return;
    }

    final sounds = UiWorldStyle.of(world.context).resolvedTheme.sounds;
    final press = pressSound.isNotEmpty ? pressSound : sounds.press;
    final hover = hoverSound.isNotEmpty ? hoverSound : sounds.hover;

    // Every press and release since the last frame, in the order they came.
    for (final edge in _edges) {
      final at = edge.position;
      final under = at == null ? null : buttonAt(at, ray: edge.ray);
      if (edge.isDown) {
        _pressing = under;
        if (under != null && press.isNotEmpty) onSound?.call(press);
      } else {
        final held = _pressing;
        _pressing = null;
        // Only a release on the button it began on counts.
        if (held != null && identical(held, under)) {
          held.getComponent<ButtonComponent>()?.press(
            UiActionContext(world: world, entity: held),
          );
        }
      }
    }
    _edges.clear();

    final at = _pointer.position;
    if (at == null) {
      _clear(_hovering);
      _clear(_pressing);
      _hovering = null;
      _pressing = null;
      return;
    }

    final under = buttonAt(at, ray: _pointer.ray);
    if (!identical(under, _hovering)) {
      _clear(_hovering);
      _hovering = under;
      if (under != null && !_pointer.isDown && hover.isNotEmpty) {
        onSound?.call(hover);
      }
    }

    // What each button shows: pressed beats hovered.
    final held = _pressing;
    if (held != null) {
      final button = held.getComponent<ButtonComponent>();
      if (button != null && button.isInteractive) {
        button.state = identical(held, under)
            ? UiInteractionState.pressed
            : UiInteractionState.normal;
      }
    }
    if (under != null && !identical(under, held)) {
      final button = under.getComponent<ButtonComponent>();
      if (button != null && button.isInteractive) {
        button.state = _pointer.isDown && held != null
            ? UiInteractionState.normal
            : UiInteractionState.hovered;
      }
    }
  }

  void _clear(Entity? entity) {
    final button = entity?.getComponent<ButtonComponent>();
    if (button != null && button.isInteractive) {
      button.state = UiInteractionState.normal;
    }
  }
}
