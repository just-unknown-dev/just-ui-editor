// Fonts loaded while the game runs: families from file names, folders read,
// loads a reset overtakes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';
import 'dart:async';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  group('fonts', () {
    test('files are grouped into families by their names', () {
      final families = UiFonts.familiesIn([
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/PressStart2P.ttf',
        'assets/sprites/player.png',
      ]);
      expect(families.keys, containsAll(['Inter', 'PressStart2P']));
      expect(families['Inter'], hasLength(2));
      expect(families.containsKey('player'), isFalse, reason: 'not a font');
    });

    test('a font that will not load leaves text in the fallback', () async {
      UiFonts.of(engineContext).read = (path) async =>
          throw StateError('no $path');
      await UiFonts.of(
        engineContext,
      ).ensureLoaded('Ghost', ['assets/fonts/Ghost.ttf']);
      expect(UiFonts.of(engineContext).isLoaded('Ghost'), isFalse);
      expect(UiFonts.of(engineContext).families, isEmpty);
      // And asking for nothing is not an error.
      await UiFonts.of(engineContext).ensureLoaded('', const []);
    });
  });

  group('fonts', () {
    test('every font in the folder is loaded', () async {
      final bundle = FontBundle([
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Pixel.otf',
        'assets/sprites/player.png',
        'assets/fontsy/Other.ttf',
      ]);

      await UiFonts.of(
        engineContext,
      ).loadFolder('assets/fonts', bundle: bundle);

      expect(bundle.read..sort(), [
        'assets/fonts/Inter-Bold.ttf',
        'assets/fonts/Inter-Regular.ttf',
        'assets/fonts/Pixel.otf',
      ]);
    });

    test('a bundle with no manifest loads nothing, quietly', () async {
      await UiFonts.of(
        engineContext,
      ).loadFolder('assets/fonts/', bundle: FontBundle(null));
    });
  });

  group('a reset while a font loads', () {
    test('the load it overtook leaves the new one alone', () async {
      final fonts = UiFonts.of(EngineContext());
      final first = Completer<ByteData>();
      final second = Completer<ByteData>();
      final one = fonts.ensureLoaded('Overtaken', const [
        'a.ttf',
      ], from: (_) => first.future);
      fonts.reset();
      final two = fonts.ensureLoaded('Overtaken', const [
        'a.ttf',
      ], from: (_) => second.future);
      expect(identical(two, one), isFalse, reason: 'a load of its own');

      first.complete(ByteData(0));
      await one;

      // Still the second load in flight: asked again, the same one, not a
      // third — the first did not take the second's place away.
      expect(
        identical(
          fonts.ensureLoaded('Overtaken', const [
            'a.ttf',
          ], from: (_) => second.future),
          two,
        ),
        isTrue,
      );
      second.complete(ByteData(0));
      await two;
    });

    test('each engine reads its fonts where it was told to', () {
      final editor = EngineContext();
      final game = EngineContext();
      Future<ByteData> project(String path) async => ByteData(0);
      UiFonts.of(editor).read = project;

      expect(UiFonts.of(editor).read, same(project));
      expect(UiFonts.of(game).read, isNot(same(project)));
    });
  });
}
