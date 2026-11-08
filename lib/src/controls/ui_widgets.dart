/// What a UI entity becomes on screen, and how a game adds its own.
///
/// Every element is built through this registry, built-ins included, so a
/// widget a game writes is placed, saved and edited exactly like one that
/// came with the engine:
///
/// ```dart
/// UiWidgets.of(engine.context).register(UiWidgetDefinition(
///   id: 'inventory_grid',
///   label: 'Inventory',
///   build: (context) => InventoryGrid(columns: context.number('columns') ?? 4),
///   props: [UiWidgetProp('columns', 'Columns', UiPropKind.number)],
/// ));
/// ```
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import '../theme/theme.dart';
import 'ui_custom_component.dart';

/// What kind of value a custom widget's property holds, so the inspector
/// can offer the right control.
enum UiPropKind { text, number, flag, color, asset }

/// One thing a custom widget lets the scene set.
class UiWidgetProp {
  const UiWidgetProp(
    this.name,
    this.label,
    this.kind, {
    this.defaultValue = '',
    this.description = '',
  });

  final String name;
  final String label;
  final UiPropKind kind;
  final String defaultValue;
  final String description;
}

/// What a widget is given when it is built.
class UiBuildContext {
  const UiBuildContext({
    required this.entity,
    required this.world,
    required this.theme,
    required this.children,
    this.props = const {},
    this.localize,
    this.gameWorld,
    this.host,
  });

  /// The entity this widget is.
  final Entity entity;
  final World world;

  /// The game's world, when [world] is the interface's own.
  final World? gameWorld;

  /// Where its actions' `ui.*` and `game.*` go, when not the game's host.
  final UiActionHost? host;

  /// The theme its canvas is drawn with.
  final UiTheme theme;

  /// What the entities under it became.
  final List<Widget> children;

  /// What the scene set on it, for a custom widget.
  final Map<String, String> props;

  /// How a `@key` becomes words.
  final String Function(String key)? localize;

  /// A property as a player reads it: a `@key` in the game's language
  /// ([localize]), with its bindings filled in — as [resolve] reads one.
  String text(String name) => resolve(props[name] ?? '');

  double? number(String name) => double.tryParse(props[name] ?? '');

  bool flag(String name) => props[name] == 'true';

  /// Runs [actions] as if this entity had done it.
  void run(UiActionList actions, {Object? value}) => actions.run(
    UiActionContext(
      world: world,
      entity: entity,
      value: value,
      gameWorld: gameWorld,
      host: host,
    ),
  );

  /// The words behind a string that may be a key, a binding, or both.
  String resolve(String source) => UiBindings.of(
    world.context,
  ).resolveText(source, self: entity, localize: localize);
}

/// How an entity becomes a widget.
typedef UiWidgetBuilder = Widget Function(UiBuildContext context);

/// A kind of UI element: what it is called, what it builds, what it lets a
/// scene set.
class UiWidgetDefinition {
  const UiWidgetDefinition({
    required this.id,
    required this.label,
    required this.build,
    this.props = const [],
    this.takesChildren = false,
    this.icon,
    this.description = '',
  });

  /// What a scene saves — `inventory_grid`.
  final String id;

  /// What the editor calls it in its menu.
  final String label;

  final UiWidgetBuilder build;

  /// What the inspector offers for it.
  final List<UiWidgetProp> props;

  /// Whether entities under it are built and handed over as children.
  final bool takesChildren;

  final IconData? icon;
  final String description;
}

/// The widgets one engine's game brings, by id: what a
/// [UiCustomComponent] names.
///
/// Kept on the engine's [EngineContext] ([of]), not in a static, so two
/// engines never place each other's widgets, and a game's builders (and
/// what they hold on to) go with its engine.
final class UiWidgets {
  UiWidgets._();

  static final Object _key = Object();

  /// [context]'s widgets, made the first time they are asked for.
  static UiWidgets of(EngineContext context) => context.slot(_key, UiWidgets._);

  final Map<String, UiWidgetDefinition> _widgets = {};

  /// Makes [definition] placeable. Registering the same id again replaces
  /// it, so a game may override a built-in with its own.
  void register(UiWidgetDefinition definition) =>
      _widgets[definition.id] = definition;

  /// [register]s each of [definitions].
  void registerAll(Iterable<UiWidgetDefinition> definitions) {
    for (final definition in definitions) {
      register(definition);
    }
  }

  /// Forgets the widget registered as [id].
  void unregister(String id) => _widgets.remove(id);

  /// The widget registered as [id], or null.
  UiWidgetDefinition? byId(String id) => _widgets[id];

  /// Whether a widget is registered as [id].
  bool has(String id) => _widgets.containsKey(id);

  /// Everything a game has offered, for the editor's menu.
  List<UiWidgetDefinition> get all =>
      _widgets.values.toList()..sort((a, b) => a.label.compareTo(b.label));

  /// Forgets every widget. For a test, or a game tearing down.
  void clear() => _widgets.clear();

  /// What [context]'s entity builds, or null when nothing here knows how.
  Widget? build(UiBuildContext context) {
    final custom = context.entity.getComponent<UiCustomComponent>();
    if (custom == null) return null;
    final definition = _widgets[custom.widgetId];
    if (definition == null) {
      // A scene naming a widget this game does not have: better an empty
      // space than a crash, and the Problems dock says which.
      return const SizedBox.shrink();
    }
    return definition.build(
      UiBuildContext(
        entity: context.entity,
        world: context.world,
        theme: context.theme,
        children: context.children,
        props: propsOf(custom),
        localize: context.localize,
        gameWorld: context.gameWorld,
        host: context.host,
      ),
    );
  }

  /// What [custom] tells its widget: every property the widget declares,
  /// with its default where the scene says nothing, and whatever else the
  /// scene set.
  Map<String, String> propsOf(UiCustomComponent custom) {
    final definition = _widgets[custom.widgetId];
    return {
      for (final prop in definition?.props ?? const <UiWidgetProp>[])
        prop.name: custom.props[prop.name] ?? prop.defaultValue,
      ...custom.props,
    };
  }
}
