// What the 0.1.0-alpha.1 release audit of the runtime found, kept from coming
// back: files that will not read, screens that close as they reset, names
// two screens share, numbers that are not numbers, and the rest.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed.
World _uiWorld() => World()
  ..context.install(JustGameUi.extension)
  ..initialize();

/// A canvas called [name], 400×300, with no transition to wait for.
Entity _canvas(
  World world,
  String name, {
  bool isScreen = false,
  bool modal = false,
  bool visible = true,
  String theme = '',
  int sortOrder = 0,
}) => world.createEntityWithComponents([
  UiCanvasComponent(
    designSize: const Size(400, 300),
    safeArea: false,
    isScreen: isScreen,
    modal: modal,
    visible: visible,
    theme: theme,
    sortOrder: sortOrder,
    transition: UiTransition.none,
  ),
], name: name);

/// An entity made of [components], hung under [parent].
Entity _under(
  World world,
  Entity parent,
  List<Component> components, {
  String? name,
}) {
  final entity = world.createEntityWithComponents(components, name: name);
  UiDocument.link(entity, parent);
  return entity;
}

/// A slot that fills its parent.
UiSlotComponent _fill() =>
    UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch);

/// [world]'s canvas called [name], as a document.
UiDocument _documentOf(World world, String name) =>
    UiDocument.capture(world.findEntityByName(name)!, world);

/// A screen file: a canvas called [name] with a card and a title.
UiDocument _screenDocument(
  String name, {
  bool isScreen = true,
  bool modal = false,
  UiTransition transition = UiTransition.fade,
}) {
  final world = _uiWorld();
  final canvas = world.createEntityWithComponents([
    UiCanvasComponent(
      designSize: const Size(400, 300),
      isScreen: isScreen,
      modal: modal,
      transition: transition,
    ),
  ], name: name);
  final card = _under(world, canvas, [
    UiPanelComponent(),
    UiLayoutComponent(),
    UiSlotComponent(size: const Size(300, 200)),
  ], name: '${name}Card');
  _under(world, card, [
    TextComponent(text: '$name title'),
    UiSlotComponent(),
  ], name: '${name}Title');
  return _documentOf(world, name);
}

/// The interface over nothing, at 400×300.
Future<GlobalKey<UiLayerState>> _show(
  WidgetTester tester,
  World world, {
  UiActionHost? host,
  bool handlesBack = false,
  String Function(String key)? localise,
  Size size = const Size(400, 300),
}) async {
  final key = GlobalKey<UiLayerState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: UiLayer(
            key: key,
            world: world,
            actionHost: host,
            handlesBack: handlesBack,
            localise: localise,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

/// Text drawn by the canvas painter rather than a `Text`, by its words.
Finder _painted(String words) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == words,
);

/// A component nobody registered, by its saved form.
const Map<String, dynamic> _nobodys = {
  'type': 'NobodysComponent',
  'fields': <String, Object>{},
};

/// A screen whose third entity names [_nobodys].
UiDocument _broken(String name) => UiDocument(
  name: name,
  entities: [
    {
      'name': name,
      'parentName': null,
      'components': [
        {
          'type': 'UiCanvasComponent',
          'fields': {'isScreen': true, 'modal': true},
        },
      ],
    },
    {
      'name': '${name}Card',
      'parentName': name,
      'components': [
        {'type': 'UiPanelComponent', 'fields': <String, Object>{}},
      ],
    },
    {
      'name': '${name}Odd',
      'parentName': '${name}Card',
      'components': [_nobodys],
    },
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
    UiIcons.clear();
  });
  tearDown(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
    UiIcons.clear();
    UiThemes.reset();
    UiFonts.reset();
  });

  group('a screen that will not read (UR-01)', () {
    test('leaves nothing behind in the world', () {
      final world = _uiWorld();
      final before = world.entityCount;

      expect(
        () => _broken('Pause').instantiate(world),
        throwsA(isA<UnknownComponentTypeException>()),
      );
      expect(world.entityCount, before, reason: 'not half a screen');
    });

    test('is left out of the game: nothing open, nothing in the way', () async {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      await screens.loadManifest(
        UiScreenManifest(screens: const [UiScreenEntry(path: 'pause.ui.json')]),
        read: (_) async => jsonEncode(_broken('Pause').toJson()),
      );

      expect(screens.names, isEmpty);
      expect(screens.navigator.isEmpty, isTrue);
      expect(screens.world.query(const [UiCanvasComponent]), isEmpty);
    });

    test('a replacement that will not read leaves the old one standing', () {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      screens.add(_screenDocument('Pause'));

      expect(() => screens.add(_broken('Pause')), throwsA(anything));
      expect(screens.canvasOf('Pause'), isNotNull);
    });
  });

  group('a file of the wrong shape says so (UR-09)', () {
    test('a screen file', () {
      expect(
        () => UiDocument.fromJson({'format': '1', 'entities': []}),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': {'a': 1},
        }),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': [
            {'name': 5, 'components': []},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => UiDocument.fromJson({
          'entities': [
            {'name': 'Hud', 'components': {}},
          ],
        }),
        throwsFormatException,
      );
    });

    test('a screen list', () {
      expect(
        () => UiScreenManifest.fromJson({'theme': 5}),
        throwsFormatException,
      );
      expect(
        () => UiScreenManifest.fromJson({'screens': {}}),
        throwsFormatException,
      );
      expect(() => UiScreenManifest.parse('[1, 2]'), throwsFormatException);
    });

    test('a game with no screen list runs with no screens', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final plugin = await JustGameUi.install(
        engine,
        read: (path) async => throw FlutterError('Unable to load $path'),
        fonts: null,
      );

      expect(plugin.screens.names, isEmpty);
    });

    test('nor does one that will not read stop it', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();

      final plugin = await JustGameUi.install(
        engine,
        read: (path) async => '{"screens": "hud.ui.json"}',
        fonts: null,
      );

      expect(plugin.screens.names, isEmpty);
    });
  });

  group('numbers that are not numbers (UR-10)', () {
    test('are written, never thrown', () {
      expect(UiBindings.format(double.infinity), 'Infinity');
      expect(UiBindings.format(double.nan), 'NaN');
      expect(UiBindings.format(double.infinity, 'mm:ss'), 'Infinity');
      expect(UiBindings.format(double.nan, 'n0'), 'NaN');
      expect(UiBindings.format(-double.infinity, '%'), '-Infinity');
      expect(UiBindings.format(3.0), '3');
      expect(UiBindings.format(1e22), '1e+22');
    });

    test('more decimals than a number has are as many as it can', () {
      expect(UiBindings.format(1.5, 'n25'), 1.5.toStringAsFixed(20));
      expect(UiBindings.format(0.5, '%30'), '${50.0.toStringAsFixed(20)}%');
    });

    test('a binding that reads one does not stop the frame', () {
      final world = _uiWorld()..addSystem(UiSystem());
      UiBindings.register('ratio', () => 1 / 0);
      final text = TextComponent(text: 'x{ratio}');
      world.createEntityWithComponents([text]);

      world.update(1 / 60);

      expect(text.resolve().plain, 'xInfinity');
    });
  });

  group('names two screens share (UR-08)', () {
    test('a screen opens by its name, whatever else is called that', () {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      // Loaded first, so the oldest entity called "Pause" — a button.
      _under(world, hud, [
        ButtonComponent(label: 'II'),
        UiSlotComponent(),
      ], name: 'Pause');
      _canvas(world, 'Pause', isScreen: true, visible: false);
      final navigator = UiNavigator(world);

      navigator.push('Pause');

      expect(navigator.top?.name, 'Pause');
      expect(navigator.top?.getComponent<UiCanvasComponent>()?.visible, isTrue);
    });

    test('an element is looked for in the screen on top first', () {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final hudTitle = _under(world, hud, [
        TextComponent(text: 'Hud'),
        UiSlotComponent(),
      ], name: 'Title');
      final settings = _canvas(world, 'Settings', isScreen: true);
      final settingsTitle = _under(world, settings, [
        TextComponent(text: 'Settings'),
        UiSlotComponent(),
      ], name: 'Title');
      final navigator = UiNavigator(world)..adopt();

      navigator.show('Title', false);

      expect(settingsTitle.getComponent<UiSlotComponent>()!.visible, isFalse);
      expect(hudTitle.getComponent<UiSlotComponent>()!.visible, isTrue);
    });

    test('a timeline is looked for in the acting screen first', () {
      final world = _uiWorld();
      final a = _canvas(world, 'A');
      final first = TimelinePlayerComponent();
      _under(world, a, [first], name: 'Door');
      final b = _canvas(world, 'B');
      final second = TimelinePlayerComponent();
      _under(world, b, [second], name: 'Door');
      final button = _under(world, b, [ButtonComponent()], name: 'Open');

      expect(
        UiActions.findBelow(
          world,
          UiActions.rootOf(button),
          'Door',
        )?.getComponent<TimelinePlayerComponent>(),
        same(second),
      );
    });
  });

  group('the stack of screens (UR-19)', () {
    test('a layer pushed is shown, not stacked', () {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud', visible: false);
      final navigator = UiNavigator(world);

      navigator.push('Hud');

      expect(hud.getComponent<UiCanvasComponent>()!.visible, isTrue);
      expect(navigator.isEmpty, isTrue);
    });

    test('keeps the order screens were opened in, by sort order', () {
      final world = _uiWorld();
      for (final name in ['A', 'B', 'C', 'D']) {
        _canvas(
          world,
          name,
          isScreen: true,
          visible: false,
          sortOrder: name == 'C' ? 5 : 0,
        );
      }
      final navigator = UiNavigator(world);

      navigator
        ..push('B')
        ..push('A')
        ..push('C')
        ..push('D');
      for (var i = 0; i < 3; i++) {
        navigator.adopt();
      }

      expect([for (final e in navigator.stack) e.name], ['B', 'A', 'D', 'C']);
    });
  });

  group('a custom widget (UR-11)', () {
    testWidgets('acts through the layer it is in', (tester) async {
      final pushed = <String>[];
      World? gameWorld;
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (context) {
            gameWorld = context.gameWorld;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.run(
                const UiActionList([UiAction('ui.push', 'Shop')]),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      );
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [UiCustomComponent(widgetId: 'probe'), _fill()]);
      final game = _uiWorld();
      final key = GlobalKey<UiLayerState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: UiLayer(
                key: key,
                world: world,
                gameWorld: game,
                actionHost: UiActionHost(pushScreen: pushed.add),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();

      expect(pushed, ['Shop'], reason: 'the layer\'s host, not the game\'s');
      expect(gameWorld, same(game));
    });
  });

  group('a label in the current language (UR-12)', () {
    testWidgets('on a button, a toggle and a field', (tester) async {
      String tr(String key) => switch (key) {
        'menu.resume' => 'Resume',
        'menu.music' => 'Music',
        'menu.name' => 'Your name',
        _ => key,
      };
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final column = _under(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column),
        _fill(),
      ]);
      _under(world, column, [
        ButtonComponent(label: '@menu.resume'),
        UiSlotComponent(),
      ]);
      _under(world, column, [
        UiToggleComponent(label: '@menu.music'),
        UiSlotComponent(size: const Size(200, 40)),
      ]);
      _under(world, column, [
        UiTextFieldComponent(hint: '@menu.name'),
        UiSlotComponent(size: const Size(200, 48)),
      ]);

      await _show(tester, world, localise: tr);

      expect(find.text('Resume', findRichText: true), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.textContaining('@menu'), findsNothing);
    });
  });

  group('text on a screen (UR-13)', () {
    testWidgets('that moves is painted, and moves on its own', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [TextComponent(text: '[wave]Wavy[/wave]'), _fill()]);

      await _show(tester, world);

      expect(find.text('Wavy', findRichText: true), findsNothing);
      expect(_painted('Wavy'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it ticks');
    });

    testWidgets('that shrinks, or has an outline, is painted too', (
      tester,
    ) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [
        TextComponent(text: 'Fits', overflow: UiTextOverflow.shrink),
        _fill(),
      ]);
      _under(world, hud, [
        TextComponent(
          text: 'Edged',
          style: const UiTextStyle(outline: UiTextOutline()),
        ),
        _fill(),
      ]);

      await _show(tester, world);

      expect(_painted('Fits'), findsOneWidget);
      expect(_painted('Edged'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an icon is drawn in the line', (tester) async {
      UiIcons.register('heart', Icons.favorite);
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [TextComponent(text: 'Lives [icon=heart]'), _fill()]);

      await _show(tester, world);

      final glyph = String.fromCharCode(Icons.favorite.codePoint);
      expect(find.text('Lives $glyph', findRichText: true), findsOneWidget);
    });

    testWidgets('a link runs its action when tapped', (tester) async {
      final ran = <String>[];
      UiActions.register('shop', (_) => ran.add('shop'));
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [
        TextComponent(text: '[link=shop]Shop[/link]'),
        _fill(),
      ]);

      await _show(tester, world);
      await tester.tap(find.text('Shop', findRichText: true));
      await tester.pump();

      expect(ran, ['shop']);
    });

    test('a link names a built-in with its argument, or the game\'s own', () {
      expect(UiActions.linkAction('shop'), const UiAction('custom:shop'));
      expect(
        UiActions.linkAction('ui.push Credits'),
        const UiAction('ui.push', 'Credits'),
      );
    });

    test('a colour that changes is a change, though the words are not', () {
      final red = UiRichText.parse('[color=red]Go[/color]');
      final green = UiRichText.parse('[color=green]Go[/color]');

      expect(red.sameAs(green), isFalse);
      expect(red.sameAs(UiRichText.parse('[color=red]Go[/color]')), isTrue);
    });

    test('letters that move wrap as still text does', () {
      final painter = UiTextPainter()
        ..set(
          text: UiRichText.parse('[wave]one two three four five[/wave]'),
          style: const UiTextStyle(size: 16),
          layout: const UiTextLayout(maxWidth: 60),
        );
      addTearDown(painter.dispose);
      final recorder = ui.PictureRecorder();

      painter.paint(
        Canvas(recorder),
        const Offset(100, 100),
        animation: const UiTextAnimation(seconds: 1),
      );
      recorder.endRecording().dispose();

      expect(painter.size.height, greaterThan(16 * 2));
    });
  });

  group('typing in a screen', () {
    testWidgets('the arrows move the caret, not the focus', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final column = _under(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column),
        _fill(),
      ]);
      _under(world, column, [
        UiTextFieldComponent(),
        UiSlotComponent(size: const Size(200, 48)),
      ]);
      _under(world, column, [
        ButtonComponent(label: 'Next'),
        UiSlotComponent(),
      ]);

      await _show(tester, world);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.selection.baseOffset, 2);
      expect(field.focusNode.hasFocus, isTrue);
    });
  });

  group('what a screen is given that does not fit (UR-16)', () {
    testWidgets('a slider the wrong way round', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [
        UiSliderComponent(value: 3, min: 10, max: 0),
        UiSlotComponent(size: const Size(300, 40)),
      ]);

      await _show(tester, world);

      expect(tester.takeException(), isNull);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect((slider.min, slider.max, slider.value), (0, 10, 3));
    });

    testWidgets('a share of the room where there is none to share', (
      tester,
    ) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final wrap = _under(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.wrap),
        _fill(),
      ]);
      _under(world, wrap, [
        TextComponent(text: 'Grows'),
        UiSlotComponent(flex: 1),
      ]);
      _under(world, wrap, [UiSpacerComponent(expand: true), UiSlotComponent()]);

      await _show(tester, world);

      expect(tester.takeException(), isNull);
      expect(find.byType(Expanded), findsNothing);
    });

    testWidgets('a choice given twice', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [
        UiDropdownComponent(value: 'Easy', options: ['Easy', 'Hard', 'Easy']),
        UiSlotComponent(size: const Size(200, 48)),
      ]);

      await _show(tester, world);

      expect(tester.takeException(), isNull);
    });

    testWidgets('no room at all', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [TextComponent(text: 'Hi'), _fill()]);

      await _show(tester, world, size: Size.zero);

      expect(tester.takeException(), isNull, reason: 'UR-23');
    });
  });

  group('a theme that will not load (UR-07)', () {
    testWidgets('is asked for once, not every frame', (tester) async {
      var asked = 0;
      UiThemes.loader = (path) async {
        asked++;
        throw FlutterError('Unable to load $path');
      };
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud', theme: 'gone.uitheme.json');
      _under(world, hud, [TextComponent(text: 'Hi'), _fill()]);

      final key = await _show(tester, world);
      for (var i = 0; i < 10; i++) {
        key.currentState!.sync();
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(asked, 1);
      expect(UiThemes.failed('gone.uitheme.json'), isTrue);
      UiThemes.evict('gone.uitheme.json');
      expect(UiThemes.failed('gone.uitheme.json'), isFalse);
    });

    test('a read that a reset or an evict overtook changes nothing', () async {
      for (final overtake in <void Function()>[
        UiThemes.reset,
        () => UiThemes.evict('slow.uitheme.json'),
      ]) {
        final pending = Completer<UiTheme>();
        UiThemes.loader = (_) => pending.future;
        final read = UiThemes.load('slow.uitheme.json');
        overtake();
        pending.completeError(FlutterError('gone'));
        await read;

        expect(UiThemes.failed('slow.uitheme.json'), isFalse);
        UiThemes.loader = (_) async => UiTheme.fallback.copyWith(radius: 3);
        expect((await UiThemes.load('slow.uitheme.json')).radius, 3);
        UiThemes.reset();
      }
    });
  });

  group('a slot changed on its own', () {
    // A timeline sliding a panel in, or code growing a bar: only the
    // child's slot changes, and nothing else tells the layer to rebuild.
    testWidgets('moves and sizes what it places, at the next sync', (
      tester,
    ) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.topLeft,
        pivot: Offset.zero,
        offset: const Offset(10, 10),
        size: const Size(100, 40),
      );
      _under(world, hud, [UiPanelComponent(), slot], name: 'Card');
      final key = await _show(tester, world);
      final card = find.byType(DecoratedBox).last;
      final before = tester.getRect(card);

      slot
        ..offset = const Offset(110, 60)
        ..size = const Size(150, 50);
      key.currentState!.sync();
      await tester.pump();

      final after = tester.getRect(card);
      expect(after.topLeft - before.topLeft, const Offset(100, 50));
      expect(after.size, const Size(150, 50));
    });

    testWidgets('resizes what a column lays out', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      final column = _under(world, hud, [
        UiLayoutComponent(kind: UiLayoutKind.column, tight: true),
        _fill(),
      ]);
      final slot = UiSlotComponent(size: const Size(100, 40));
      _under(world, column, [UiPanelComponent(), slot]);
      final key = await _show(tester, world);
      final bar = find.byType(DecoratedBox).last;
      expect(tester.getSize(bar), const Size(100, 40));

      slot.size = const Size(220, 60);
      key.currentState!.sync();
      await tester.pump();

      expect(tester.getSize(bar), const Size(220, 60));
    });
  });

  group('the system\'s back (UR-15)', () {
    testWidgets('closes the screen on top, not the game', (tester) async {
      final world = _uiWorld();
      final pause = _canvas(world, 'Pause', isScreen: true, modal: true);
      _under(world, pause, [TextComponent(text: 'Paused'), _fill()]);

      final key = await _show(tester, world, handlesBack: true);
      await tester.pump();
      expect(key.currentState!.navigator.isEmpty, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump();
      key.currentState!.sync();
      await tester.pump();

      expect(key.currentState!.navigator.isEmpty, isTrue);
      expect(find.byType(UiLayer), findsOneWidget, reason: 'still there');
    });
  });

  group('a world button (UR-17, UR-18, UR-24)', () {
    late World world;
    late UiPointerSystem system;
    late ButtonComponent button;
    late TransformComponent transform;
    late List<String> sounds;
    late List<String> pressed;

    setUp(() {
      sounds = [];
      pressed = [];
      UiActions.register('hit', (_) => pressed.add('hit'));
      world = _uiWorld();
      system = UiPointerSystem(onSound: sounds.add);
      world.addSystem(system);
      transform = TransformComponent(position: Vector3(100, 100, 0));
      button = ButtonComponent(
        size: const Size(40, 20),
        onPressed: const UiActionList([UiAction('custom:hit')]),
      );
      world.createEntityWithComponents([transform, button], name: 'B');
    });

    void at(double x, double y, {bool down = false}) =>
        system.pointer = UiPointer(position: Offset(x, y), isDown: down);

    test('is pressed where it is drawn, scaled', () {
      transform.scale.setValues(2, 2, 1);

      at(135, 100);
      world.update(1 / 60);

      expect(button.state, UiInteractionState.hovered);
    });

    test('is pressed where it is drawn, turned', () {
      transform.angle = math.pi / 2;

      at(100, 118); // past its height unturned, inside its width turned
      world.update(1 / 60);
      expect(button.state, UiInteractionState.hovered);

      at(118, 100); // inside unturned, outside turned
      world.update(1 / 60);
      expect(button.state, UiInteractionState.normal);
    });

    test('a tap between two frames still presses it', () {
      at(100, 100, down: true);
      at(100, 100);
      world.update(1 / 60);

      expect(pressed, ['hit']);
    });

    test('presses made while the world waits can be let go', () {
      at(100, 100, down: true);
      at(100, 100);
      system.discardPending();
      world.update(1 / 60);

      expect(pressed, isEmpty);
    });

    test('sounds as the theme says', () {
      UiWorldStyle.of(world.context).theme = const UiTheme(
        sounds: UiSounds(hover: 'over.wav', press: 'down.wav'),
      );

      at(100, 100);
      world.update(1 / 60);
      at(100, 100, down: true);
      world.update(1 / 60);

      expect(sounds, ['over.wav', 'down.wav']);
    });
  });

  group('a press on a screen (UR-25)', () {
    test('is kept for one frame, then let go', () {
      final screens = UiScreens();
      addTearDown(screens.dispose);
      final hud = _canvas(screens.world, 'Hud');
      final button = ButtonComponent(
        onPressed: const UiActionList([UiAction('none')]),
      );
      _under(screens.world, hud, [button, UiSlotComponent()]);

      button.press(UiActionContext(world: screens.world));
      screens.update(1 / 60);
      expect(button.wasPressed, isTrue);
      screens.update(1 / 60);
      expect(button.wasPressed, isFalse);
    });
  });

  group('what is saved (UR-26)', () {
    final definitions = EngineContext(
      extensions: const [JustGameUi.extension],
    ).definitions;

    T roundTrip<T extends Component>(String type, T component) {
      final definition = definitions.definitionByType(type)!;
      final json = jsonDecode(jsonEncode(definition.encode(component)));
      return definition.decode((json as Map).cast<String, dynamic>()) as T;
    }

    test('a panel\'s gradient', () {
      final back = roundTrip(
        'UiPanelComponent',
        UiPanelComponent(
          gradient: const [Color(0xFFFF0000), Color(0xFF0000FF)],
        ),
      );
      expect(back.gradient, const [Color(0xFFFF0000), Color(0xFF0000FF)]);

      final written = definitions.definitionByType('UiPanelComponent')!.decode({
        'type': 'UiPanelComponent',
        'fields': {
          'gradient': ['#f00', 'nonsense', '#ff00ff00'],
        },
      });
      expect((written as UiPanelComponent).gradient, const [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
      ]);
    });

    test('a world text\'s layer, and a button\'s layer and switch', () {
      final text = roundTrip(
        'TextComponent',
        TextComponent(text: 'Sign', layer: 3),
      );
      expect(text.layer, 3);
      final button = roundTrip(
        'ButtonComponent',
        ButtonComponent(layer: 2, enabled: false),
      );
      expect((button.layer, button.enabled), (2, false));
    });

    testWidgets('a panel\'s picture is drawn', (tester) async {
      final world = _uiWorld();
      final hud = _canvas(world, 'Hud');
      _under(world, hud, [UiPanelComponent(image: 'assets/none.png'), _fill()]);

      await _show(tester, world);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration?)?.image != null,
        ),
        findsOneWidget,
      );
    });
  });

  group('taking screens out of a scene (UR-29)', () {
    test('two parents of one name keep their own children', () {
      Map<String, dynamic> entity(
        String name,
        String? parent,
        List<Map<String, dynamic>> components,
      ) => {'name': name, 'parentName': parent, 'components': components};
      final canvas = [
        {
          'type': 'UiCanvasComponent',
          'fields': {'isScreen': true},
        },
      ];
      final slot = [
        {'type': 'UiSlotComponent', 'fields': <String, Object>{}},
      ];
      final extraction = UiSceneExtractor.extract({
        'version': 5,
        'entities': [
          entity('A', null, canvas),
          entity('Panel', 'A', slot),
          entity('OnlyA', 'Panel', slot),
          entity('B', null, canvas),
          entity('Panel', 'B', slot),
          entity('OnlyB', 'Panel', slot),
        ],
      });

      final names = {
        for (final doc in extraction.documents)
          doc.name: [for (final e in doc.entities) e['name']],
      };
      expect(names['A'], ['A', 'Panel', 'OnlyA']);
      expect(names['B'], ['B', 'Panel', 'OnlyB']);
    });
  });

  group('installed again, and taken out (UR-28)', () {
    test('takes the new callbacks, and gives the theme back', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      UiThemes.loader = (path) async => const UiTheme(name: 'mine');
      final list = UiScreenManifest(theme: 'mine.uitheme.json');

      await JustGameUi.install(engine, screens: list, fonts: null);
      String second(String key) => 'second';
      await JustGameUi.install(
        engine,
        screens: list,
        localise: second,
        fonts: null,
      );

      expect(engine.world.getSystem<UiSystem>()!.localise, same(second));
      expect(UiWorldStyle.of(engine.context).localise, same(second));
      expect(UiWorldStyle.of(engine.context).resolvedTheme.name, 'mine');

      JustGameUi.uninstall(engine);

      expect(UiThemes.fallback, same(UiTheme.fallback));
      expect(UiWorldStyle.of(engine.context).localise, isNull);
    });

    test('a game\'s own self.name is kept', () {
      UiBindings.registerForEntity('name', (_) => 'mine');
      registerUiSystems(_uiWorld());
      final entity = _uiWorld().createEntity(name: 'Entity');

      expect(UiBindings.read('self.name', self: entity), 'mine');
    });
  });

  group('fonts (UR-14)', () {
    test('every font in the folder is loaded', () async {
      final bundle = _FontBundle([
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Pixel.otf',
        'assets/sprites/player.png',
        'assets/fontsy/Other.ttf',
      ]);

      await UiFonts.loadFolder('assets/fonts', bundle: bundle);

      expect(bundle.read..sort(), [
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Pixel.otf',
      ]);
    });

    test('a bundle with no manifest loads nothing, quietly', () async {
      await UiFonts.loadFolder('assets/fonts/', bundle: _FontBundle(null));
    });
  });

  group('installed in a game (UR-03, UR-04, UR-05, UR-06)', () {
    late Engine engine;
    late Map<String, String> files;
    var tick = 0;
    var probeBuilds = 0;

    setUp(() async {
      tick = 0;
      probeBuilds = 0;
      UiBindings.register('tick', () => tick);
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (_) {
            probeBuilds++;
            return const SizedBox.expand();
          },
        ),
      );
      final hudWorld = _uiWorld();
      final hud = _canvas(hudWorld, 'Hud');
      _under(hudWorld, hud, [
        TextComponent(text: 'Tick {tick}'),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          size: const Size(200, 40),
          pivot: Offset.zero,
        ),
      ]);
      _under(hudWorld, hud, [
        UiCustomComponent(widgetId: 'probe'),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          size: const Size(10, 10),
          pivot: Offset.zero,
          offset: const Offset(300, 0),
        ),
      ]);
      _under(hudWorld, hud, [
        ButtonComponent(
          label: 'Hud',
          onPressed: const UiActionList([UiAction('custom:hudPressed')]),
        ),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          anchor: UiAnchor.center,
          size: const Size(80, 40),
        ),
      ], name: 'HudButton');
      files = {
        'screens.json': jsonEncode({
          'screens': [
            {'path': 'hud.ui.json', 'startOpen': true},
            {'path': 'pause.ui.json'},
          ],
        }),
        'hud.ui.json': jsonEncode(_documentOf(hudWorld, 'Hud').toJson()),
        'pause.ui.json': jsonEncode(
          _screenDocument('Pause', modal: true).toJson(),
        ),
      };
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      await JustGameUi.install(
        engine,
        manifest: 'screens.json',
        read: (path) async => files[path]!,
        localise: (key) => key == 'sign' ? 'Welcome' : key,
        fonts: null,
      );
    });

    testWidgets('restarting with a screen open throws nothing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      final screens = JustGameUi.of(engine)!.screens;
      screens.push('Pause');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Pause title', findRichText: true), findsOneWidget);

      // What the template's Restart does from the pause menu.
      screens.reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(screens.isOpen('Pause'), isFalse);
    });

    testWidgets('a reading that changes rebuilds its text, nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      expect(find.text('Tick 0', findRichText: true), findsOneWidget);
      final before = probeBuilds;

      for (var i = 1; i <= 5; i++) {
        tick = i;
        engine.plugins.update(1 / 60);
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('Tick 5', findRichText: true), findsOneWidget);
      expect(probeBuilds, before, reason: 'the rest of the screen sat still');
    });

    test('the level\'s text gets the game\'s language and theme', () {
      final look = UiWorldStyle.of(engine.context);
      expect(look.localise?.call('sign'), 'Welcome');
      expect(look.resolvedTheme, same(UiThemes.fallback));

      final text = TextComponent(text: '@sign');
      final sign = engine.world.createEntityWithComponents([
        TransformComponent(),
        text,
      ]);
      engine.world.update(1 / 60);
      final recorder = ui.PictureRecorder();
      const TextComponentPainter().paint(
        Canvas(recorder),
        sign,
        text,
        RenderContext(world: engine.world, size: const Size(400, 300)),
      );
      recorder.endRecording().dispose();

      expect(
        text.resolve(self: sign, localise: look.localise).plain,
        'Welcome',
      );
    });

    testWidgets('a world button hears what the screens let through', (
      tester,
    ) async {
      final pressed = <String>[];
      UiActions.register('worldPressed', (_) => pressed.add('world'));
      UiActions.register('hudPressed', (_) => pressed.add('hud'));
      // A world button as big as the whole view: wherever the camera is.
      engine.world.createEntityWithComponents([
        TransformComponent(),
        ButtonComponent(
          size: const Size(100000, 100000),
          onPressed: const UiActionList([UiAction('custom:worldPressed')]),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: GameWidget(engine: engine, showFPS: false)),
      );
      await tester.pump();
      final view = tester.getRect(find.byType(GameWidget));
      final hud = tester.getCenter(find.text('Hud', findRichText: true));

      // Away from the HUD's button: the world's is pressed.
      await tester.tapAt(view.topLeft + const Offset(20, 200));
      engine.world.update(1 / 60);
      expect(pressed, ['world']);

      // On the HUD's button: only it.
      pressed.clear();
      await tester.tapAt(hud);
      await tester.pump();
      engine.world.update(1 / 60);
      expect(pressed, ['hud']);

      // Under a modal screen: nothing in the world.
      pressed.clear();
      JustGameUi.of(engine)!.screens.push('Pause');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tapAt(view.topLeft + const Offset(20, 200));
      await tester.pump();
      engine.world.update(1 / 60);
      expect(pressed, isEmpty);
    });
  });
}

/// A bundle holding [assets] in its manifest, recording what is read.
class _FontBundle extends CachingAssetBundle {
  _FontBundle(this.assets);

  /// Null: no manifest at all.
  final List<String>? assets;
  final List<String> read = [];

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final listed = assets;
      if (listed == null) throw FlutterError('No manifest');
      return const StandardMessageCodec().encodeMessage({
        for (final asset in listed)
          asset: [
            {'asset': asset},
          ],
      })!;
    }
    read.add(key);
    // Not a font: the family stays the fallback, quietly.
    return ByteData(0);
  }
}
