// A theme: its palette, its text roles, its file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  group('theme', () {
    test('it round-trips, and a role nobody named still reads', () {
      const theme = UiTheme(
        name: 'arcade',
        palette: UiPalette(primary: Color(0xFF00FF88)),
        textStyles: {'body': UiTextStyle(family: 'Inter', size: 14)},
        radius: 12,
        spacing: 6,
        sounds: UiSounds(press: 'assets/sfx/click.wav'),
      );
      final back = UiTheme.parse(theme.encode());
      expect(back.name, 'arcade');
      expect(back.palette.primary, const Color(0xFF00FF88));
      expect(back.textStyles['body']!.size, 14);
      expect(back.radius, 12);
      expect(back.sounds.press, 'assets/sfx/click.wav');

      // A title takes the body's family but a title's size and weight.
      final title = back.textStyle('title');
      expect(title.family, 'Inter');
      expect(title.size, 32);
      expect(title.weight, FontWeight.w700);
    });

    test('it becomes a real ThemeData for the Flutter layer', () {
      const theme = UiTheme(
        palette: UiPalette(primary: Color(0xFF123456)),
        textStyles: {'body': UiTextStyle(family: 'Inter')},
      );
      final data = theme.toThemeData();
      expect(data.colorScheme.primary, const Color(0xFF123456));
      expect(data.textTheme.bodyMedium!.fontFamily, 'Inter');
      expect(data.textTheme.displayLarge!.fontSize, 32);
    });

    test('a theme that will not load is the fallback, not a crash', () async {
      UiThemes.of(engineContext).evict();
      UiThemes.of(engineContext).loader = (path) async =>
          throw StateError('no $path');
      addTearDown(UiThemes.of(engineContext).useBundle);
      expect(
        await UiThemes.of(engineContext).load('gone.uitheme.json'),
        UiThemes.of(engineContext).fallback,
      );
      expect(
        await UiThemes.of(engineContext).load(''),
        UiThemes.of(engineContext).fallback,
      );

      UiThemes.of(engineContext).loader = (path) async =>
          const UiTheme(name: 'ok');
      expect(
        (await UiThemes.of(engineContext).load('a.uitheme.json')).name,
        'ok',
      );
      expect(UiThemes.of(engineContext).cached('a.uitheme.json')!.name, 'ok');
      UiThemes.of(engineContext).evict('a.uitheme.json');
      expect(UiThemes.of(engineContext).cached('a.uitheme.json'), isNull);
    });
  });
}
