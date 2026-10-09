library;

import 'package:flutter/painting.dart';

import 'package:just_game_engine/just_game_engine.dart';
import '../logic/ui_bindings.dart';
import '../text/ui_rich_text.dart';
import '../text/ui_text_painter.dart';
import '../text/ui_text_style.dart';
import '../theme/ui_theme.dart';
import 'button_component.dart';
import 'text_component.dart';
import 'ui_component.dart';

/// Shared by the UI painters: draw order and visibility come from
/// [UIComponent].
mixin _UiLayering<T extends UIComponent> on ComponentPainter<T> {
  @override
  int layerOf(T component) => component.layer;

  @override
  bool isVisible(T component) => component.visible;
}

/// Draws a [TextComponent]: its style, its tags, and whatever moves.
class TextComponentPainter extends ComponentPainter<TextComponent>
    with _UiLayering<TextComponent> {
  const TextComponentPainter();

  /// One painter per component, since laying text out is what costs and a
  /// component's text rarely changes between frames.
  static final Expando<UiTextPainter> _painters = Expando('uiTextPainter');

  /// How a key becomes words. The game sets this once; without it a key
  /// shows as written, which is what an editor wants.
  static String Function(String key)? localise;

  /// The theme world text is drawn with.
  static UiTheme theme = UiTheme.fallback;

  @override
  void paint(Canvas canvas, Entity e, TextComponent text, RenderContext ctx) {
    final resolved = text.resolve(self: e, localise: localise);
    if (resolved.isEmpty) return;
    final shown = text.revealSpeed > 0
        ? resolved.take(text.revealed.floor())
        : resolved;
    if (shown.isEmpty) return;

    final painter = _painters[text] ??= UiTextPainter();
    painter
      ..set(
        text: shown,
        style: text.styleUnder(theme),
        layout: text.layoutFor(),
      )
      ..paint(
        canvas,
        Offset.zero,
        animation: UiTextAnimation(seconds: text.elapsed),
      );
  }
}

/// Draws a [ButtonComponent]: its fill in the theme's colour and its
/// state's tint, an optional border, and its label.
class ButtonComponentPainter extends ComponentPainter<ButtonComponent>
    with _UiLayering<ButtonComponent> {
  const ButtonComponentPainter();

  static final _fill = Paint();
  static final _border = Paint()..style = PaintingStyle.stroke;
  static final Expando<UiTextPainter> _labels = Expando('uiButtonLabel');

  @override
  void paint(Canvas canvas, Entity e, ButtonComponent b, RenderContext ctx) {
    final theme = TextComponentPainter.theme;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: b.size.width,
        height: b.size.height,
      ),
      Radius.circular(b.borderRadius),
    );
    final opacity = b.opacity;
    _fill.color = b.colorUnder(theme).withValues(alpha: opacity);
    canvas.drawRRect(rect, _fill);
    if (b.borderColor != null) {
      _border.color = b.borderColor!.withValues(alpha: opacity);
      canvas.drawRRect(rect, _border);
    }

    final label = UiRichText.parse(UiBindings.interpolate(b.label, self: e));
    if (label.isEmpty) return;
    final style = b.labelStyleUnder(theme);
    (_labels[b] ??= UiTextPainter())
      ..set(
        text: label,
        style: opacity < 1
            ? style.copyWith(
                color: (style.color ?? const Color(0xFFFFFFFF)).withValues(
                  alpha: opacity,
                ),
              )
            : style,
        layout: UiTextLayout(
          align: UiTextAlign.center,
          overflow: UiTextOverflow.ellipsis,
          maxWidth: b.size.width - 12,
          maxLines: 1,
        ),
      )
      ..paint(canvas, Offset.zero);
  }
}
