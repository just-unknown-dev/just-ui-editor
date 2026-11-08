/// What a button does when it is pressed: the built-ins, and the names a
/// game registers.
///
/// A scene cannot save a Dart closure, so it saves what to do by name — a
/// built-in like "play this timeline", or a name the game has registered:
///
/// ```dart
/// UiActions.of(engine.context)
///     .register('start_game', (context) => game.start());
/// ```
library;

import 'package:just_game_engine/just_game_engine.dart';

import 'ui_action.dart';

/// What one engine's interface can do: the actions its game registered,
/// and where the built-ins reach the game.
///
/// Kept on the engine's [EngineContext] ([of]), not in a static, so a
/// screen's `ui.push` opens a screen of its own engine — never another's,
/// with two installed — and a game's closures go with its engine.
final class UiActions {
  UiActions._();

  static final Object _key = Object();

  /// [context]'s actions, made the first time they are asked for.
  static UiActions of(EngineContext context) => context.slot(_key, UiActions._);

  final Map<String, UiActionHandler> _handlers = {};

  /// What a built-in reaches the game through. A game sets this once, and
  /// need only fill in what it handles itself.
  UiActionHost host = const UiActionHost();

  /// What answers whatever [host] leaves out — the screens, once
  /// `JustGameUi.install` has run, so `ui.push Pause` opens Pause however
  /// much of [host] the game set, and whenever it set it.
  UiActionHost defaults = const UiActionHost();

  /// Makes [name] usable as `custom:name`.
  void register(String name, UiActionHandler handler) =>
      _handlers[name] = handler;

  /// Forgets `custom:name`.
  void unregister(String name) => _handlers.remove(name);

  /// Whether a game registered `custom:name`.
  bool has(String name) => _handlers.containsKey(name);

  /// The names a game has registered, for an editor to offer.
  List<String> get customNames => _handlers.keys.toList()..sort();

  /// Forgets every registered action and both hosts. For a test, or a game
  /// tearing down.
  void clear() {
    _handlers.clear();
    host = const UiActionHost();
    defaults = const UiActionHost();
  }

  /// Every built-in, and what its argument means — an editor reads this to
  /// offer the right picker.
  static const Map<String, String> builtIns = {
    'none': '',
    'signal': 'A timeline signal to emit',
    'timeline.play': 'An entity whose timeline plays',
    'timeline.stop': 'An entity whose timeline stops',
    'scene.load': 'A scene to open',
    'ui.show': 'A UI entity to show',
    'ui.hide': 'A UI entity to hide',
    'ui.toggle': 'A UI entity to show or hide',
    'ui.push': 'A screen to open over this one',
    'ui.back': '',
    'game.pause': '',
    'game.resume': '',
    'game.quit': '',
    'audio.play': 'A sound to play',
  };

  /// What a text's `[link=…]` runs when it is tapped: `[link=shop]` is the
  /// game's `custom:shop`, and a built-in may be named with its argument —
  /// `[link=ui.push Credits]`.
  static UiAction linkAction(String link) {
    final value = link.trim();
    final space = value.indexOf(' ');
    final kind = space < 0 ? value : value.substring(0, space);
    final argument = space < 0 ? '' : value.substring(space + 1).trim();
    final known = builtIns.containsKey(kind) || kind.startsWith('custom:');
    return UiAction(known ? kind : 'custom:$kind', argument);
  }

  /// Does [action]. An action nobody can carry out is quietly nothing —
  /// a button with a missing handler must not take the game down. The
  /// editor's Problems dock is where that is reported instead.
  void run(UiAction action, UiActionContext context) {
    final argument = action.argument.isEmpty
        ? context.argument
        : action.argument;
    final scoped = UiActionContext(
      world: context.world,
      entity: context.entity,
      argument: argument,
      value: context.value,
      gameWorld: context.gameWorld,
      host: context.host,
    );
    final host = (context.host ?? this.host).over(defaults);
    final custom = action.customName;
    if (custom != null) {
      _handlers[custom]?.call(scoped);
      return;
    }
    switch (action.kind) {
      case 'none' || '':
        break;
      case 'signal':
        // The engine's bus, which the screens' world shares with the level.
        scoped.world.context.signals.emit(argument);
      case 'timeline.play':
        _timelineOf(scoped)?.restart();
      case 'timeline.stop':
        _timelineOf(scoped)?.stop();
      case 'scene.load':
        host.loadScene?.call(argument);
      case 'ui.show':
        host.showUi?.call(argument, true);
      case 'ui.hide':
        host.showUi?.call(argument, false);
      case 'ui.toggle':
        host.showUi?.call(argument, null);
      case 'ui.push':
        host.pushScreen?.call(argument);
      case 'ui.back':
        host.back?.call();
      case 'game.pause':
        host.pause?.call();
      case 'game.resume':
        host.resume?.call();
      case 'game.quit':
        host.quit?.call();
      case 'audio.play':
        host.playSound?.call(argument);
      default:
        // An unknown kind: a scene from a newer engine, or a typo.
        break;
    }
  }

  /// The timeline player an action names — in the acting entity's own
  /// screen first (two screens may each hold an entity by that name), then
  /// anywhere in the interface, then the game — or the acting entity's own.
  static TimelinePlayerComponent? _timelineOf(UiActionContext context) {
    final name = context.argument;
    final acting = context.entity;
    if (name.isEmpty) {
      return acting?.getComponent<TimelinePlayerComponent>();
    }
    final named =
        (acting == null
            ? null
            : findBelow(context.world, rootOf(acting), name)) ??
        context.world.findEntityByName(name) ??
        context.gameWorld?.findEntityByName(name);
    return named?.getComponent<TimelinePlayerComponent>();
  }

  /// The top of [entity]'s hierarchy: a screen's canvas, a level's root.
  static Entity rootOf(Entity entity) {
    final world = entity.world;
    var current = entity;
    // A tree deeper than this is a mistake, not a use case.
    for (var step = 0; step < 64 && world != null; step++) {
      final parentId = current.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : world.getEntity(parentId);
      if (parent == null) break;
      current = parent;
    }
    return current;
  }

  /// The first entity called [name] at or below [root], nearest first.
  static Entity? findBelow(World world, Entity root, String name) {
    final queue = [root];
    final seen = <Entity>{root};
    for (var i = 0; i < queue.length; i++) {
      final entity = queue[i];
      if (entity.name == name) return entity;
      final children = entity.getComponent<ChildrenComponent>()?.childIds;
      for (final id in children ?? const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null && seen.add(child)) queue.add(child);
      }
    }
    return null;
  }
}
