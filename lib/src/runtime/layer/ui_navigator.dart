/// Which screens are open, and in what order.
///
/// A canvas marked `isScreen` is a page: opened over what is already
/// there, closed to go back. A canvas that is not one is a layer that
/// stays — a HUD under everything.
///
/// The scene stays the source of truth: opening a screen sets its
/// `visible`, so what the editor shows and what the game shows are the
/// same thing, and a scene saved with a menu open opens with it open.
library;

import 'package:just_game_engine/just_game_engine.dart';
import '../logic/ui_actions.dart';
import '../components/screen/ui_canvas_component.dart';
import '../components/screen/ui_slot_component.dart';

class UiNavigator {
  UiNavigator(this.world);

  final World world;

  /// The names of the open screens, oldest first. Names rather than
  /// entities, so a scene reloading under it does not leave it holding
  /// entities that have gone.
  final List<String> _stack = [];

  /// The open screens, bottom first.
  List<Entity> get stack => [for (final name in _stack) ?_screen(name)];

  /// What is on top, or null when only the layers are showing.
  Entity? get top {
    for (var i = _stack.length - 1; i >= 0; i--) {
      final screen = _screen(_stack[i]);
      if (screen != null) return screen;
    }
    return null;
  }

  bool get isEmpty => top == null;

  /// Opens [name] over whatever is already open.
  ///
  /// A canvas that is not a screen — a layer, like a HUD — is not stacked:
  /// it is simply shown, as [show] would.
  void push(String name) {
    final entity = _screen(name);
    if (entity == null) return;
    final canvas = entity.getComponent<UiCanvasComponent>()!;
    if (!canvas.isScreen) {
      canvas
        ..visible = true
        ..markDirty();
      return;
    }
    _stack.remove(name);
    _stack.add(name);
    canvas
      ..visible = true
      ..markDirty();
  }

  /// Closes the screen on top. Does nothing when there is none — a back
  /// press with nothing to go back to is the game's business, not the
  /// interface's.
  void back() {
    if (_stack.isEmpty) return;
    final name = _stack.removeLast();
    _screen(name)?.getComponent<UiCanvasComponent>()
      ?..visible = false
      ..markDirty();
  }

  /// Closes every screen, leaving the layers.
  void popToRoot() {
    while (_stack.isNotEmpty) {
      back();
    }
  }

  /// Shows, hides or flips any UI entity by name: a screen goes through
  /// the stack, a layer simply appears.
  ///
  /// A name that is no canvas's is an element's. Two screens may each hold
  /// one by that name; the one in the screen on top wins, then the open
  /// layers from the highest down, then any.
  ///
  /// [visible] null flips it.
  void show(String name, bool? visible) {
    final entity = _screen(name);
    if (entity == null) {
      // Not a canvas: a single element inside one.
      final slot = _element(name)?.getComponent<UiSlotComponent>();
      if (slot != null) slot.visible = visible ?? !slot.visible;
      return;
    }
    final canvas = entity.getComponent<UiCanvasComponent>()!;
    final wanted = visible ?? !canvas.visible;
    if (canvas.isScreen) {
      if (wanted) {
        push(name);
      } else if (_stack.contains(name)) {
        _stack.remove(name);
        canvas
          ..visible = false
          ..markDirty();
      }
      return;
    }
    canvas
      ..visible = wanted
      ..markDirty();
  }

  /// Picks up screens a scene was saved with open, so the stack and the
  /// scene agree from the first frame.
  ///
  /// The stack is kept in [UiCanvasComponent.sortOrder] order — a screen
  /// that asks to be higher stays over one opened after it — and, among
  /// screens of one order, in the order they were opened.
  void adopt() {
    for (final entity in world.query(const [UiCanvasComponent])) {
      final canvas = entity.getComponent<UiCanvasComponent>()!;
      final name = entity.name;
      if (!canvas.isScreen || !canvas.visible || name == null) continue;
      if (!_stack.contains(name)) _stack.add(name);
    }
    // A screen that was closed from elsewhere leaves the stack.
    _stack.removeWhere((name) {
      final canvas = _screen(name)?.getComponent<UiCanvasComponent>();
      return canvas == null || !canvas.isScreen || !canvas.visible;
    });
    if (_stack.length < 2) return;
    // A stable sort: List.sort is not one past a few dozen entries.
    final order = {
      for (var i = 0; i < _stack.length; i++)
        _stack[i]: (
          _screen(_stack[i])?.getComponent<UiCanvasComponent>()?.sortOrder ?? 0,
          i,
        ),
    };
    _stack.sort((a, b) {
      final (orderA, indexA) = order[a]!;
      final (orderB, indexB) = order[b]!;
      final byOrder = orderA.compareTo(orderB);
      return byOrder != 0 ? byOrder : indexA.compareTo(indexB);
    });
  }

  /// What `ui.push`, `ui.back` and `ui.show` reach when the game has not
  /// offered its own. Whatever the game *did* set is left alone.
  UiActionHost fillingIn(UiActionHost host) => UiActionHost(
    loadScene: host.loadScene,
    pause: host.pause,
    resume: host.resume,
    quit: host.quit,
    playSound: host.playSound,
    showUi: host.showUi ?? show,
    pushScreen: host.pushScreen ?? push,
    back: host.back ?? back,
  );

  /// The canvas called [name] — only a canvas: an element that happens to
  /// share a screen's name never stands in for it.
  Entity? _screen(String name) {
    final named = world.findEntityByName(name);
    if (named != null &&
        named.isActive &&
        named.getComponent<UiCanvasComponent>() != null) {
      return named;
    }
    if (named == null) return null;
    for (final entity in world.query(const [UiCanvasComponent])) {
      if (entity.name == name && entity.isActive) return entity;
    }
    return null;
  }

  /// The element called [name], from the screen on top down.
  Entity? _element(String name) {
    final candidates = [
      for (final entity in world.query(const [UiSlotComponent]))
        if (entity.name == name) entity,
    ];
    if (candidates.length < 2) return candidates.firstOrNull;
    final ranked = [
      ...stack.reversed,
      ...[
        for (final entity in world.query(const [UiCanvasComponent]))
          if (!entity.getComponent<UiCanvasComponent>()!.isScreen &&
              entity.getComponent<UiCanvasComponent>()!.visible)
            entity,
      ]..sort(
        (a, b) => b.getComponent<UiCanvasComponent>()!.sortOrder.compareTo(
          a.getComponent<UiCanvasComponent>()!.sortOrder,
        ),
      ),
    ];
    for (final canvas in ranked) {
      for (final entity in candidates) {
        if (identical(canvasAbove(world, entity), canvas)) return entity;
      }
    }
    return candidates.first;
  }

  /// The canvas [entity] is drawn in: the nearest ancestor (or itself)
  /// that carries a [UiCanvasComponent]. Null for something under none.
  static Entity? canvasAbove(World world, Entity entity) {
    Entity? current = entity;
    // A UI tree deeper than this is a mistake, not a use case.
    for (var step = 0; step < 64 && current != null; step++) {
      if (current.getComponent<UiCanvasComponent>() != null) return current;
      final parent = current.getComponent<ParentComponent>()?.parentId;
      current = parent == null ? null : world.getEntity(parent);
    }
    return null;
  }

  @override
  String toString() => 'UiNavigator($_stack)';
}
