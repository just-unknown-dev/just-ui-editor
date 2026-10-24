/// Lets a gamepad — or anything that is not a keyboard — work the scene's
/// menus through input actions.
library;

import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, PhysicalKeyboardKey;
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
///
/// A direction is given to whatever has focus first, as the arrow key
/// would be — so a slider slides — and moves focus when that does nothing
/// with it. In a text field it moves focus straight away: a pad cannot
/// type, and must not be stuck there.
final class UiInputBridge {
  UiInputBridge({
    required this.input,
    required this.layer,
    this.actions = const UiInputActions(),
    this.takesPad,
  }) {
    _subscription = input.listenUpdates(_afterUpdate);
  }

  final InputService input;

  /// The UI layer, when there is one on screen.
  final UiLayerState? Function() layer;

  final UiInputActions actions;

  /// Whether the open screens take the pad now. Null: whenever a screen is
  /// open. A game's view says so only while the game is paused or the
  /// screen on top is modal — a banner over live play leaves the stick to
  /// the player.
  final bool Function(UiLayerState ui)? takesPad;

  late final InputSubscription _subscription;
  TraversalDirection? _held;
  double _nextRepeat = 0;

  void _afterUpdate(double now) {
    if (input.isSuspended) return;
    final ui = layer();
    // No screen open: this is play, and the stick is moving a character,
    // not a menu's focus.
    if (ui == null || ui.navigator.isEmpty || !(takesPad?.call(ui) ?? true)) {
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

  static void _move(TraversalDirection direction) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    final typing =
        focus.context?.findAncestorStateOfType<EditableTextState>() != null;
    if (!typing && _offer(focus, direction)) return;
    focus.focusInDirection(direction);
  }

  /// Gives [direction] to the focused widget and those around it as the
  /// arrow key, the way a key press travels; true when one of them took
  /// it — a slider moving, a menu moving its own focus.
  static bool _offer(FocusNode focus, TraversalDirection direction) {
    final (logical, physical) = switch (direction) {
      TraversalDirection.up => (
        LogicalKeyboardKey.arrowUp,
        PhysicalKeyboardKey.arrowUp,
      ),
      TraversalDirection.down => (
        LogicalKeyboardKey.arrowDown,
        PhysicalKeyboardKey.arrowDown,
      ),
      TraversalDirection.left => (
        LogicalKeyboardKey.arrowLeft,
        PhysicalKeyboardKey.arrowLeft,
      ),
      TraversalDirection.right => (
        LogicalKeyboardKey.arrowRight,
        PhysicalKeyboardKey.arrowRight,
      ),
    };
    final key = KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );
    for (FocusNode? node = focus; node != null; node = node.parent) {
      final result = node.onKeyEvent?.call(node, key);
      if (result == KeyEventResult.handled) return true;
      if (result == KeyEventResult.skipRemainingHandlers) return false;
    }
    return false;
  }

  void dispose() => _subscription.cancel();
}
