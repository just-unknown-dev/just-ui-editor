// Where themes come from: loading, caching, failing and evicting, per
// engine.

import 'dart:async';

import 'package:flutter/material.dart';
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

  group('a theme that will not load', () {
    testWidgets('is asked for once, not every frame', (tester) async {
      var asked = 0;
      UiThemes.of(engineContext).loader = (path) async {
        asked++;
        throw FlutterError('Unable to load $path');
      };
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud', theme: 'gone.uitheme.json');
      addUnder(world, hud, [UiTextComponent(text: 'Hi'), fillSlot()]);

      final key = await showLayer(tester, world);
      for (var i = 0; i < 10; i++) {
        key.currentState!.sync();
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(asked, 1);
      expect(UiThemes.of(engineContext).failed('gone.uitheme.json'), isTrue);
      UiThemes.of(engineContext).evict('gone.uitheme.json');
      expect(UiThemes.of(engineContext).failed('gone.uitheme.json'), isFalse);
    });

    test('a read that a reset or an evict overtook changes nothing', () async {
      for (final overtake in <void Function()>[
        UiThemes.of(engineContext).reset,
        () => UiThemes.of(engineContext).evict('slow.uitheme.json'),
      ]) {
        final pending = Completer<UiTheme>();
        UiThemes.of(engineContext).loader = (_) => pending.future;
        final read = UiThemes.of(engineContext).load('slow.uitheme.json');
        overtake();
        pending.completeError(FlutterError('gone'));
        await read;

        expect(UiThemes.of(engineContext).failed('slow.uitheme.json'), isFalse);
        UiThemes.of(engineContext).loader = (_) async =>
            UiTheme.fallback.copyWith(radius: 3);
        expect(
          (await UiThemes.of(engineContext).load('slow.uitheme.json')).radius,
          3,
        );
        UiThemes.of(engineContext).reset();
      }
    });
  });

  group('placing, routing and theming', () {
    test('a changed theme file refreshes what tools preview', () async {
      var colour = const Color(0xFF111111);
      UiThemes.of(engineContext).loader = (path) async => UiTheme(
        name: path,
        palette: UiPalette(primary: colour),
      );
      await UiThemes.of(engineContext).usePreview('assets/ui/a.uitheme.json');
      expect(
        UiThemes.of(engineContext).preview.palette.primary,
        const Color(0xFF111111),
      );

      colour = const Color(0xFF222222);
      UiThemes.of(engineContext).evict('assets/ui/a.uitheme.json');
      await Future<void>.delayed(Duration.zero);

      expect(
        UiThemes.of(engineContext).preview.palette.primary,
        const Color(0xFF222222),
      );
    });
  });
}
