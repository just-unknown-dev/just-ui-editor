/// How world-space text and buttons are drawn on the game's canvas.
library;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import '../controls/controls.dart';
import '../text/text.dart';
import '../theme/theme.dart';

/// Shared by the UI painters: draw order and visibility come from
/// [UiElementComponent].
mixin _UiLayering<T extends UiElementComponent> on ComponentPainter<T> {
  @override
  int layerOf(T component) => component.layer;

  @override
  bool isVisible(T component) => component.visible;
}

/// Draws a [UiTextComponent]: its style, its tags, and whatever moves.
class UiTextComponentPainter extends ComponentPainter<UiTextComponent>
    with _UiLayering<UiTextComponent> {
  const UiTextComponentPainter();

  @override
  void paint(Canvas canvas, Entity e, UiTextComponent text, RenderContext ctx) {
    // The theme and the language are the engine's (see [UiWorldStyle]),
    // which `JustGameUi.install` fills in.
    final context = ctx.world.context;
    final look = UiWorldStyle.of(context);
    final resolved = text.resolve(
      UiBindings.of(context),
      self: e,
      localize: look.localize,
    );
    if (resolved.isEmpty) return;
    final shown = text.revealSpeed > 0
        ? resolved.take(text.revealed.floor())
        : resolved;
    if (shown.isEmpty) return;

    // One painter per component, since laying text out is what costs and a
    // component's text rarely changes between frames. The component owns
    // it, and disposes it when it goes.
    final painter = text.painter ??= UiTextPainter();
    painter
      ..set(
        text: shown,
        style: text.styleUnder(look.resolvedTheme),
        layout: text.layoutFor(),
        icons: UiIcons.of(context),
      )
      ..paint(
        canvas,
        Offset.zero,
        animation: UiTextAnimation(seconds: text.elapsed),
      );
  }
}

/// Draws a [UiButtonComponent]: its fill in the theme's colour and its
/// state's tint, an optional border, and its label.
class UiButtonComponentPainter extends ComponentPainter<UiButtonComponent>
    with _UiLayering<UiButtonComponent> {
  const UiButtonComponentPainter();

  static final _fill = Paint();
  static final _border = Paint()..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Entity e, UiButtonComponent b, RenderContext ctx) {
    final context = ctx.world.context;
    final look = UiWorldStyle.of(context);
    final theme = look.resolvedTheme;
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

    final source = UiBindings.of(
      context,
    ).resolveText(b.label, self: e, localize: look.localize);
    // Parsed again only when the words change.
    final read = b.labelRead;
    final label = read != null && read.$1 == source
        ? read.$2
        : (b.labelRead = (source, UiRichText.parse(source))).$2;
    if (label.isEmpty) return;
    final style = b.labelStyleUnder(theme);
    (b.labelPainter ??= UiTextPainter())
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
        icons: UiIcons.of(context),
      )
      ..paint(canvas, Offset.zero);
  }
}
