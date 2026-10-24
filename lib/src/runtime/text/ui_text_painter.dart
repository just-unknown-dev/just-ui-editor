/// Drawing text on the game's canvas: wrapping, fitting, outlines,
/// gradients, and letters that move.
///
/// Flutter's own `TextPainter` does the hard part — shaping and line
/// breaking — and this adds what a game wants on top of it. The screen-side
/// UI uses real widgets instead, except where an effect needs painting by
/// hand; both read the same [UiRichText], so they agree about what the text
/// says.
library;

import 'dart:math' as math;

// widgets.dart, not painting.dart, for the `characters` extension: a
// per-letter effect must step over emoji whole rather than splitting them.
import 'package:flutter/widgets.dart';

import 'ui_rich_text.dart';
import 'ui_text_style.dart';

/// How a piece of text is laid out, apart from how it looks.
class UiTextLayout {
  const UiTextLayout({
    this.align = UiTextAlign.center,
    this.overflow = UiTextOverflow.visible,
    this.maxWidth,
    this.maxHeight,
    this.maxLines,
    this.minSize = 8,
  });

  final UiTextAlign align;
  final UiTextOverflow overflow;

  /// Where text wraps. Null lets it run on.
  final double? maxWidth;

  /// What it must fit in vertically, for [UiTextOverflow.shrink].
  final double? maxHeight;

  final int? maxLines;

  /// How small shrinking may go before it gives up and lets text spill.
  final double minSize;

  UiTextLayout copyWith({
    UiTextAlign? align,
    UiTextOverflow? overflow,
    double? maxWidth,
    double? maxHeight,
    int? maxLines,
    double? minSize,
  }) => UiTextLayout(
    align: align ?? this.align,
    overflow: overflow ?? this.overflow,
    maxWidth: maxWidth ?? this.maxWidth,
    maxHeight: maxHeight ?? this.maxHeight,
    maxLines: maxLines ?? this.maxLines,
    minSize: minSize ?? this.minSize,
  );
}

/// What the moving effects need to know: how far into the game we are.
class UiTextAnimation {
  const UiTextAnimation({this.seconds = 0, this.amplitude = 3, this.speed = 1});

  static const UiTextAnimation still = UiTextAnimation();

  final double seconds;

  /// How far a wave rides, in pixels.
  final double amplitude;

  /// A multiple of the usual rate.
  final double speed;
}

/// Lays out and draws rich text on a canvas.
///
/// Made once and reused: laying text out is the expensive part, and this
/// only redoes it when something it was given actually changed. Whatever
/// it lays out — the text, its outline, its letters one by one — is kept
/// until then, so a frame that changes nothing only paints.
class UiTextPainter {
  UiTextPainter();

  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);

  /// The outline: the same text, stroked. Laid out with [_painter].
  TextPainter? _stroke;

  /// The gradient's paint, over the laid-out box.
  Paint? _gradient;

  /// Text that moves or changes colour, a letter at a time, made on the
  /// first paint after a layout.
  List<_Glyph>? _glyphs;

  UiRichText _text = UiRichText.empty;
  UiTextStyle _style = const UiTextStyle();
  UiTextLayout _layout = const UiTextLayout();
  TextScaler _scaler = TextScaler.noScaling;
  double _fittedSize = 0;
  bool _dirty = true;

  /// The size the text came out at once it had been fitted — what an
  /// inspector shows when auto-fit is on.
  double get fittedSize => _fittedSize;

  Size get size => _painter.size;

  /// Where the text will be drawn, relative to the point it is drawn at
  /// (which is its centre).
  Rect get bounds => Rect.fromCenter(
    center: Offset.zero,
    width: _painter.width,
    height: _painter.height,
  );

  /// What to draw and how. Nothing is laid out until [layout].
  ///
  /// [textScaler] is the player's text size, as a screen's `MediaQuery`
  /// gives it; world text is drawn as written.
  void set({
    required UiRichText text,
    required UiTextStyle style,
    UiTextLayout layout = const UiTextLayout(),
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (text.sameAs(_text) &&
        style == _style &&
        _sameLayout(layout) &&
        textScaler == _scaler) {
      return;
    }
    _text = text;
    _style = style;
    _layout = layout;
    _scaler = textScaler;
    _dirty = true;
  }

  bool _sameLayout(UiTextLayout other) =>
      other.align == _layout.align &&
      other.overflow == _layout.overflow &&
      other.maxWidth == _layout.maxWidth &&
      other.maxHeight == _layout.maxHeight &&
      other.maxLines == _layout.maxLines &&
      other.minSize == _layout.minSize;

  /// Measures the text, shrinking it if that is what was asked for.
  void layout() {
    if (!_dirty) return;
    _dirty = false;
    _forgetGlyphs();
    final wanted = _style.effectiveSize;
    _fittedSize = wanted;

    if (_layout.overflow != UiTextOverflow.shrink) {
      _layoutAt(wanted);
    } else {
      _shrink(wanted);
    }
    _layoutDecorations();
  }

  /// Comes down a point at a time until it fits. A binary search would do
  /// fewer layouts, but text jumps a whole line at a time as it shrinks, so
  /// stepping is what actually lands on the largest size that fits.
  void _shrink(double wanted) {
    for (var size = wanted; size >= _layout.minSize; size -= 1) {
      _layoutAt(size);
      if (_fits) {
        _fittedSize = size;
        return;
      }
    }
    _fittedSize = _layout.minSize;
    _layoutAt(_layout.minSize);
  }

  bool get _fits {
    final height = _layout.maxHeight;
    if (height != null && _painter.height > height + 0.5) return false;
    if (_painter.didExceedMaxLines) return false;
    final width = _layout.maxWidth;
    // A single word longer than its box cannot be broken, and would
    // otherwise shrink forever.
    if (width != null && _painter.width > width + 0.5) return false;
    return true;
  }

  void _layoutAt(double size) {
    _painter
      ..text = _text.toTextSpan(_style.copyWith(size: size))
      ..textAlign = _layout.align.flutter
      ..textScaler = _scaler
      ..maxLines = _layout.maxLines
      ..ellipsis = _layout.overflow == UiTextOverflow.ellipsis ? '…' : null
      ..layout(maxWidth: _layout.maxWidth ?? double.infinity);
  }

  /// The outline and the gradient, for the text as it was just laid out.
  void _layoutDecorations() {
    final resolved = _style.over(UiTextStyle.fallback);
    final outline = resolved.outline;
    _stroke?.dispose();
    _stroke = null;
    if (outline != null && outline.isVisible) {
      _stroke = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: _layout.align.flutter,
        textScaler: _scaler,
        maxLines: _layout.maxLines,
        ellipsis: _painter.ellipsis,
        text: _text.toTextSpan(
          _style.copyWith(size: _fittedSize),
          foreground: _strokePaint(outline),
        ),
      )..layout(maxWidth: _layout.maxWidth ?? double.infinity);
    }
    final colors = resolved.gradient;
    _gradient = colors != null && colors.length > 1
        ? (Paint()
            ..blendMode = BlendMode.srcIn
            ..shader = LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(Offset.zero & _painter.size))
        : null;
  }

  static Paint _strokePaint(UiTextOutline outline) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = outline.width
    ..strokeJoin = StrokeJoin.round
    ..color = outline.color;

  /// Draws the text centred on [at].
  ///
  /// [animation] moves what moves; leave it still and the text sits.
  void paint(
    Canvas canvas,
    Offset at, {
    UiTextAnimation animation = UiTextAnimation.still,
  }) {
    layout();
    final origin = at - Offset(_painter.width / 2, _painter.height / 2);

    if (_text.animates) {
      _paintGlyphs(canvas, origin, animation);
      return;
    }

    _stroke?.paint(canvas, origin);
    final gradient = _gradient;
    if (gradient != null) {
      // Colours swept across the whole block of text.
      canvas
        ..save()
        ..translate(origin.dx, origin.dy);
      final rect = Offset.zero & _painter.size;
      canvas.saveLayer(rect, Paint());
      _painter.paint(canvas, Offset.zero);
      canvas
        ..drawRect(rect, gradient)
        ..restore()
        ..restore();
      return;
    }
    _painter.paint(canvas, origin);
  }

  /// Text that moves or changes colour: each letter drawn on its own,
  /// where the laid-out text put it — so it wraps, aligns and breaks lines
  /// as the still text would. A gradient does not combine with these.
  void _paintGlyphs(Canvas canvas, Offset origin, UiTextAnimation animation) {
    final glyphs = _glyphs ??= _makeGlyphs();
    for (final glyph in glyphs) {
      final at = origin + glyph.offset + _offsetFor(glyph, animation);
      glyph.stroke?.paint(canvas, at);
      final color = _colorFor(glyph, animation);
      if (color != null) {
        glyph.painter
          ..text = TextSpan(
            text: glyph.text,
            style: glyph.style.copyWith(color: color).toTextStyle(),
          )
          ..layout();
      }
      glyph.painter.paint(canvas, at);
    }
  }

  List<_Glyph> _makeGlyphs() {
    final base = _style.copyWith(size: _fittedSize);
    final outline = _style.over(UiTextStyle.fallback).outline;
    final stroke = outline != null && outline.isVisible
        ? _strokePaint(outline)
        : null;
    final out = <_Glyph>[];
    var offset = 0;
    var index = 0;

    void add(
      String text,
      InlineSpan run,
      InlineSpan? stroked,
      _Glyph Function(
        TextPainter painter,
        TextPainter? strokePainter,
        Offset at,
      )
      make,
    ) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + text.length),
      );
      offset += text.length;
      if (boxes.isEmpty) return; // cut off by maxLines or an ellipsis
      final box = boxes.first;
      TextPainter laid(InlineSpan span) => TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
      )..layout();
      out.add(
        make(
          laid(run),
          stroked == null ? null : laid(stroked),
          Offset(box.left, box.top),
        ),
      );
    }

    for (final span in _text.spans) {
      final style = span.style.over(base);
      if (span.isIcon) {
        final run = UiIcons.spanFor(span.icon!, style, widgets: false);
        final text = run is TextSpan ? run.text ?? '' : '';
        if (run != null && text.isNotEmpty) {
          final at = index;
          add(
            text,
            run,
            stroke == null
                ? null
                : UiIcons.spanFor(
                    span.icon!,
                    style,
                    widgets: false,
                    foreground: stroke,
                  ),
            (painter, strokePainter, where) => _Glyph(
              text: text,
              style: style,
              effect: span.effect,
              index: at,
              offset: where,
              painter: painter,
              stroke: strokePainter,
              recolours: false,
            ),
          );
        }
        index++;
        continue;
      }
      for (final char in span.text.characters) {
        final at = index++;
        if (char == '\n') {
          offset += char.length;
          continue;
        }
        add(
          char,
          TextSpan(text: char, style: style.toTextStyle()),
          stroke == null
              ? null
              : TextSpan(
                  text: char,
                  style: style.toTextStyle().copyWith(
                    foreground: stroke,
                    shadows: const [],
                  ),
                ),
          (painter, strokePainter, where) => _Glyph(
            text: char,
            style: style,
            effect: span.effect,
            index: at,
            offset: where,
            painter: painter,
            stroke: strokePainter,
            recolours: true,
          ),
        );
      }
    }
    return out;
  }

  void _forgetGlyphs() {
    for (final glyph in _glyphs ?? const <_Glyph>[]) {
      glyph.dispose();
    }
    _glyphs = null;
  }

  Offset _offsetFor(_Glyph glyph, UiTextAnimation a) {
    final t = a.seconds * a.speed;
    final index = glyph.index;
    return switch (glyph.effect) {
      UiTextEffect.wave => Offset(
        0,
        math.sin(t * 6 + index * 0.6) * a.amplitude,
      ),
      // Deterministic jitter: the same letter at the same moment always
      // lands in the same place, so a screenshot test can hold it still.
      UiTextEffect.shake => Offset(
        math.sin(t * 43 + index * 12.9) * a.amplitude * 0.4,
        math.cos(t * 37 + index * 7.3) * a.amplitude * 0.4,
      ),
      _ => Offset.zero,
    };
  }

  Color? _colorFor(_Glyph glyph, UiTextAnimation a) {
    if (!glyph.recolours) return null;
    final t = a.seconds * a.speed;
    final index = glyph.index;
    switch (glyph.effect) {
      case UiTextEffect.rainbow:
        return HSVColor.fromAHSV(
          1,
          (t * 120 + index * 40) % 360,
          0.85,
          1,
        ).toColor();
      case UiTextEffect.pulse:
        final base = glyph.style.color ?? const Color(0xFFFFFFFF);
        final alpha = 0.55 + 0.45 * math.sin(t * 4 + index * 0.2);
        return base.withValues(alpha: alpha.clamp(0.0, 1.0));
      default:
        return null;
    }
  }

  /// Lets go of what was laid out. The painter is not used again.
  void dispose() {
    _forgetGlyphs();
    _stroke?.dispose();
    _stroke = null;
    _painter.dispose();
  }
}

/// One letter of animated text, laid out on its own.
class _Glyph {
  _Glyph({
    required this.text,
    required this.style,
    required this.effect,
    required this.index,
    required this.offset,
    required this.painter,
    required this.stroke,
    required this.recolours,
  });

  final String text;
  final UiTextStyle style;
  final UiTextEffect effect;

  /// Its place in the text, letters and icons counted, for the effects.
  final int index;

  /// Where the laid-out text put it, from the text's top-left.
  final Offset offset;

  final TextPainter painter;
  final TextPainter? stroke;

  /// Whether a colour effect may relayout it (an icon keeps its own look).
  final bool recolours;

  void dispose() {
    painter.dispose();
    stroke?.dispose();
  }
}
