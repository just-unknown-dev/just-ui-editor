// Rich text: the tags, effects, icons and links in a line of text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rich text', () {
    test('tags nest, and the plain text has none of them in it', () {
      final text = UiRichText.parse(
        'Press [b]Space[/b] for [color=#ffcc00]coins[/color]!',
      );
      expect(text.plain, 'Press Space for coins!');
      expect(text.spans.map((s) => s.text), [
        'Press ',
        'Space',
        ' for ',
        'coins',
        '!',
      ]);
      expect(text.spans[1].style.weight, FontWeight.w700);
      expect(text.spans[3].style.color, const Color(0xFFFFCC00));
      expect(text.spans[4].style.color, isNull, reason: 'the tag closed');
    });

    test('a tag inside a tag keeps both', () {
      final text = UiRichText.parse('[b]bold [i]and italic[/i][/b]');
      final inner = text.spans.last;
      expect(inner.style.weight, FontWeight.w700);
      expect(inner.style.italic, isTrue);
    });

    test('a tag nobody knows is left on screen, not swallowed', () {
      for (final source in [
        'a [nonsense] b',
        'a [b b',
        'a [/b] b',
        'a [color] b',
        'cost: [50] gold',
      ]) {
        final text = UiRichText.parse(source);
        expect(
          text.plain,
          source,
          reason: 'an author sees their mistake: $source',
        );
      }
    });

    test('colours are read as names or hex, of any length', () {
      Color? colorOf(String tag) =>
          UiRichText.parse('[color=$tag]x[/color]').spans.first.style.color;
      expect(colorOf('#f00'), const Color(0xFFFF0000));
      expect(colorOf('#00ff00'), const Color(0xFF00FF00));
      expect(colorOf('#8000ff00'), const Color(0x8000FF00));
      expect(colorOf('red'), isNotNull);
      expect(colorOf('wat'), isNull, reason: 'left as it was');
    });

    test('an icon is a span of its own and counts as one character', () {
      final text = UiRichText.parse('Got [icon=coin] x3');
      final icon = text.spans.firstWhere((s) => s.isIcon);
      expect(icon.icon, 'coin');
      expect(text.length, 'Got  x3'.length + 1);
    });

    test('effects and links ride on the spans under them', () {
      final text = UiRichText.parse('[wave]hi[/wave] [link=shop]buy[/link]');
      expect(text.spans.first.effect, UiTextEffect.wave);
      expect(text.spans.last.link, 'shop');
      expect(text.needsPainter, isTrue, reason: 'a wave must be painted');
      expect(
        UiRichText.parse('plain').needsPainter,
        isFalse,
        reason: 'plain text is left to Flutter, for a reader to read',
      );
    });

    test('a typewriter takes characters, not tags', () {
      final text = UiRichText.parse('[b]Hello[/b] world');
      expect(text.length, 'Hello world'.length);
      final part = text.take(7);
      expect(part.plain, 'Hello w');
      expect(part.spans.first.style.weight, FontWeight.w700);
      expect(text.take(0).isEmpty, isTrue);
      expect(text.take(999).length, text.length);
    });

    test('it becomes a TextSpan for the Flutter side', () {
      final span =
          UiRichText.parse('a [b]b[/b]').toTextSpan(const UiTextStyle(size: 14))
              as TextSpan;
      expect(span.children, hasLength(2));
      expect(
        (span.children!.last as TextSpan).style!.fontWeight,
        FontWeight.w700,
      );
      expect((span.children!.last as TextSpan).style!.fontSize, 14);
    });
  });

  group('the typewriter', () {
    test('never cuts a letter in half: an emoji is one letter', () {
      final text = UiRichText.parse('Hi 😀!');
      expect(text.length, 5, reason: 'H, i, space, the emoji, !');
      expect(text.take(4).plain, 'Hi 😀');
      expect(text.take(4).spans.single.text, 'Hi 😀');
      expect(text.take(3).plain, 'Hi ');
      // No lone surrogate anywhere in between.
      for (var n = 0; n <= text.length; n++) {
        final shown = text.take(n).plain;
        expect(
          shown.codeUnits
              .where((u) => u >= 0xD800 && u <= 0xDFFF)
              .length
              .isEven,
          isTrue,
          reason: 'take($n) is "$shown"',
        );
      }
    });

    test('a letter with its accent is one letter too', () {
      final text = UiRichText.parse('e\u0301!');
      expect(text.length, 2);
      expect(text.take(1).plain, 'e\u0301');
    });
  });
}
