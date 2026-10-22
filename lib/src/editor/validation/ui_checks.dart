/// What the Problems dock says about the interface.
library;

import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/text_component.dart';
import '../../runtime/just_game_ui.dart';
import '../../runtime/layer/ui_widgets.dart';
import '../../runtime/logic/ui_actions.dart';
import '../../runtime/logic/ui_bindings.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import '../project/ui_level_screens.dart';
import '../project/ui_project.dart';

/// Checks of the game's screens — read from their files, since they are
/// not in the level — and of the text and buttons the level itself holds.
///
/// What a game registered (bindings, actions, widgets) is only known while
/// that game is running in the editor, so the checks that need a registry
/// stay quiet while it is empty: empty means "cannot tell", not "none".
abstract final class UiChecks {
  /// The validator the module hands the editor.
  static List<SceneProblem> run(ValidationContext context) => [
    ...screens(UiProject(context.projectRoot), context: context.scope.context),
    ...level(context.world),
  ];

  /// Every screen on the game's list, and the list itself.
  ///
  /// The Problems dock asks about once a second; the files are read and
  /// the screens built again only when something they depend on changed —
  /// the list, a screen's file, what the game registered.
  ///
  /// The screens are built on [context] — the edited engine's, so the
  /// game's own components read — or on a context of their own when null.
  static List<SceneProblem> screens(
    UiProject project, {
    EngineContext? context,
  }) {
    final stamp = _stamp(project);
    if (stamp == _checkedAt) return _checked;
    final found = List<SceneProblem>.unmodifiable(_screens(project, context));
    _checkedAt = stamp;
    _checked = found;
    return found;
  }

  static String? _checkedAt;
  static List<SceneProblem> _checked = const [];

  /// What [screens]' answer depends on, cheaply: each file as it stands
  /// on disk, and the names the game registered.
  static String _stamp(UiProject project) {
    String onDisk(String path) {
      final file = File(project.absolute(path));
      if (!file.existsSync()) return '$path:-';
      final stat = file.statSync();
      return '$path:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    }

    return [
      project.root,
      onDisk(UiScreenManifest.defaultPath),
      for (final entry in project.readManifest().screens) onDisk(entry.path),
      Object.hashAll(UiBindings.names),
      Object.hashAll(UiActions.customNames),
      Object.hashAll([for (final w in UiWidgets.all) w.id]),
    ].join('|');
  }

  /// A world to build one screen in, on [context] (its own when null).
  static World _worldOn(EngineContext? context) => World(context: context)
    ..context.install(JustGameUi.extension)
    ..initialize();

  static List<SceneProblem> _screens(
    UiProject project,
    EngineContext? context,
  ) {
    final out = <SceneProblem>[];
    final list = project.readManifest();
    final names = <String, String>{};
    for (final entry in list.screens) {
      if (!project.exists(entry.path)) {
        out.add(
          SceneProblem(
            severity: ProblemSeverity.error,
            message:
                'The game lists ${entry.path}, which is not there — it will '
                'start without that screen.',
            hint:
                'Take it off the list in the Interface editor, or restore it.',
          ),
        );
        continue;
      }
      final World world;
      final Entity canvas;
      try {
        world = _worldOn(context);
        canvas = project
            .readScreen(entry.path)
            .instantiate(
              world,
              decode: SceneCodec(world.context.definitions).decodeAll,
            );
      } on Object catch (error) {
        out.add(
          SceneProblem(
            severity: ProblemSeverity.error,
            message: '${entry.path} does not read: $error',
          ),
        );
        continue;
      }
      final name = canvas.name ?? entry.path;
      if (names[name] case final other?) {
        out.add(
          SceneProblem(
            severity: ProblemSeverity.error,
            message:
                '${entry.path} and $other are both called "$name" — the game '
                'opens screens by name.',
            hint: 'Rename one of them.',
          ),
        );
      }
      names[name] = entry.path;
      out.addAll(_screen(world, canvas));
      world.dispose();
    }
    out.addAll(
      _opensWhatIsNotThere(project, list, names.keys.toSet(), context),
    );
    return out;
  }

  /// `ui.push Settings` on a button, with no screen called Settings.
  static List<SceneProblem> _opensWhatIsNotThere(
    UiProject project,
    UiScreenManifest list,
    Set<String> names,
    EngineContext? context,
  ) {
    final out = <SceneProblem>[];
    for (final entry in list.screens) {
      if (!project.exists(entry.path)) continue;
      final World world;
      try {
        world = _worldOn(context);
        project
            .readScreen(entry.path)
            .instantiate(
              world,
              decode: SceneCodec(world.context.definitions).decodeAll,
            );
      } on Object {
        continue;
      }
      for (final e in world.entities) {
        for (final actions in _actionListsOf(e)) {
          for (final action in actions.actions) {
            if (action.kind != 'ui.push' && action.kind != 'ui.show') continue;
            if (action.argument.isEmpty || names.contains(action.argument)) {
              continue;
            }
            // `ui.show` may name an element of the same screen.
            if (action.kind == 'ui.show' &&
                world.findEntityByName(action.argument) != null) {
              continue;
            }
            out.add(
              SceneProblem(
                message:
                    '${_where(world, e)} opens "${action.argument}", which is '
                    'no screen on the game\'s list.',
              ),
            );
          }
        }
      }
      world.dispose();
    }
    return out;
  }

  /// One screen: what its elements do and read, and whether it can be
  /// used without a pointer.
  static List<SceneProblem> _screen(World world, Entity canvasEntity) {
    final out = <SceneProblem>[];
    for (final e in world.entities) {
      out.addAll(_element(e, where: _where(world, e), entity: null));
    }
    final canvas = canvasEntity.getComponent<UiCanvasComponent>();
    if (canvas == null || !canvas.isScreen) return out;
    final name = canvasEntity.name ?? 'A screen';
    final focusable = [
      for (final e in world.entities)
        if (_isFocusable(e)) e,
    ];
    if (focusable.isEmpty) {
      out.add(
        SceneProblem(
          message:
              '$name is a screen with nothing to focus: it cannot be used '
              'without a pointer.',
        ),
      );
    } else if (canvas.initialFocus.isEmpty) {
      out.add(
        SceneProblem(
          message: '$name does not say what takes focus when it opens.',
          hint: 'Set "First focus" on its canvas to one of its controls.',
        ),
      );
    } else if (!focusable.any((e) => e.name == canvas.initialFocus)) {
      out.add(
        SceneProblem(
          severity: ProblemSeverity.error,
          message:
              '$name focuses "${canvas.initialFocus}" when it opens, which is '
              'not one of its controls.',
        ),
      );
    } else if (focusable.any(
      (e) => e.name == canvas.initialFocus && !e.isActive,
    )) {
      out.add(
        SceneProblem(
          severity: ProblemSeverity.error,
          message:
              '$name focuses "${canvas.initialFocus}" when it opens, which is '
              'switched off.',
        ),
      );
    }
    return out;
  }

  /// The text and buttons placed in the level itself — and any screen
  /// still inside it, from before screens were files of their own.
  static List<SceneProblem> level(World world) => [
    for (final canvas in UiLevelScreens.of(world))
      SceneProblem(
        message:
            '${canvas.name ?? 'A screen'} is inside the level. Screens are '
            'files of their own now: the game never shows one kept here.',
        hint:
            'Right-click it in the scene tree: Move screens out of the '
            'level.',
        entity: canvas,
      ),
    for (final e in world.entities)
      if (e.isAlive &&
          (e.hasComponent<TextComponent>() ||
              e.hasComponent<ButtonComponent>()))
        ..._element(e, where: e.name ?? 'Entity ${e.id}', entity: e),
  ];

  static List<SceneProblem> _element(
    Entity e, {
    required String where,
    required Entity? entity,
  }) {
    final out = <SceneProblem>[];
    final knownBindings = UiBindings.names.toSet();
    final knownActions = UiActions.customNames.toSet();
    final knownWidgets = {for (final w in UiWidgets.all) w.id};

    for (final actions in _actionListsOf(e)) {
      for (final action in actions.actions) {
        final custom = action.customName;
        if (custom != null) {
          if (knownActions.isNotEmpty && !knownActions.contains(custom)) {
            out.add(
              SceneProblem(
                entity: entity,
                message:
                    '$where does "custom:$custom", which this game does not '
                    'register.',
              ),
            );
          }
          continue;
        }
        if (!UiActions.builtIns.containsKey(action.kind)) {
          out.add(
            SceneProblem(
              entity: entity,
              severity: ProblemSeverity.error,
              message: '$where does "${action.kind}", which is not an action.',
            ),
          );
        }
      }
    }
    if (_isInteractive(e) && _actionListsOf(e).every((a) => a.isEmpty)) {
      out.add(
        SceneProblem(
          entity: entity,
          message: '$where can be used, but nothing happens when it is.',
          hint: 'Give it an action, or make it a plain element.',
        ),
      );
    }
    final text = e.getComponent<TextComponent>();
    if (text != null && knownBindings.isNotEmpty) {
      for (final binding in UiBindings.namesIn(text.text)) {
        if (knownBindings.contains(binding)) continue;
        out.add(
          SceneProblem(
            entity: entity,
            message: '$where reads {$binding}, which the game does not offer.',
          ),
        );
      }
    }
    final custom = e.getComponent<UiCustomComponent>();
    if (custom != null &&
        knownWidgets.isNotEmpty &&
        !knownWidgets.contains(custom.widgetId)) {
      out.add(
        SceneProblem(
          entity: entity,
          severity: ProblemSeverity.error,
          message:
              '$where is the widget "${custom.widgetId}", which this game does '
              'not register.',
        ),
      );
    }
    return out;
  }

  /// "Pause › PauseResume": which screen, and which element of it.
  static String _where(World world, Entity e) {
    var top = e;
    for (var i = 0; i < 64; i++) {
      final parentId = top.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : world.getEntity(parentId);
      if (parent == null) break;
      top = parent;
    }
    return identical(top, e)
        ? (e.name ?? 'A screen')
        : '${top.name} › ${e.name ?? 'an element'}';
  }

  static List<UiActionList> _actionListsOf(Entity entity) => [
    ?entity.getComponent<ButtonComponent>()?.onPressed,
    ?entity.getComponent<UiToggleComponent>()?.onChanged,
    ?entity.getComponent<UiSliderComponent>()?.onChanged,
    ?entity.getComponent<UiTextFieldComponent>()?.onSubmitted,
    ?entity.getComponent<UiTextFieldComponent>()?.onChanged,
    ?entity.getComponent<UiDropdownComponent>()?.onChanged,
  ];

  static bool _isInteractive(Entity e) =>
      e.hasComponent<ButtonComponent>() ||
      e.hasComponent<UiToggleComponent>() ||
      e.hasComponent<UiSliderComponent>() ||
      e.hasComponent<UiDropdownComponent>();

  static bool _isFocusable(Entity e) =>
      _isInteractive(e) || e.hasComponent<UiTextFieldComponent>();
}
