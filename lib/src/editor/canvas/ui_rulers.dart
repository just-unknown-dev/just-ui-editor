/// The rulers along the top and the left of the canvas, in design pixels.
library;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';

import 'ui_canvas_metrics.dart';

/// Paints the two rulers. Where the pointer is on the canvas is marked on
/// both, and so is the selection's extent.
class UiRulersPainter extends CustomPainter {
  UiRulersPainter({
    required this.metrics,
    required this.pointer,
    required this.selection,
    super.repaint,
  });

  /// Where the screen is on the canvas — asked when painting, since the
  /// frame is only laid out after the canvas is built.
  final UiCanvasMetrics? Function() metrics;

  /// The pointer, in view pixels, or null when it is elsewhere.
  final Offset? pointer;

  /// The selection's box, in view pixels — asked when painting.
  final Rect? Function() selection;

  /// How thick a ruler is.
  static const double thickness = 18;

  /// A step between labelled ticks, in design pixels, that leaves at least
  /// [minGap] view pixels between labels at [scale].
  static double stepFor(double scale, {double minGap = 56}) {
    const steps = [
      1.0,
      2.0,
      5.0,
      10.0,
      20.0,
      50.0,
      100.0,
      200.0,
      500.0,
      1000.0,
      2000.0,
    ];
    for (final step in steps) {
      if (step * scale >= minGap) return step;
    }
    return steps.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = metrics();
    final back = Paint()..color = EditorTheme.panelBg;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, thickness), back)
      ..drawRect(Rect.fromLTWH(0, 0, thickness, size.height), back);
    final border = Paint()
      ..color = EditorTheme.border
      ..strokeWidth = 1;
    canvas
      ..drawLine(
        const Offset(0, thickness),
        Offset(size.width, thickness),
        border,
      )
      ..drawLine(
        const Offset(thickness, 0),
        Offset(thickness, size.height),
        border,
      );
    if (m == null || m.canvasView == null) return;

    final scale = m.scale;
    final step = stepFor(scale);
    final minor = step / 5;
    final tick = Paint()
      ..color = EditorTheme.textMuted
      ..strokeWidth = 1;
    final design = m.designSize;
    final left = m.toDesign(const Offset(thickness, 0)).dx;
    final right = m.toDesign(Offset(size.width, 0)).dx;
    final top = m.toDesign(const Offset(0, thickness)).dy;
    final bottom = m.toDesign(Offset(0, size.height)).dy;

    // The canvas's own extent, a shade lighter, so its edges read on both.
    final canvasRect = m.canvasView!;
    final lit = Paint()..color = EditorTheme.surfaceBg;
    canvas
      ..drawRect(
        Rect.fromLTRB(
          canvasRect.left.clamp(thickness, size.width),
          0,
          canvasRect.right.clamp(thickness, size.width),
          thickness - 1,
        ),
        lit,
      )
      ..drawRect(
        Rect.fromLTRB(
          0,
          canvasRect.top.clamp(thickness, size.height),
          thickness - 1,
          canvasRect.bottom.clamp(thickness, size.height),
        ),
        lit,
      );

    final sel = selection();
    if (sel != null) {
      final mark = Paint()..color = EditorTheme.accent.withValues(alpha: 0.35);
      canvas
        ..drawRect(Rect.fromLTRB(sel.left, 0, sel.right, thickness - 1), mark)
        ..drawRect(Rect.fromLTRB(0, sel.top, thickness - 1, sel.bottom), mark);
    }

    double first(double from) => (from / minor).floorToDouble() * minor;
    for (var x = first(left); x <= right; x += minor) {
      final at = m.toView(Offset(x, 0)).dx;
      if (at < thickness) continue;
      final major = (x / step).roundToDouble() * step == x;
      canvas.drawLine(
        Offset(at, major ? 4 : thickness - 5),
        Offset(at, thickness - 1),
        tick,
      );
      if (major) _text(canvas, _format(x), Offset(at + 3, 1), vertical: false);
    }
    for (var y = first(top); y <= bottom; y += minor) {
      final at = m.toView(Offset(0, y)).dy;
      if (at < thickness) continue;
      final major = (y / step).roundToDouble() * step == y;
      canvas.drawLine(
        Offset(major ? 4 : thickness - 5, at),
        Offset(thickness - 1, at),
        tick,
      );
      if (major) _text(canvas, _format(y), Offset(1, at + 3), vertical: true);
    }

    final p = pointer;
    if (p != null && design != Size.zero) {
      final mark = Paint()
        ..color = EditorTheme.accent
        ..strokeWidth = 1;
      canvas
        ..drawLine(Offset(p.dx, 0), Offset(p.dx, thickness), mark)
        ..drawLine(Offset(0, p.dy), Offset(thickness, p.dy), mark);
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, thickness, thickness),
      Paint()..color = EditorTheme.panelBg,
    );
  }

  static String _format(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  void _text(Canvas canvas, String text, Offset at, {required bool vertical}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: EditorTheme.textMuted, fontSize: 8.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (!vertical) {
      painter.paint(canvas, at);
      return;
    }
    canvas
      ..save()
      ..translate(at.dx, at.dy + painter.width)
      ..rotate(-1.5707963267948966);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(UiRulersPainter old) => true;
}
