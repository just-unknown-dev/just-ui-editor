// What the Problems dock says about the game's screens: read from their
// files, since a level no longer holds them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import '../../support/ui_test_support.dart';

void main() {
  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );
  late Directory dir;
  late UiProject project;
  final listed = <Map<String, Object?>>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ui_checks');
    project = UiProject(dir.path);
    listed.clear();
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  /// Writes a screen called [name] holding [children], and lists it.
  void screen(
    String name,
    List<(String, List<Component>)> children, {
    bool isScreen = false,
    String initialFocus = '',
    bool closesOnBack = true,
  }) {
    final world = uiWorld(engineContext)..initialize();
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(
        isScreen: isScreen,
        initialFocus: initialFocus,
        closesOnBack: closesOnBack,
      ),
    ], name: name);
    for (final (childName, components) in children) {
      UiDocument.link(
        world.createEntityWithComponents(components, name: childName),
        canvas,
      );
    }
    final path = 'assets/ui/${UiSceneExtractor.fileNameFor(name)}';
    project.writeScreen(path, UiDocument.capture(canvas, world));
    listed.add({'path': path});
    project.writeJsonSync(UiScreenManifest.defaultPath, {'screens': listed});
    world.dispose();
  }

  List<String> messages() => [
    for (final p in UiChecks.screens(project, context: engineContext))
      p.message,
  ];

  UiButtonComponent button(String action, [String argument = '']) =>
      UiButtonComponent(
        label: 'Go',
        onPressed: UiActionList([UiAction(action, argument)]),
      );

  test('an action that is not an action', () {
    screen('Hud', [
      ('Go', [button('scene.lod', 'level_02')]),
    ]);
    expect(messages(), contains(contains('"scene.lod", which is not an')));
  });

  test(
    'a custom action the game does not register — once it registers any',
    () {
      screen('Hud', [
        ('Go', [button('custom:explode')]),
      ]);
      // The game is not running: an empty registry means "cannot tell".
      expect(messages(), isNot(contains(contains('custom:explode'))));

      UiActions.of(engineContext).register('cheer', (_) {});
      expect(messages(), contains(contains('custom:explode')));
    },
  );

  test('a button nothing happens with', () {
    screen('Hud', [
      ('Go', [UiButtonComponent(label: 'Go')]),
    ]);
    expect(messages(), contains(contains('nothing happens when it is')));
  });

  test('a text reading something the game does not offer', () {
    UiBindings.of(engineContext).register('coins', () => 0);
    screen('Hud', [
      ('Counter', [UiTextComponent(text: '{coins} / {gems}')]),
    ]);
    expect(messages(), contains(contains('reads {gems}')));
  });

  group('a screen and the keyboard', () {
    test('nothing on it to focus', () {
      screen('Pause', [
        ('Title', [UiTextComponent(text: 'Paused')]),
      ], isScreen: true);
      expect(messages(), contains(contains('nothing to focus')));
    });

    test('not saying what takes focus', () {
      screen('Pause', [
        ('Resume', [button('ui.back')]),
      ], isScreen: true);
      expect(messages(), contains(contains('does not say what takes focus')));
    });

    test('focusing something that is not one of its controls', () {
      screen(
        'Pause',
        [
          ('Resume', [button('ui.back')]),
        ],
        isScreen: true,
        initialFocus: 'Elsewhere',
      );
      expect(messages(), contains(contains('which is not one of its')));
    });

    test('set up right, nothing is said', () {
      screen(
        'Pause',
        [
          ('Resume', [button('ui.back')]),
        ],
        isScreen: true,
        initialFocus: 'Resume',
      );
      expect(messages(), isEmpty);
    });
  });

  group('a screen Back does not close', () {
    test('with nothing on it to leave by', () {
      screen(
        'Waiting',
        [
          ('Title', [UiTextComponent(text: 'Waiting for players')]),
        ],
        isScreen: true,
        closesOnBack: false,
      );
      expect(messages(), contains(contains('only the game can close it')));
    });

    test('with a button on it, nothing is said', () {
      screen(
        'Complete',
        [
          ('Again', [button('custom:restart')]),
        ],
        isScreen: true,
        initialFocus: 'Again',
        closesOnBack: false,
      );
      expect(messages(), isEmpty);
    });

    test('a layer, which Back never closes anyway', () {
      screen('Hud', const [], closesOnBack: false);
      expect(messages(), contains(contains('Back never closes one')));
    });
  });

  group('the game\'s list', () {
    test('a screen on it that is not there', () {
      project.writeJsonSync(UiScreenManifest.defaultPath, {
        'screens': [
          {'path': 'assets/ui/gone.ui.json'},
        ],
      });
      final problems = UiChecks.screens(project, context: engineContext);
      expect(problems.single.message, contains('which is not there'));
      expect(problems.single.severity, ProblemSeverity.error);
    });

    test('two screens with one name', () {
      screen('Pause', const []);
      final copy = project.readScreen('assets/ui/pause.ui.json');
      project.writeScreen('assets/ui/pause_again.ui.json', copy);
      listed.add({'path': 'assets/ui/pause_again.ui.json'});
      project.writeJsonSync(UiScreenManifest.defaultPath, {'screens': listed});

      expect(messages(), contains(contains('are both called "Pause"')));
    });

    test('a button opening a screen the game does not have', () {
      screen('Hud', [
        ('Settings', [button('ui.push', 'Settings')]),
      ]);
      expect(
        messages(),
        contains(contains('opens "Settings", which is no screen')),
      );

      screen('Settings', const []);
      expect(messages(), isNot(contains(contains('opens "Settings"'))));
    });

    test('a file that does not read says so, and the rest still checks', () {
      screen('Hud', [
        ('Go', [UiButtonComponent(label: 'Go')]),
      ]);
      File('${dir.path}/assets/ui/broken.ui.json').writeAsStringSync('{');
      listed.add({'path': 'assets/ui/broken.ui.json'});
      project.writeJsonSync(UiScreenManifest.defaultPath, {'screens': listed});

      final said = messages();
      expect(said, contains(contains('broken.ui.json does not read')));
      expect(said, contains(contains('nothing happens when it is')));
    });

    test('a layer pushed as though it were a screen', () {
      screen('Hud', const []);
      screen('Pause', [
        ('Go', [button('ui.push', 'Hud')]),
      ], isScreen: true);

      expect(messages(), contains(contains('pushes "Hud", which is a layer')));
    });

    test('a theme that is not there, or does not read', () {
      screen('Hud', const []);
      project.writeJsonSync(UiScreenManifest.defaultPath, {
        'theme': 'assets/ui/gone.uitheme.json',
        'screens': listed,
      });
      expect(messages(), contains(contains('gone.uitheme.json is not there')));

      File('${dir.path}/assets/ui/gone.uitheme.json').writeAsStringSync('{');
      expect(messages(), contains(contains('gone.uitheme.json does not read')));
    });

    test('a list that does not read says so', () {
      screen('Hud', const []);
      File(
        '${dir.path}/${UiScreenManifest.defaultPath}',
      ).writeAsStringSync('{"screens": [,]}');

      final problems = UiChecks.screens(project, context: engineContext);
      expect(problems.single.message, contains('screens.json does not read'));
      expect(problems.single.severity, ProblemSeverity.error);
    });
  });

  group('controls and tags', () {
    test('an icon the game does not register', () {
      UiIcons.of(engineContext).register('coin', const IconData(0xe000));
      screen('Hud', [
        ('Coins', [UiTextComponent(text: '[icon=coin] [icon=gem] 12')]),
      ]);

      final said = messages();
      expect(said, contains(contains('[icon=gem]')));
      expect(said, isNot(contains(contains('[icon=coin]'))));
    });

    test('with no icons registered, none is complained of', () {
      screen('Hud', [
        ('Coins', [UiTextComponent(text: '[icon=gem] 12')]),
      ]);
      expect(messages(), isNot(contains(contains('[icon='))));
    });

    test('a link that cannot be clicked', () {
      screen('Hud', [
        (
          'Shop',
          [UiTextComponent(text: '[wave][link=shop]Shop[/link][/wave]')],
        ),
        ('Plain', [UiTextComponent(text: '[link=shop]Shop[/link]')]),
      ]);
      final said = messages();
      expect(said, contains(contains('Hud › Shop has a [link]')));
      expect(said, isNot(contains(contains('Hud › Plain has a [link]'))));

      final level = uiWorld(engineContext)..initialize();
      level.createEntityWithComponents([
        UiTextComponent(text: 'Visit the [link=shop]shop[/link]'),
      ], name: 'Sign');
      expect(
        UiChecks.level(level).map((p) => p.message),
        contains(contains('Sign has a [link]')),
      );
    });

    test('a slider from more to less, and a choice offered twice', () {
      screen('Options', [
        ('Volume', [UiSliderComponent(min: 1, max: 0)]),
        (
          'Size',
          [
            UiDropdownComponent(options: ['Small', 'Big', 'Small']),
          ],
        ),
      ]);
      final said = messages();
      expect(said, contains(contains('its least is more than its most')));
      expect(said, contains(contains('offers "Small" more than once')));
    });

    test('a flex or a spacer outside a row or a column', () {
      screen('Hud', [
        ('Wide', [UiSlotComponent(flex: 1)]),
        ('Gap', [UiSpacerComponent(expand: true), UiSlotComponent()]),
      ]);
      final said = messages();
      expect(said, contains(contains('Hud › Wide has a flex')));
      expect(said, contains(contains('Hud › Gap is a spacer')));
    });
  });

  test('asked again with nothing changed, the files are not read again', () {
    screen('Hud', [
      ('Go', [UiButtonComponent(label: 'Go')]),
    ]);
    final first = UiChecks.screens(project, context: engineContext);
    expect(UiChecks.screens(project, context: engineContext), same(first));

    // A screen saved again is checked again.
    final world = uiWorld(engineContext)..initialize();
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(),
    ], name: 'Hud');
    project.writeScreen(
      'assets/ui/hud.ui.json',
      UiDocument.capture(canvas, world),
    );
    world.dispose();
    final after = UiChecks.screens(project, context: engineContext);
    expect(after, isNot(same(first)));
    expect(after, isEmpty);
  });

  test('the file reads back as it was written', () {
    screen('Hud', const []);
    final json =
        jsonDecode(File('${dir.path}/assets/ui/hud.ui.json').readAsStringSync())
            as Map;
    expect(json['name'], 'Hud');
  });

  test('bindings a scene asks for but the game never registered', () {
    final world = uiWorld(engineContext);
    UiBindings.of(engineContext).register('coins', () => 1);
    world.createEntityWithComponents([
      UiTextComponent(text: '{coins} / {gems}'),
    ], name: 'Line');

    expect(UiChecks.missingBindings(world), ['gems']);
  });

  test("one engine's last check is not another's", () {
    screen('Hud', [
      ('Go', [UiButtonComponent(label: 'Go')]),
    ]);
    final other = EngineContext(extensions: const [JustGameUi.extension]);

    final mine = UiChecks.screens(project, context: engineContext);
    final theirs = UiChecks.screens(project, context: other);

    expect(identical(mine, theirs), isFalse);
    expect(UiChecks.screens(project, context: other), same(theirs));
  });
}
