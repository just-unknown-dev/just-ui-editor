// The Interface module in the engine editor: what it adds, the game's
// screens only while a play-test runs, and screens an older level still
// holds moved out into files of their own.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_ui_editor/editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()..context.install(JustGameUi.extension);
void main() {
  late Directory dir;
  late UiEditorModule module;

  String file(String path) => '${dir.path}/$path';
  Map<String, dynamic> readJson(String path) =>
      (jsonDecode(File(file(path)).readAsStringSync()) as Map)
          .cast<String, dynamic>();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ui_module');
    module = UiEditorModule(root: dir.path);
    addTearDown(() {
      UiThemes.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  EditorScope scopeOver(World world) {
    final scope = EditorScope(world: world, modules: [module]);
    addTearDown(scope.dispose);
    return scope;
  }

  /// A screen the way an older level held one: a canvas and what is on it,
  /// entities of the level itself.
  Entity oldScreen(World world, String name, {bool showing = true}) {
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(visible: showing),
    ], name: name);
    final coins = world.createEntityWithComponents([
      TextComponent(text: 'Coins'),
      UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.topLeft,
        size: const Size(200, 40),
      ),
    ], name: '${name}Coins');
    UiDocument.link(coins, canvas);
    return canvas;
  }

  group('what it adds', () {
    test('a workspace for screens and themes, a button, a key', () {
      final scope = scopeOver(_uiWorld()..initialize());

      final workspace = scope.workspaces.singleWhere(
        (w) => w.id == UiEditorModule.workspaceId,
      );
      expect(workspace.fileExtensions, ['ui.json', 'uitheme.json']);
      expect(scope.openInWorkspace('assets/ui/pause.ui.json'), isTrue);
      expect(
        scope.activeWorkspace.value!.definition.id,
        UiEditorModule.workspaceId,
      );
      expect(scope.toolbarButtons.map((b) => b.id), contains('ui.open'));
      expect(
        scope.commands.bindings.where((b) => b.commandId == 'ui.open'),
        hasLength(1),
      );
    });

    test('the inspector rows the level still needs for text and buttons', () {
      final scope = scopeOver(_uiWorld()..initialize());
      for (final id in const [
        'uiTextStyle',
        'uiActions',
        'uiAnchor',
        'uiText',
        'uiStyleRole',
        'uiColorRole',
      ]) {
        expect(scope.fieldEditors.byTypeId(id), isNotNull, reason: id);
      }
      expect(scope.fieldEditors.inheritedColors, isNotEmpty);
    });

    test('its files are data, never taken for sprite atlases', () {
      final scope = scopeOver(_uiWorld()..initialize());
      expect(
        scope.dataFileSuffixes,
        containsAll(['.ui.json', '/screens.json', '.uitheme.json']),
      );
    });

    test('a Text prefab, and an icon for text in the tree', () {
      final scope = scopeOver(_uiWorld()..initialize());
      final prefab = scope.prefabs.byId('ui.text')!;
      final made = prefab.build(Offset.zero, const Size(160, 32));
      expect(made.whereType<TextComponent>(), hasLength(1));

      expect(
        scope.designers,
        isEmpty,
        reason: 'offering Text does not make it a Level Designer',
      );

      final text = scope.world.createEntityWithComponents([
        TextComponent(text: 'Hi'),
      ]);
      expect(
        scope.entityIcons.map((i) => i.of(text)).whereType<Object>(),
        isNotEmpty,
      );
    });
  });

  group('the game\'s screens in the editor', () {
    setUp(() {
      Directory(file('assets/ui')).createSync(recursive: true);
      final world = _uiWorld()..initialize();
      final hud = world.createEntityWithComponents([
        UiCanvasComponent(),
      ], name: 'Hud');
      File(
        file('assets/ui/hud.ui.json'),
      ).writeAsStringSync(jsonEncode(UiDocument.capture(hud, world).toJson()));
      File(file('assets/ui/screens.json')).writeAsStringSync(
        jsonEncode({
          'screens': [
            {'path': 'assets/ui/hud.ui.json', 'startOpen': true},
          ],
        }),
      );
    });
    test(
      'hidden while building the level; shown, fresh, during play',
      () async {
        final engine = Engine();
        addTearDown(engine.dispose);
        await engine.initialize();
        final scope = EditorScope(engine: engine, modules: [module]);
        addTearDown(scope.dispose);
        final layers = engine.layers;
        expect(layers.isEnabled(UiScreensLayer.layerId), isFalse);

        module.onPlayStateChanged(true);
        // It reads the list and the screens from disk first.
        for (var i = 0; i < 300; i++) {
          if (layers.isEnabled(UiScreensLayer.layerId)) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final installed = JustGameUi.of(engine);
        expect(installed, isNotNull, reason: 'installed on the first play');
        expect(layers.isEnabled(UiScreensLayer.layerId), isTrue);
        expect(installed!.screens.isOpen('Hud'), isTrue);

        installed.screens.hide('Hud');
        module.onPlayStateChanged(false);
        await Future<void>.delayed(Duration.zero);
        expect(layers.isEnabled(UiScreensLayer.layerId), isFalse);
        expect(
          installed.screens.isOpen('Hud'),
          isTrue,
          reason: 'the next play starts where the game would',
        );
      },
    );
  });

  group('screens left in a level', () {
    test('the Problems dock names each one', () {
      final world = _uiWorld()..initialize();
      oldScreen(world, 'Hud');
      world.createEntityWithComponents([TransformComponent()], name: 'Ground');

      final problems = UiChecks.level(world);
      expect(
        problems.where((p) => p.message.contains('Hud is inside the level')),
        hasLength(1),
      );
    });

    test('moved out: a file each, on the list, and gone from the level', () {
      final world = _uiWorld()..initialize();
      final scope = scopeOver(world);
      oldScreen(world, 'Hud');
      oldScreen(world, 'GameOver', showing: false);
      world.createEntityWithComponents([TransformComponent()], name: 'Ground');

      final moved = module.moveScreensOut(scope);

      expect(moved.map((m) => m.path), [
        'assets/ui/hud.ui.json',
        'assets/ui/game_over.ui.json',
      ]);
      final hud = readJson('assets/ui/hud.ui.json');
      expect((hud['entities'] as List).map((e) => (e as Map)['name']), [
        'Hud',
        'HudCoins',
      ]);
      expect(readJson('assets/ui/screens.json')['screens'], [
        {'path': 'assets/ui/hud.ui.json', 'startOpen': true},
        {'path': 'assets/ui/game_over.ui.json'},
      ]);
      expect(world.entities.map((e) => e.name), ['Ground']);
      expect(UiLevelScreens.of(world), isEmpty);

      // One step back puts the level as it was; the files stay.
      scope.history.undo();
      expect(
        world.entities.map((e) => e.name),
        containsAll(['Hud', 'HudCoins', 'GameOver', 'Ground']),
      );
      expect(File(file('assets/ui/hud.ui.json')).existsSync(), isTrue);
    });

    test('a name another screen has already is not taken over', () {
      final world = _uiWorld()..initialize();
      final scope = scopeOver(world);
      Directory(file('assets/ui')).createSync(recursive: true);
      final other = _uiWorld()..initialize();
      final existing = other.createEntityWithComponents([
        UiCanvasComponent(),
      ], name: 'Hud');
      File(file('assets/ui/hud.ui.json')).writeAsStringSync(
        jsonEncode(UiDocument.capture(existing, other).toJson()),
      );
      oldScreen(world, 'Hud');

      final moved = module.moveScreensOut(scope).single;

      expect(moved.name, 'Hud2');
      expect(moved.was, 'Hud');
      expect(moved.path, 'assets/ui/hud2.ui.json');
      final entities = readJson(moved.path)['entities'] as List;
      expect((entities.last as Map)['parentName'], 'Hud2');
      expect(
        readJson('assets/ui/hud.ui.json')['entities'],
        hasLength(1),
        reason: 'the one already there is left alone',
      );
    });

    test('a level with none has nothing to move', () {
      final world = _uiWorld()..initialize();
      final scope = scopeOver(world);
      world.createEntityWithComponents([TransformComponent()], name: 'Ground');

      expect(module.moveScreensOut(scope), isEmpty);
      expect(File(file('assets/ui/screens.json')).existsSync(), isFalse);
      expect(scope.history.canUndo.value, isFalse);
    });

    test('a screen list that does not read is left as it is', () {
      final world = _uiWorld()..initialize();
      final scope = scopeOver(world);
      oldScreen(world, 'Hud');
      final list = File(file('assets/ui/screens.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"screens": [');

      expect(module.moveScreensOut(scope), isEmpty);

      expect(list.readAsStringSync(), '{"screens": [');
      expect(File(file('assets/ui/hud.ui.json')).existsSync(), isFalse);
      expect(UiLevelScreens.of(world), hasLength(1), reason: 'still there');
      expect(scope.history.canUndo.value, isFalse);
    });
  });

  group('play-tests', () {
    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    void writeHud({required bool startOpen}) {
      Directory(file('assets/ui')).createSync(recursive: true);
      final world = _uiWorld()..initialize();
      final hud = world.createEntityWithComponents([
        UiCanvasComponent(),
      ], name: 'Hud');
      File(
        file('assets/ui/hud.ui.json'),
      ).writeAsStringSync(jsonEncode(UiDocument.capture(hud, world).toJson()));
      File(file('assets/ui/screens.json')).writeAsStringSync(
        jsonEncode({
          'screens': [
            {'path': 'assets/ui/hud.ui.json', 'startOpen': startOpen},
          ],
        }),
      );
    }

    test('the next one reads what changed on disk since the last', () async {
      writeHud(startOpen: true);
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      final scope = EditorScope(engine: engine, modules: [module]);
      addTearDown(scope.dispose);
      final layers = engine.layers;

      module.onPlayStateChanged(true);
      await until(() => layers.isEnabled(UiScreensLayer.layerId));
      final installed = JustGameUi.of(engine)!;
      expect(installed.screens.isOpen('Hud'), isTrue);
      module.onPlayStateChanged(false);
      await Future<void>.delayed(Duration.zero);

      // Changed while no play-test runs — say, its ▶ unticked in Screens.
      writeHud(startOpen: false);
      module.onPlayStateChanged(true);
      await until(() => layers.isEnabled(UiScreensLayer.layerId));

      expect(installed.screens.isOpen('Hud'), isFalse);
    });

    test('stopped before the files were read, nothing shows', () async {
      writeHud(startOpen: true);
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      final scope = EditorScope(engine: engine, modules: [module]);
      addTearDown(scope.dispose);

      module
        ..onPlayStateChanged(true)
        ..onPlayStateChanged(false);
      await until(() => JustGameUi.of(engine) != null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(JustGameUi.of(engine), isNotNull);
      expect(engine.layers.isEnabled(UiScreensLayer.layerId), isFalse);
    });
  });

  group('what it lends the interface', () {
    test('the level\'s text is drawn in the game\'s theme', () async {
      const path = 'assets/ui/default.uitheme.json';
      void writeTheme(double radius) => File(file(path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(
            UiTheme.fallback.copyWith(name: 'game', radius: radius).toJson(),
          ),
        );
      writeTheme(4);
      File(
        file(UiScreenManifest.defaultPath),
      ).writeAsStringSync(jsonEncode({'theme': path, 'screens': <Object>[]}));
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      final scope = EditorScope(engine: engine, modules: [module]);
      addTearDown(scope.dispose);
      final style = UiWorldStyle.of(engine.context);
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await until(() => style.theme != null);
      expect(style.theme?.name, 'game');

      // Saved again from the Theme tab: the level follows.
      writeTheme(9);
      module.onAssetChanged(path);
      await until(() => style.theme?.radius == 9);
      expect(style.theme?.radius, 9);
    });

    test('let go, themes are read from the bundle again', () async {
      const path = 'assets/ui/only_on_disk.uitheme.json';
      File(file(path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(UiTheme.fallback.copyWith(name: 'disk').toJson()),
        );
      final scope = EditorScope(
        world: _uiWorld()..initialize(),
        modules: [module],
      );
      expect((await UiThemes.load(path)).name, 'disk');

      scope.dispose();
      UiThemes.evict(path);

      expect(
        (await UiThemes.load(path)).name,
        isNot('disk'),
        reason: 'the bundle has no such theme: the fallback',
      );
    });

    test('a font changing keeps every other font', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = (await rootBundle.load(
        'fonts/MaterialIcons-Regular.otf',
      )).buffer.asUint8List();
      for (final name in const ['Alpha-Regular.otf', 'Beta-Regular.otf']) {
        File(file('assets/fonts/$name'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      }
      UiFonts.reset();
      addTearDown(() {
        UiFonts.reset();
        UiFonts.read = rootBundle.load;
      });
      scopeOver(_uiWorld()..initialize());
      Future<void> settle() async {
        for (var i = 0; i < 300 && UiFonts.families.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await settle();
      expect(UiFonts.families, ['Alpha', 'Beta']);

      module.onAssetChanged('assets/fonts/Beta-Regular.otf');
      await settle();

      expect(UiFonts.families, ['Alpha', 'Beta']);
    });
  });
}
