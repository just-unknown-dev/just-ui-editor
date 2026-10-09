/// Lets a gamepad — or anything that is not a keyboard — work the scene's
/// menus through input actions.
library;

import 'package:flutter/widgets.dart';
import 'package:just_inputs/just_inputs.dart';

import 'ui_layer.dart';

/// The actions that drive menus: a vector to move focus, a button to press
/// the focused widget, a button to go back.
final class UiInputActions {
  const UiInputActions({
    this.navigate = 'ui/navigate',
    this.submit = 'ui/submit',
    this.cancel = 'ui/cancel',
    this.repeatDelay = 0.35,
    this.repeatInterval = 0.1,
  });

  final String navigate;
  final String submit;
  final String cancel;

  /// Holding a direction moves once, waits this long, then moves every
  /// [repeatInterval] — seconds on the input clock.
  final double repeatDelay;
  final double repeatInterval;
}

/// Moves focus, presses and goes back in the scene's UI from [input]'s
/// actions, while a screen is open.
///
/// A keyboard is left out: the UI's own shortcuts already walk it with the
/// arrows, Enter and Escape, and a key handled twice would move twice. So
/// is the mouse, which points. What is left is a pad's d-pad, stick and
/// buttons — and whatever else a game binds.
///
/// Runs after every input update, paused or not, and stands aside while a
/// rebind is listening.
final class UiInputBridge {
  UiInputBridge({
    required this.input,
    required this.layer,
    this.actions = const UiInputActions(),
  }) {
    _subscription = input.listenUpdates(_afterUpdate);
  }

  final InputService input;

  /// The UI layer, when there is one on screen.
  final UiLayerState? Function() layer;

  final UiInputActions actions;

  late final InputSubscription _subscription;
  TraversalDirection? _held;
  double _nextRepeat = 0;

  void _afterUpdate(double now) {
    if (input.isSuspended) return;
    final ui = layer();
    // No screen open: this is play, and the stick is moving a character,
    // not a menu's focus.
    if (ui == null || ui.navigator.isEmpty) {
      _held = null;
      return;
    }
    final shared = input.actions;

    final navigate = shared.tryAction(actions.navigate);
    final direction = navigate != null && _notKeyboard(navigate)
        ? _direction(navigate.readVector2())
        : null;
    if (direction == null) {
      _held = null;
    } else if (direction != _held) {
      _held = direction;
      _nextRepeat = now + actions.repeatDelay;
      _move(direction);
    } else if (now >= _nextRepeat) {
      _nextRepeat = now + actions.repeatInterval;
      _move(direction);
    }

    final submit = shared.tryAction(actions.submit);
    if (submit != null &&
        submit.wasPressedThisFrame() &&
        _notKeyboard(submit)) {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context != null) Actions.maybeInvoke(context, const ActivateIntent());
    }

    final cancel = shared.tryAction(actions.cancel);
    if (cancel != null &&
        cancel.wasPressedThisFrame() &&
        _notKeyboard(cancel)) {
      ui.navigator.back();
      ui.markDirty();
    }
  }

  static bool _notKeyboard(InputAction action) {
    final layout = action.activeDevice?.layout;
    return layout != null &&
        layout != InputLayouts.keyboard &&
        layout != InputLayouts.mouse;
  }

  /// The stick's main direction, once it is pushed past half way.
  static TraversalDirection? _direction(Offset v) {
    if (v.distance < 0.5) return null;
    if (v.dx.abs() > v.dy.abs()) {
      return v.dx > 0 ? TraversalDirection.right : TraversalDirection.left;
    }
    return v.dy > 0 ? TraversalDirection.down : TraversalDirection.up;
  }

  static void _move(TraversalDirection direction) =>
      FocusManager.instance.primaryFocus?.focusInDirection(direction);

  void dispose() => _subscription.cancel();
}
