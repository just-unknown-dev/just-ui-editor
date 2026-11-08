// Bindings: what a text reads from the game, formatted, per engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  group('bindings', () {
    test('a name reads what the game says, and an unknown one shows', () {
      var coins = 7;
      UiBindings.of(engineContext).register('coins', () => coins);
      expect(
        UiBindings.of(engineContext).interpolate('Coins: {coins}'),
        'Coins: 7',
      );
      coins = 8;
      expect(
        UiBindings.of(engineContext).interpolate('Coins: {coins}'),
        'Coins: 8',
      );
      expect(
        UiBindings.of(engineContext).interpolate('{nope}'),
        '{nope}',
        reason: 'a missing binding is visible, not blank',
      );
      expect(UiBindings.namesIn('{a} and {b:n0}'), ['a', 'b']);
    });

    test('formats: clocks, decimals, thousands, percentages', () {
      UiBindings.of(engineContext).register('t', () => 91.4);
      UiBindings.of(engineContext).register('n', () => 1234567.0);
      UiBindings.of(engineContext).register('f', () => 0.256);
      expect(UiBindings.of(engineContext).interpolate('{t:mm:ss}'), '01:31');
      expect(UiBindings.of(engineContext).interpolate('{t:m:ss.S}'), '1:31.4');
      expect(UiBindings.format(3725.0, 'hh:mm:ss'), '01:02:05');
      expect(UiBindings.of(engineContext).interpolate('{n:n0}'), '1,234,567');
      expect(UiBindings.of(engineContext).interpolate('{f:0.00}'), '0.26');
      expect(UiBindings.of(engineContext).interpolate('{f:%0}'), '26%');
      expect(UiBindings.format(4.0), '4', reason: 'no stray .0');
      expect(UiBindings.format(null), '');
    });

    test('{{ writes a brace, and an unclosed one is text', () {
      expect(UiBindings.of(engineContext).interpolate('{{coins}'), '{coins}');
      expect(UiBindings.of(engineContext).interpolate('a {b'), 'a {b');
    });

    test('self.* reads the entity the text belongs to', () {
      final world = uiWorld(engineContext);
      final hero = world.createEntity(name: 'Hero');
      expect(
        UiBindings.of(engineContext).interpolate('{self.name}', self: hero),
        'Hero',
      );
      expect(
        UiBindings.of(engineContext).interpolate('{self.name}'),
        '',
        reason: 'no entity, nothing to read',
      );
      expect(UiBindings.of(engineContext).names, contains('self.name'));
    });

    test('a number for a bar, from anything that is one', () {
      UiBindings.of(engineContext).register('hp', () => 30);
      UiBindings.of(engineContext).register('max', () => 40);
      UiBindings.of(engineContext).register('word', () => 'nope');
      expect(UiBindings.of(engineContext).readNumber('hp'), 30);
      expect(
        UiBindings.of(engineContext).fraction('hp', 'max'),
        closeTo(0.75, 1e-9),
      );
      expect(UiBindings.of(engineContext).readNumber('word'), isNull);
      expect(
        UiBindings.of(engineContext).fraction('hp', 'word'),
        0,
        reason: 'no maximum',
      );
    });
  });

  group('numbers that are not numbers', () {
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
      final world = uiWorld(engineContext)..addSystem(UiTextSystem());
      UiBindings.of(engineContext).register('ratio', () => 1 / 0);
      final text = UiTextComponent(text: 'x{ratio}');
      world.createEntityWithComponents([text]);

      world.update(1 / 60);

      expect(text.resolve(UiBindings.of(engineContext)).plain, 'xInfinity');
    });
  });

  group('per engine', () {
    test("one engine's bindings are not another's", () {
      final game = EngineContext();
      final preview = EngineContext();
      UiBindings.of(game).register('coins', () => 3);

      expect(UiBindings.of(game).has('coins'), isTrue);
      expect(UiBindings.of(preview).has('coins'), isFalse);
      expect(UiBindings.of(preview).interpolate('{coins}'), '{coins}');
    });

    test('self.name and self.id are there from the start, and after clear', () {
      final bindings = UiBindings.of(EngineContext());
      expect(bindings.names, containsAll(['self.id', 'self.name']));
      bindings
        ..register('coins', () => 1)
        ..clear();
      expect(bindings.names, ['self.id', 'self.name']);
    });

    test("samples stand in only in the worlds shown with them", () {
      final context = EngineContext();
      final bindings = UiBindings.of(context)..register('coins', () => 3);
      final previewed = World(context: context);
      final game = World(context: context);
      final inPreview = previewed.createEntity(name: 'Coins');
      final inGame = game.createEntity(name: 'Coins');
      var samples = <String, Object?>{'coins': 12, 'gems': 5};
      bindings.showSamples(previewed, () => samples);

      expect(bindings.read('coins', self: inPreview), 12);
      expect(bindings.read('coins', self: inGame), 3, reason: "the game's");
      expect(
        bindings.interpolate('{gems}', self: inPreview),
        '5',
        reason: 'a sampled name reads though the game offers none',
      );
      expect(bindings.interpolate('{gems}', self: inGame), '{gems}');

      samples = {'coins': 99};
      expect(bindings.read('coins', self: inPreview), 99, reason: 'asked anew');

      bindings.hideSamples(previewed);
      expect(bindings.read('coins', self: inPreview), 3);
    });
  });
}
