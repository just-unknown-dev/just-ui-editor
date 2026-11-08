/// What the Problems dock says about the interface.
library;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/io.dart' show File;
import 'package:just_editor_core/just_editor_core.dart';

import '../../bindings/bindings.dart';
import '../../controls/controls.dart';
import '../../layout/layout.dart';
import '../../screens/screens.dart';
import '../../text/text.dart';
import '../../theme/theme.dart';
import 'ui_level_screens.dart';
import 'ui_project.dart';

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
    // Kept per engine: two editors' Problems docks never answer from each
    // other's last check.
    final cache = context == null
        ? _UiChecksCache()
        : context.slot(_cacheKey, _UiChecksCache.new);
    final stamp = _stamp(project, context, cache);
    if (stamp == cache.checkedAt) return cache.checked;
    final found = List<SceneProblem>.unmodifiable(
      _screens(project, context, cache),
    );
    cache
      ..checkedAt = stamp
      ..checked = found;
    return found;
  }

  static final Object _cacheKey = Object();

  /// What [screens]' answer depends on, cheaply: each file as it stands
  /// on disk (its time and size only), and the names the game registered.
  /// The list itself is read again only when it changed on disk.
  static String _stamp(
    UiProject project,
    EngineContext? context,
    _UiChecksCache cache,
  ) {
    String onDisk(String path) {
      final file = File(project.absolute(path));
      if (!file.existsSync()) return '$path:-';
      final stat = file.statSync();
      return '$path:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    }

    final list = onDisk(UiScreenManifest.defaultPath);
    if (list != cache.listStamp || project.root != cache.root) {
      cache
        ..root = project.root
        ..listStamp = list
        ..listed = [for (final e in project.readManifest().screens) e.path];
    }
    return [
      project.root,
      list,
      for (final path in cache.listed) onDisk(path),
      if (context != null) ...[
        Object.hashAll(UiBindings.of(context).names),
        Object.hashAll(UiActions.of(context).customNames),
        Object.hashAll([for (final w in UiWidgets.of(context).all) w.id]),
        Object.hashAll(UiIcons.of(context).names),
      ],
      // The themes the screens were drawn with when last checked: a
      // screen naming another changes its own file, which is above.
      for (final theme in cache.themesSeen) onDisk(theme),
    ].join('|');
  }

  /// Every binding the texts in [world] read that its game does not offer,
  /// sorted — what the Problems dock lists, and what a game's test can ask
  /// of a screen.
  static List<String> missingBindings(World world) {
    final bindings = UiBindings.of(world.context);
    final missing = <String>{};
    for (final entity in world.query([UiTextComponent])) {
      final text = entity.getComponent<UiTextComponent>()!;
      for (final name in UiBindings.namesIn(text.text)) {
        if (!bindings.has(name)) missing.add(name);
      }
    }
    return missing.toList()..sort();
  }

  /// A world to build one screen in, on [context] (its own when null).
  static World _worldOn(EngineContext? context) => World(context: context)
    ..context.install(JustGameUi.extension)
    ..initialize();

  static List<SceneProblem> _screens(
    UiProject project,
    EngineContext? context,
    _UiChecksCache cache,
  ) {
    final out = <SceneProblem>[];
    if (project.manifestProblem() case final problem?) {
      out.add(
        SceneProblem(
          severity: ProblemSeverity.error,
          message:
              '${UiScreenManifest.defaultPath} does not read: $problem. The '
              'game cannot start its interface, and the editor leaves the '
              'list alone until it is mended.',
          hint: 'Mend it by hand: it is JSON.',
        ),
      );
      return out;
    }
    final list = project.readManifest();
    final names = <String, String>{};
    // The screens that are layers — always there, never pushed.
    final layers = <String>{};
    final themes = <String>{?list.theme};
    // Each listed screen built once, for every check, and let go after.
    final built = <(World, Entity)>[];
    try {
      for (final entry in list.screens) {
        if (!project.exists(entry.path)) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              message:
                  'The game lists ${entry.path}, which is not there — it '
                  'will start without that screen.',
              hint:
                  'Take it off the list in the Interface editor, or restore '
                  'it.',
            ),
          );
          continue;
        }
        final world = _worldOn(context);
        final Entity canvas;
        try {
          canvas = project
              .readScreen(entry.path, hooks: world.context.migrations)
              .instantiate(
                world,
                decode: SceneCodec(world.context.definitions).decodeAll,
              );
        } on Object catch (error) {
          world.dispose();
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              message: '${entry.path} does not read: $error',
            ),
          );
          continue;
        }
        built.add((world, canvas));
        final name = canvas.name ?? entry.path;
        if (names[name] case final other?) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              message:
                  '${entry.path} and $other are both called "$name" — the '
                  'game opens screens by name.',
              hint: 'Rename one of them.',
            ),
          );
        }
        names[name] = entry.path;
        final settings = canvas.getComponent<UiCanvasComponent>();
        if (settings != null && !settings.isScreen) layers.add(name);
        if (settings != null && settings.theme.isNotEmpty) {
          themes.add(settings.theme);
        }
        out.addAll(_screen(world, canvas));
      }
      for (final (world, _) in built) {
        out.addAll(_opensWhatIsNotThere(world, names.keys.toSet(), layers));
      }
    } finally {
      for (final (world, _) in built) {
        world.dispose();
      }
    }
    cache.themesSeen = themes;
    out.addAll(_themes(project, themes, context));
    return out;
  }

  /// A theme the list or a screen names that is not there, or does not
  /// read: what names it draws with the built-in one instead.
  static List<SceneProblem> _themes(
    UiProject project,
    Set<String> themes,
    EngineContext? context,
  ) => [
    for (final path in themes)
      if (_themeProblem(project, path, context) case final problem?)
        SceneProblem(
          severity: ProblemSeverity.error,
          message:
              'The theme $path $problem: what names it is drawn with the '
              'built-in theme.',
          hint: 'Restore it, or choose another in the Theme tab.',
        ),
  ];

  static String? _themeProblem(
    UiProject project,
    String path,
    EngineContext? context,
  ) {
    final String? text;
    try {
      text = project.readSync(path);
    } on Object catch (error) {
      return 'does not read ($error)';
    }
    if (text == null) {
      final loaded = context == null ? null : UiThemes.of(context);
      return loaded != null &&
              loaded.cached(path) != null &&
              !loaded.failed(path)
          ? null // From the app bundle, then: a package's theme.
          : 'is not there';
    }
    try {
      UiTheme.parse(text);
      return null;
    } on Object catch (error) {
      return 'does not read ($error)';
    }
  }

  /// `ui.push Settings` on a button in [world]'s screen, with no screen
  /// called Settings among [names].
  static List<SceneProblem> _opensWhatIsNotThere(
    World world,
    Set<String> names,
    Set<String> layers,
  ) {
    final out = <SceneProblem>[];
    for (final e in world.entities) {
      for (final actions in _actionListsOf(e)) {
        for (final action in actions.actions) {
          // A layer sits under the screens and is never stacked: a push
          // only shows it, and Back does not take it away. Said, since
          // whoever wrote the push most likely meant a screen.
          if (action.kind == 'ui.push' && layers.contains(action.argument)) {
            out.add(
              SceneProblem(
                message:
                    '${_where(world, e)} pushes "${action.argument}", which '
                    'is a layer, not a screen: it is only shown, under the '
                    'screens, and Back does not close it.',
                hint: 'Use ui.show, or make it a screen.',
              ),
            );
            continue;
          }
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
    return out;
  }

  /// One screen: what its elements do and read, and whether it can be
  /// used without a pointer.
  static List<SceneProblem> _screen(World world, Entity canvasEntity) {
    final out = <SceneProblem>[];
    for (final e in world.entities) {
      out.addAll(
        _element(e, where: _where(world, e), entity: null, world: world),
      );
    }
    final canvas = canvasEntity.getComponent<UiCanvasComponent>();
    if (canvas == null) return out;
    final name = canvasEntity.name ?? 'A screen';
    if (!canvas.isScreen) {
      // Back never closes a layer, so saying it does not means nothing.
      if (!canvas.closesOnBack) {
        out.add(
          SceneProblem(
            message:
                '$name is a layer: Back never closes one, so "Closes on '
                'Back" being off does nothing.',
            hint: 'Make it a screen, or turn "Closes on Back" on again.',
          ),
        );
      }
      return out;
    }
    if (!canvas.closesOnBack &&
        !world.entities.any((e) => e.isActive && _mayDoSomething(e))) {
      out.add(
        SceneProblem(
          message:
              '$name does not close on Back, and nothing on it does '
              'anything: once open, only the game can close it.',
          hint: 'Give it a button, or turn "Closes on Back" on.',
        ),
      );
    }
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
          (e.hasComponent<UiTextComponent>() ||
              e.hasComponent<UiButtonComponent>()))
        ..._element(
          e,
          where: e.name ?? 'Entity ${e.id}',
          entity: e,
          world: world,
          inLevel: true,
        ),
  ];

  /// One element's problems. [inLevel]: it is text or a button placed in
  /// the level itself, painted on the game, rather than part of a screen.
  static List<SceneProblem> _element(
    Entity e, {
    required String where,
    required Entity? entity,
    required World world,
    bool inLevel = false,
  }) {
    final out = <SceneProblem>[];
    // What the game registered on the engine [world] is in.
    final registered = world.context;
    final knownBindings = UiBindings.of(registered).names.toSet();
    final knownActions = UiActions.of(registered).customNames.toSet();
    final knownWidgets = {for (final w in UiWidgets.of(registered).all) w.id};

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
    final text = e.getComponent<UiTextComponent>();
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
    out
      ..addAll(
        _tagsOf(
          e,
          where: where,
          entity: entity,
          inLevel: inLevel,
          icons: UiIcons.of(registered),
        ),
      )
      ..addAll(_controlsOf(e, where: where, entity: entity, world: world));
    return out;
  }

  /// `[icon=…]` names the game does not register, and `[link=…]` runs that
  /// cannot be clicked: text in the level, or text a screen paints by hand
  /// (an effect, a gradient, an outline, shrinking to fit).
  static List<SceneProblem> _tagsOf(
    Entity e, {
    required String where,
    required Entity? entity,
    required bool inLevel,
    required UiIcons icons,
  }) {
    final out = <SceneProblem>[];
    final text = e.getComponent<UiTextComponent>();
    final button = e.getComponent<UiButtonComponent>();
    final names = icons.names.toSet();
    for (final source in [?text?.text, ?button?.label]) {
      final rich = UiRichText.parse(source);
      // Like bindings: with nothing registered, nothing can be told.
      if (names.isNotEmpty) {
        for (final name in {
          for (final span in rich.spans)
            if (span.icon case final icon? when icon.isNotEmpty) icon,
        }) {
          if (icons.has(name)) continue;
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '$where shows [icon=$name], which the game does not '
                  'register: it is drawn as nothing.',
            ),
          );
        }
      }
      if (text == null || !identical(source, text.text)) continue;
      if (!rich.spans.any((s) => s.link != null)) continue;
      final look = text.style;
      final painted =
          rich.needsPainter ||
          (look.gradient?.length ?? 0) > 1 ||
          (look.outline?.isVisible ?? false) ||
          text.overflow == UiTextOverflow.shrink;
      if (inLevel || painted) {
        out.add(
          SceneProblem(
            entity: entity,
            message: inLevel
                ? '$where has a [link], which cannot be clicked in text '
                      'placed in the level.'
                : '$where has a [link], which cannot be clicked: an effect, '
                      'a gradient, an outline or shrinking to fit has it '
                      'painted by hand.',
            hint: inLevel
                ? 'Put it on a screen, or use a button.'
                : 'Take that look off the text, or use a button.',
          ),
        );
      }
    }
    return out;
  }

  /// Controls set up so they cannot work as meant: a slider whose least is
  /// more than its most, a dropdown offering one choice twice, and a flex
  /// or a stretching spacer outside a row or a column, where it means
  /// nothing.
  static List<SceneProblem> _controlsOf(
    Entity e, {
    required String where,
    required Entity? entity,
    required World world,
  }) {
    final out = <SceneProblem>[];
    final slider = e.getComponent<UiSliderComponent>();
    if (slider != null && slider.min > slider.max) {
      out.add(
        SceneProblem(
          entity: entity,
          severity: ProblemSeverity.error,
          message:
              '$where goes from ${slider.min} to ${slider.max}: its least is '
              'more than its most.',
          hint: 'Swap Min and Max.',
        ),
      );
    }
    final dropdown = e.getComponent<UiDropdownComponent>();
    if (dropdown != null) {
      final seen = <String>{};
      final twice = {
        for (final option in dropdown.options)
          if (!seen.add(option)) option,
      };
      for (final option in twice) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '$where offers "$option" more than once: a player cannot '
                'tell the two apart.',
          ),
        );
      }
    }
    final flex = (e.getComponent<UiSlotComponent>()?.flex ?? 0) > 0;
    final stretches = e.getComponent<UiSpacerComponent>()?.expand ?? false;
    if (flex || stretches) {
      final parentId = e.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : world.getEntity(parentId);
      final inFlex =
          parent?.getComponent<UiLayoutComponent>()?.kind.isFlex ?? false;
      if (!inFlex) {
        out.add(
          SceneProblem(
            entity: entity,
            message: stretches
                ? '$where is a spacer that takes what is left, outside a '
                      'row or a column: it takes nothing.'
                : '$where has a flex, outside a row or a column: it is '
                      'given its size instead.',
            hint: 'Put it in a row or a column, or leave the flex out.',
          ),
        );
      }
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
    ?entity.getComponent<UiButtonComponent>()?.onPressed,
    ?entity.getComponent<UiToggleComponent>()?.onChanged,
    ?entity.getComponent<UiSliderComponent>()?.onChanged,
    ?entity.getComponent<UiTextFieldComponent>()?.onSubmitted,
    ?entity.getComponent<UiTextFieldComponent>()?.onChanged,
    ?entity.getComponent<UiDropdownComponent>()?.onChanged,
  ];

  static bool _isInteractive(Entity e) =>
      e.hasComponent<UiButtonComponent>() ||
      e.hasComponent<UiToggleComponent>() ||
      e.hasComponent<UiSliderComponent>() ||
      e.hasComponent<UiDropdownComponent>();

  static bool _isFocusable(Entity e) =>
      _isInteractive(e) || e.hasComponent<UiTextFieldComponent>();

  /// Whether [e] may be a way off a screen: it runs actions, or it is a
  /// game's own widget, which may hold anything.
  static bool _mayDoSomething(Entity e) =>
      _actionListsOf(e).any((a) => a.isNotEmpty) ||
      e.hasComponent<UiCustomComponent>();
}

/// What [UiChecks.screens] last found, and what it found it from, for one
/// engine.
final class _UiChecksCache {
  String? checkedAt;
  List<SceneProblem> checked = const [];
  String? root;
  String? listStamp;
  List<String> listed = const [];

  /// Every theme the list and its screens named, as last checked.
  Set<String> themesSeen = const {};
}
