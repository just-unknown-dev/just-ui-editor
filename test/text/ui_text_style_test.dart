// A text style: what it sets, what it inherits, and what survives a save.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text style', () {
    test('everything set survives a save — the whole point of it', () {
      const style = UiTextStyle(
        family: 'PressStart2P',
        size: 22,
        weight: FontWeight.w700,
        italic: true,
        color: Color(0xFFFFCC00),
        letterSpacing: 1.5,
        lineHeight: 1.2,
        outline: UiTextOutline(color: Color(0xFF102030), width: 3),
        shadow: UiTextShadow(
          color: Color(0x80000000),
          offset: Offset(2, 3),
          blur: 4,
        ),
      );
      final back = UiTextStyle.fromJson(style.toJson());
      expect(back, style, reason: 'nothing is lost on the way to a file');
      expect(back.toTextStyle().fontSize, 22);
      expect(back.toTextStyle().fontStyle, FontStyle.italic);
      expect(back.toTextStyle().shadows, hasLength(1));
    });

    test('what is not set is not written, and falls back when read', () {
      const style = UiTextStyle(size: 12);
      expect(style.toJson().keys, ['size']);
      expect(style.color, isNull);
      // Unset fields come from the fallback only when it is drawn.
      expect(style.toTextStyle().color, const Color(0xFFFFFFFF));
      expect(style.toTextStyle().fontSize, 12);
      expect(const UiTextStyle().isEmpty, isTrue);
      expect(UiTextStyle.fromJson(const {}), const UiTextStyle());
    });

    test('one style layers over another, and a field can be taken back', () {
      const theme = UiTextStyle(family: 'Inter', size: 16, color: Colors.white);
      const own = UiTextStyle(size: 24);
      final merged = own.over(theme);
      expect(merged.family, 'Inter', reason: "the theme's, untouched");
      expect(merged.size, 24, reason: 'its own wins');
      expect(merged.color, Colors.white);
      expect(merged.without('size').over(theme).size, 16);
    });

    test('a gradient keeps a colour for anything that ignores it', () {
      const style = UiTextStyle(gradient: [Colors.red, Colors.blue]);
      expect(style.toTextStyle().color, Colors.red);
      expect(UiTextStyle.fromJson(style.toJson()).gradient, hasLength(2));
    });

    test('a weight from a file lands on one Flutter knows', () {
      final style = UiTextStyle.fromJson(const {'weight': 640});
      expect(style.weight, FontWeight.w600);
    });
  });
}
