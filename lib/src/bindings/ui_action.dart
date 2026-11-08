/// What a button does when it is pressed, as a scene saves it.
library;

import 'package:just_game_engine/just_game_engine.dart';

import 'ui_actions.dart';

/// What an action is told when it runs.
class UiActionContext {
  const UiActionContext({
    required this.world,
    this.entity,
    this.argument = '',
    this.value,
    this.gameWorld,
    this.host,
  });

  /// The world [entity] lives in — for a screen, the interface's own.
  final World world;

  /// The game's world, when [world] is the interface's: a name an action
  /// gives (a timeline to play) is looked for there too.
  final World? gameWorld;

  /// Where `ui.*` and `game.*` go for this action instead of
  /// [UiActions.host] — an editor previewing a screen, which must not
  /// pause the game it is not running.
  final UiActionHost? host;

  /// The entity whose UI ran this — a button, a slider.
  final Entity? entity;

  /// What the action was given in the scene: a scene name, a timeline path,
  /// the name of another UI entity.
  final String argument;

  /// What changed, for the events that carry something: a slider's number,
  /// a toggle's flag, a field's text.
  final Object? value;

  /// [value] as a number, when it is one.
  double? get number => value is num ? (value! as num).toDouble() : null;
}

/// Runs an action.
typedef UiActionHandler = void Function(UiActionContext context);

/// One thing to do, as it is saved: a kind, and what it acts on.
///
/// `UiAction('timeline.play', 'assets/timelines/open.timeline.json')`
class UiAction {
  const UiAction(this.kind, [this.argument = '']);

  /// A built-in's name, or `custom:<name>` for one the game registered.
  final String kind;
  final String argument;

  /// The name a game registered, for a `custom:` action.
  String? get customName =>
      kind.startsWith('custom:') ? kind.substring(7) : null;

  UiAction copyWith({String? kind, String? argument}) =>
      UiAction(kind ?? this.kind, argument ?? this.argument);

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (argument.isNotEmpty) 'arg': argument,
  };

  factory UiAction.fromJson(Map<String, dynamic> json) =>
      UiAction(json['kind'] as String? ?? '', json['arg'] as String? ?? '');

  @override
  bool operator ==(Object other) =>
      other is UiAction && other.kind == kind && other.argument == argument;

  @override
  int get hashCode => Object.hash(kind, argument);

  @override
  String toString() =>
      'UiAction($kind${argument.isEmpty ? '' : ': $argument'})';
}

/// A list of actions, as a field holds it — what one event sets off.
class UiActionList {
  const UiActionList(this.actions);

  static const UiActionList empty = UiActionList([]);

  final List<UiAction> actions;

  bool get isEmpty => actions.isEmpty;
  bool get isNotEmpty => actions.isNotEmpty;

  /// Runs them in order, through the actions of [context]'s world
  /// ([UiActions.of] its context).
  void run(UiActionContext context) {
    final registry = UiActions.of(context.world.context);
    for (final action in actions) {
      registry.run(action, context);
    }
  }

  UiActionList copyWith({List<UiAction>? actions}) =>
      UiActionList(actions ?? this.actions);

  List<Map<String, dynamic>> toJson() => [for (final a in actions) a.toJson()];

  factory UiActionList.fromJson(Object? json) => UiActionList([
    if (json is List)
      for (final a in json)
        if (a is Map) UiAction.fromJson(a.cast<String, dynamic>()),
  ]);

  @override
  bool operator ==(Object other) =>
      other is UiActionList &&
      other.actions.length == actions.length &&
      _same(other.actions, actions);

  static bool _same(List<UiAction> a, List<UiAction> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(actions);

  @override
  String toString() => 'UiActionList($actions)';
}

/// What a built-in action needs from whoever is hosting the game: loading a
/// scene, pausing, quitting. The engine cannot do these by itself, so a
/// host offers what it can and the rest do nothing.
class UiActionHost {
  const UiActionHost({
    this.loadScene,
    this.pause,
    this.resume,
    this.quit,
    this.playSound,
    this.showUi,
    this.pushScreen,
    this.back,
  });

  /// Opens the scene at a path: `scene.load`.
  final void Function(String scene)? loadScene;

  /// Pauses the game: `game.pause`.
  final void Function()? pause;

  /// Resumes it: `game.resume`.
  final void Function()? resume;

  /// Leaves the game: `game.quit`.
  final void Function()? quit;

  /// Plays a sound at a path: `audio.play`.
  final void Function(String path)? playSound;

  /// Shows, hides or flips a UI entity by name: true shows, false hides,
  /// null flips.
  final void Function(String entityName, bool? visible)? showUi;

  /// Opens a screen over the open ones: `ui.push`.
  final void Function(String entityName)? pushScreen;

  /// Closes the screen on top: `ui.back`.
  final void Function()? back;

  /// This host, with whatever it leaves out taken from [below].
  UiActionHost over(UiActionHost below) => UiActionHost(
    loadScene: loadScene ?? below.loadScene,
    pause: pause ?? below.pause,
    resume: resume ?? below.resume,
    quit: quit ?? below.quit,
    playSound: playSound ?? below.playSound,
    showUi: showUi ?? below.showUi,
    pushScreen: pushScreen ?? below.pushScreen,
    back: back ?? below.back,
  );
}
