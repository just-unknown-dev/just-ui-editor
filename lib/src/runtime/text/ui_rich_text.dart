/// Text with tags in it: `Press [b]Space[/b] for [color=#ffcc00]coins[/color]`.
///
/// One parse, two readers — the canvas painter draws the spans itself, and
/// the Flutter layer turns them into a `TextSpan` — so world text and screen
/// text always say the same thing.
library;

import 'package:flutter/gestures.dart' show GestureRecognizer;
import 'package:flutter/widgets.dart';

import 'ui_text_style.dart';

/// What a span does beyond sitting still.
enum UiTextEffect {
  none,

  /// Rides up and down.
  wave,

  /// Jitters in place.
  shake,

  /// Cycles through hues.
  rainbow,

  /// Fades in and out.
  pulse;

  bool get movesGlyphs => this == wave || this == shake;
}

/// A run of text that shares a look.
class UiTextSpan {
  const UiTextSpan({
    required this.text,
    this.style = const UiTextStyle(),
    this.effect = UiTextEffect.none,
    this.icon,
    this.link,
  });

  /// The characters. Empty for an icon.
  final String text;

  /// What this run says about itself; anything it leaves out comes from the
  /// paragraph's style.
  final UiTextStyle style;

  final UiTextEffect effect;

  /// An image drawn in the line instead of text — `[icon=coin]`. The name is
  /// resolved by whoever draws it.
  final String? icon;

  /// An action name this run runs when it is clicked — `[link=shop]`.
  final String? link;

  bool get isIcon => icon != null;

  /// How many characters this span counts for when text is revealed a
  /// letter at a time. An icon is one.
  int get length => isIcon ? 1 : text.length;

  UiTextSpan copyWith({String? text, UiTextStyle? style}) => UiTextSpan(
    text: text ?? this.text,
    style: style ?? this.style,
    effect: effect,
    icon: icon,
    link: link,
  );

  @override
  bool operator ==(Object other) =>
      other is UiTextSpan &&
      other.text == text &&
      other.style == style &&
      other.effect == effect &&
      other.icon == icon &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, style, effect, icon, link);

  @override
  String toString() =>
      isIcon ? 'UiTextSpan(icon: $icon)' : 'UiTextSpan("$text")';
}

/// A parsed piece of rich text.
class UiRichText {
  const UiRichText(this.spans, {this.plain = ''});

  static const UiRichText empty = UiRichText([]);

  final List<UiTextSpan> spans;

  /// The text with every tag taken out — what a reader hears, what a
  /// character count counts, and what a plain `Text` shows.
  final String plain;

  bool get isEmpty => spans.isEmpty;

  /// Whether anything here needs painting by hand rather than by Flutter:
  /// a moving effect, a gradient or an outline.
  bool get needsPainter => spans.any(
    (s) =>
        s.effect != UiTextEffect.none ||
        s.style.gradient != null ||
        (s.style.outline?.isVisible ?? false),
  );

  /// Whether anything here changes from frame to frame: a wave, a shake, a
  /// rainbow or a pulse.
  bool get animates => spans.any((s) => s.effect != UiTextEffect.none);

  /// Whether [other] says the same thing in the same way, span for span —
  /// not just the same words.
  bool sameAs(UiRichText other) {
    if (identical(this, other)) return true;
    if (plain != other.plain || spans.length != other.spans.length) {
      return false;
    }
    for (var i = 0; i < spans.length; i++) {
      if (spans[i] != other.spans[i]) return false;
    }
    return true;
  }

  /// How many characters there are in all, icons counting as one.
  int get length {
    var total = 0;
    for (final s in spans) {
      total += s.length;
    }
    return total;
  }

  /// The first [count] characters of this text, spans and all — what a
  /// typewriter shows part-way through.
  UiRichText take(int count) {
    if (count >= length) return this;
    if (count <= 0) return empty;
    final out = <UiTextSpan>[];
    var left = count;
    for (final span in spans) {
      if (left <= 0) break;
      if (span.length <= left) {
        out.add(span);
        left -= span.length;
      } else {
        out.add(span.copyWith(text: span.text.substring(0, left)));
        left = 0;
      }
    }
    return UiRichText(
      out,
      plain: plain.substring(0, count.clamp(0, plain.length)),
    );
  }

  /// A `TextSpan` for Flutter to lay out. [base] is the style underneath.
  ///
  /// An `[icon=…]` becomes what [iconBuilder] makes of it, or else what
  /// [UiIcons] has under that name — a glyph anywhere, a widget only where
  /// [widgets] is true (a `Text`; never a canvas painter, which cannot draw
  /// one). [foreground] paints every run with one paint — an outline's
  /// stroke. [recognizerFor] gives a `[link=…]` run something to tap.
  InlineSpan toTextSpan(
    UiTextStyle base, {
    InlineSpan Function(String name, UiTextStyle style)? iconBuilder,
    bool widgets = false,
    Paint? foreground,
    GestureRecognizer? Function(UiTextSpan span)? recognizerFor,
  }) {
    TextStyle look(UiTextStyle style) {
      final flutter = style.toTextStyle();
      return foreground == null
          ? flutter
          : flutter.copyWith(foreground: foreground, shadows: const []);
    }

    return TextSpan(
      children: [
        for (final span in spans)
          if (span.isIcon)
            iconBuilder?.call(span.icon!, span.style.over(base)) ??
                UiIcons.spanFor(
                  span.icon!,
                  span.style.over(base),
                  widgets: widgets && foreground == null,
                  foreground: foreground,
                ) ??
                const TextSpan(text: '')
          else
            _run(span, look(span.style.over(base)), recognizerFor),
      ],
    );
  }

  static TextSpan _run(
    UiTextSpan span,
    TextStyle style,
    GestureRecognizer? Function(UiTextSpan span)? recognizerFor,
  ) {
    final recognizer = span.link == null ? null : recognizerFor?.call(span);
    return TextSpan(
      text: span.text,
      style: style,
      recognizer: recognizer,
      mouseCursor: recognizer == null ? null : SystemMouseCursors.click,
    );
  }

  /// Reads [source] and its tags.
  ///
  /// Unknown or unclosed tags are left as they were written rather than
  /// swallowed: an author sees their mistake on screen instead of watching
  /// text disappear. A `[` that starts nothing is just a bracket.
  factory UiRichText.parse(String source) {
    if (source.isEmpty) return empty;
    if (!source.contains('[')) {
      return UiRichText([UiTextSpan(text: source)], plain: source);
    }

    final spans = <UiTextSpan>[];
    final plain = StringBuffer();
    final buffer = StringBuffer();
    // What the tags we are inside say, innermost last.
    final stack = <_Tag>[];

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        UiTextSpan(
          text: buffer.toString(),
          style: _styleOf(stack),
          effect: _effectOf(stack),
          link: _linkOf(stack),
        ),
      );
      buffer.clear();
    }

    var i = 0;
    while (i < source.length) {
      final char = source[i];
      if (char != '[') {
        buffer.write(char);
        plain.write(char);
        i++;
        continue;
      }
      final close = source.indexOf(']', i);
      if (close < 0) {
        // No closing bracket at all: the rest is text.
        buffer.write(source.substring(i));
        plain.write(source.substring(i));
        break;
      }
      final body = source.substring(i + 1, close);
      final tag = _Tag.parse(body);
      if (tag == null) {
        // Not a tag we know: show it as written.
        buffer.write(source.substring(i, close + 1));
        plain.write(source.substring(i, close + 1));
        i = close + 1;
        continue;
      }
      if (tag.isClosing) {
        // Close the innermost tag of that name. One that closes nothing is
        // a mistake, and is shown as written rather than swallowed.
        final at = stack.lastIndexWhere((t) => t.name == tag.name);
        if (at < 0) {
          buffer.write(source.substring(i, close + 1));
          plain.write(source.substring(i, close + 1));
          i = close + 1;
          continue;
        }
        flush();
        stack.removeAt(at);
        i = close + 1;
        continue;
      }
      flush();
      if (tag.name == 'icon') {
        spans.add(
          UiTextSpan(
            text: '',
            icon: tag.value ?? '',
            style: _styleOf(stack),
            effect: _effectOf(stack),
            link: _linkOf(stack),
          ),
        );
        plain.write('\u{fffc}'); // the object-replacement character
      } else if (tag.isSelfClosing) {
        // A tag that opens and shuts itself, like [br].
        if (tag.name == 'br') {
          buffer.write('\n');
          plain.write('\n');
        }
      } else {
        stack.add(tag);
      }
      i = close + 1;
    }
    flush();
    return UiRichText(spans, plain: plain.toString());
  }

  static UiTextStyle _styleOf(List<_Tag> stack) {
    var style = const UiTextStyle();
    for (final tag in stack) {
      final own = tag.style;
      if (own != null) style = own.over(style);
    }
    return style;
  }

  static UiTextEffect _effectOf(List<_Tag> stack) {
    for (var i = stack.length - 1; i >= 0; i--) {
      final effect = stack[i].effect;
      if (effect != null) return effect;
    }
    return UiTextEffect.none;
  }

  static String? _linkOf(List<_Tag> stack) {
    for (var i = stack.length - 1; i >= 0; i--) {
      if (stack[i].name == 'link') return stack[i].value ?? '';
    }
    return null;
  }

  /// A colour as a tag or a field writes it: `#rgb`, `#rrggbb`,
  /// `#aarrggbb`, or one of a few names (`red`, `white`…). Null when it
  /// makes no sense.
  static Color? parseColor(String? raw) => _Tag.parseColor(raw);

  /// [color] as [parseColor] reads it back: `#aarrggbb`.
  static String writeColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

  /// The tags that may be written, for an editor to offer.
  static const List<String> tagNames = [
    'b',
    'i',
    'color',
    'size',
    'font',
    'icon',
    'wave',
    'shake',
    'rainbow',
    'pulse',
    'link',
    'br',
  ];

  @override
  String toString() => 'UiRichText("$plain", ${spans.length} spans)';
}

/// One `[tag]`, `[tag=value]` or `[/tag]`.
class _Tag {
  const _Tag(this.name, this.value, {this.isClosing = false});

  final String name;
  final String? value;
  final bool isClosing;

  bool get isSelfClosing => name == 'br';

  static const Set<String> _known = {
    'b',
    'i',
    'color',
    'size',
    'font',
    'icon',
    'wave',
    'shake',
    'rainbow',
    'pulse',
    'link',
    'br',
  };

  /// [body] is what is between the brackets; null when it is not a tag.
  static _Tag? parse(String body) {
    if (body.isEmpty) return null;
    final closing = body.startsWith('/');
    final rest = closing ? body.substring(1) : body;
    final equals = rest.indexOf('=');
    final name = (equals < 0 ? rest : rest.substring(0, equals))
        .trim()
        .toLowerCase();
    if (!_known.contains(name)) return null;
    final value = equals < 0 ? null : rest.substring(equals + 1).trim();
    // A closing tag carries nothing, and an icon must say which.
    if (closing && value != null) return null;
    if (!closing && (name == 'icon' || name == 'color') && value == null) {
      return null;
    }
    return _Tag(name, value, isClosing: closing);
  }

  /// What this tag says about how its text looks.
  UiTextStyle? get style => switch (name) {
    'b' => const UiTextStyle(weight: FontWeight.w700),
    'i' => const UiTextStyle(italic: true),
    'color' => UiTextStyle(color: parseColor(value)),
    'size' => UiTextStyle(size: double.tryParse(value ?? '')),
    'font' => UiTextStyle(family: value),
    _ => null,
  };

  UiTextEffect? get effect => switch (name) {
    'wave' => UiTextEffect.wave,
    'shake' => UiTextEffect.shake,
    'rainbow' => UiTextEffect.rainbow,
    'pulse' => UiTextEffect.pulse,
    _ => null,
  };

  /// `#rgb`, `#rrggbb`, `#aarrggbb`, or one of a few names. Null when it
  /// makes no sense, which leaves the colour as it was.
  static Color? parseColor(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final named = _names[raw.toLowerCase()];
    if (named != null) return named;
    var hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  static const Map<String, Color> _names = {
    'white': Color(0xFFFFFFFF),
    'black': Color(0xFF000000),
    'red': Color(0xFFE53935),
    'green': Color(0xFF43A047),
    'blue': Color(0xFF1E88E5),
    'yellow': Color(0xFFFDD835),
    'orange': Color(0xFFFB8C00),
    'purple': Color(0xFF8E24AA),
    'grey': Color(0xFF9E9E9E),
    'gray': Color(0xFF9E9E9E),
  };
}

/// Draws one icon in a line of text, for a screen: an image, a widget of
/// the game's own. [size] is the font size of the text around it.
typedef UiIconWidgetBuilder = Widget Function(double size);

/// What `[icon=name]` draws.
///
/// A glyph from an icon font ([register]) works everywhere text does — in
/// a screen and on the game's canvas — since it is just another letter. A
/// widget ([registerWidget]) can be anything, a coin's sprite included,
/// but only a screen can show one: in world text it draws nothing.
///
/// ```dart
/// UiIcons.register('heart', Icons.favorite);
/// UiIcons.registerWidget('coin', (size) => Image.asset('assets/coin.png',
///     width: size, height: size));
/// ```
///
/// A name nobody registered draws nothing, and the editor's Problems dock
/// is where that shows.
abstract final class UiIcons {
  static final Map<String, IconData> _glyphs = {};
  static final Map<String, UiIconWidgetBuilder> _widgets = {};

  /// Makes `[icon=name]` draw [icon], in the colour and size of the text
  /// around it.
  static void register(String name, IconData icon) {
    _widgets.remove(name);
    _glyphs[name] = icon;
  }

  /// Makes `[icon=name]` draw what [build] makes, in a screen.
  static void registerWidget(String name, UiIconWidgetBuilder build) {
    _glyphs.remove(name);
    _widgets[name] = build;
  }

  static void unregister(String name) {
    _glyphs.remove(name);
    _widgets.remove(name);
  }

  static bool has(String name) =>
      _glyphs.containsKey(name) || _widgets.containsKey(name);

  /// Every name registered, for an editor to offer.
  static List<String> get names => [..._glyphs.keys, ..._widgets.keys]..sort();

  static void clear() {
    _glyphs.clear();
    _widgets.clear();
  }

  /// The run [name] draws as, in [style]; null when nothing can be drawn
  /// here — no such icon, or a widget where [widgets] is false.
  static InlineSpan? spanFor(
    String name,
    UiTextStyle style, {
    bool widgets = true,
    Paint? foreground,
  }) {
    final glyph = _glyphs[name];
    if (glyph != null) {
      final look = style.toTextStyle().copyWith(
        fontFamily: glyph.fontFamily,
        package: glyph.fontPackage,
        fontFamilyFallback: glyph.fontFamilyFallback,
      );
      return TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: foreground == null
            ? look
            : look.copyWith(foreground: foreground, shadows: const []),
      );
    }
    final build = _widgets[name];
    if (build == null || !widgets) return null;
    final size = style.over(UiTextStyle.fallback).effectiveSize;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox.square(dimension: size, child: build(size)),
    );
  }
}
