/// What the editor draws over a screen: outlines, handles, anchors, lines.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/screen/ui_slot_component.dart';
import '../session/ui_editor_session.dart';
import 'ui_canvas_metrics.dart';
import 'ui_geometry.dart';

/// Colours of the overlay: the editor's accent for what is selected, a
/// quieter line for the rest.
abstract final class UiOverlayColors {
  static Color get selection => EditorTheme.accent;
  static Color get hover => EditorTheme.accent.withValues(alpha: 0.55);
  static Color get box => Colors.white.withValues(alpha: 0.18);
  static const Color snap = Color(0xFFFF4FB8);
  static const Color guide = Color(0xFF3DD6F5);
  static Color get anchor => EditorTheme.warning;
  static const Color grid = Color(0x22FFFFFF);
  static const Color insert = Color(0xFF3DD6F5);
}

/// A flow child being dragged to a new place: the line where it would go.
class UiInsertMark {
  const UiInsertMark(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// What the canvas shows over the screen that follows the pointer — the
/// element under it, a marquee, where a dragged child would land, a size
/// while dragging. Read when painting, and told of a change with
/// [changed], so a hover repaints the overlay and rebuilds nothing.
class UiCanvasOverlay extends ChangeNotifier {
  /// The pointer, in view pixels, or null when it is elsewhere.
  Offset? pointer;

  /// What is under the pointer, outlined lightly.
  Entity? hovered;

  /// A marquee being dragged out, in view pixels.
  Rect? marquee;

  /// Where a flow child being dragged would land.
  UiInsertMark? insertMark;

  /// Size and place while a drag lasts: "240 × 52".
  String? dragLabel;

  /// Whether a drag is going on: nothing is outlined as hovered then.
  bool dragging = false;

  /// Repaints whatever shows these.
  void changed() => notifyListeners();
}

/// The overlay, painted in view pixels.
class UiCanvasPainter extends CustomPainter {
  UiCanvasPainter({
    required this.session,
    required this.overlay,
    super.repaint,
  });

  final UiEditorSession session;

  /// Where things are on the canvas, read from [session] when painting:
  /// the frame is only laid out after the canvas is built, so what it was
  /// at build time is nothing on the first frame.
  UiCanvasMetrics? get metrics => session.metrics;

  /// What is selected, read when painting, like [metrics].
  List<Entity> get selected => session.selection;

  /// What follows the pointer, read when painting.
  final UiCanvasOverlay overlay;

  Entity? get hovered => overlay.dragging ? null : overlay.hovered;
  Rect? get marquee => overlay.marquee;
  UiInsertMark? get insertMark => overlay.insertMark;
  String? get dragLabel => overlay.dragLabel;

  /// How big a handle is on screen, whatever the zoom.
  static const double handleSize = 8;

  /// How near a handle a press grabs it.
  static const double handleReach = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final m = metrics;
    final doc = session.document.value;
    if (m == null || doc == null) return;
    final canvasRect = m.canvasView;
    if (canvasRect == null) return;

    if (session.grid.value) _grid(canvas, m, canvasRect);
    if (session.showGuides.value) _guides(canvas, m, canvasRect);

    if (session.boxes.value) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = UiOverlayColors.box;
      for (final e in doc.entities.skip(1)) {
        final r = m.viewRectOf(e);
        if (r != null) canvas.drawRect(r, paint);
      }
    }

    final hover = hovered;
    if (hover != null && !selected.any((e) => e.id == hover.id)) {
      final r = m.viewRectOf(hover);
      if (r != null) {
        canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = UiOverlayColors.hover,
        );
      }
    }

    for (final e in selected) {
      final r = m.viewRectOf(e);
      if (r == null) continue;
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = UiOverlayColors.selection,
      );
    }

    final primary = selected.isEmpty ? null : selected.first;
    if (primary != null && primary.id != doc.canvas.id) {
      final r = m.viewRectOf(primary);
      if (r != null) {
        _anchor(canvas, m, doc.world, primary);
        _handles(canvas, r);
      }
    }

    for (final guide in session.snapGuides.value) {
      final a = m.toView(
        guide.vertical
            ? Offset(guide.position, guide.start)
            : Offset(guide.start, guide.position),
      );
      final b = m.toView(
        guide.vertical
            ? Offset(guide.position, guide.end)
            : Offset(guide.end, guide.position),
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = UiOverlayColors.snap
          ..strokeWidth = 1,
      );
    }

    final mark = insertMark;
    if (mark != null) {
      canvas.drawLine(
        mark.from,
        mark.to,
        Paint()
          ..color = UiOverlayColors.insert
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    final box = marquee;
    if (box != null) {
      canvas
        ..drawRect(
          box,
          Paint()..color = UiOverlayColors.hover.withValues(alpha: 0.12),
        )
        ..drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = UiOverlayColors.selection,
        );
    }

    final label = dragLabel;
    if (label != null && primary != null) {
      final r = m.viewRectOf(primary);
      if (r != null) _label(canvas, label, r.bottomCenter + const Offset(0, 8));
    }
  }

  /// Squares on the corners and edges of [r], and a round one in its
  /// middle marking the pivot.
  void _handles(Canvas canvas, Rect r) {
    final fill = Paint()..color = Colors.white;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = UiOverlayColors.selection;
    for (final handle in UiHandle.resizing) {
      final at = handle.on(r);
      final square = Rect.fromCenter(
        center: at,
        width: handleSize,
        height: handleSize,
      );
      canvas
        ..drawRect(square, fill)
        ..drawRect(square, edge);
    }
  }

  /// Where [e] is pinned in its parent: the anchor, drawn as four small
  /// arrowheads on the parent's box, joined when they stretch — and the
  /// pivot, where the element hangs from it.
  void _anchor(Canvas canvas, UiCanvasMetrics m, World world, Entity e) {
    final slot = e.getComponent<UiSlotComponent>();
    if (slot == null || slot.mode != UiSlotMode.anchored) return;
    final parentId = e.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);
    final content = parent == null ? null : m.contentRectOf(parent);
    if (content == null) return;
    final box = m.designToView(content);
    Offset at(Offset fraction) => Offset(
      box.left + box.width * fraction.dx,
      box.top + box.height * fraction.dy,
    );
    final paint = Paint()
      ..color = UiOverlayColors.anchor
      ..style = PaintingStyle.fill;
    final line = Paint()
      ..color = UiOverlayColors.anchor
      ..strokeWidth = 1;
    final min = at(slot.anchor.min);
    final max = at(slot.anchor.max);
    final corners = {min, max, Offset(min.dx, max.dy), Offset(max.dx, min.dy)};
    for (final c in corners) {
      _arrow(canvas, c, box.center, paint);
    }
    if (slot.anchor.stretchesX || slot.anchor.stretchesY) {
      canvas.drawRect(
        Rect.fromPoints(min, max),
        line..style = PaintingStyle.stroke,
      );
    }
    final element = m.viewRectOf(e);
    if (element != null) {
      final pivot = Offset(
        element.left + element.width * slot.pivot.dx,
        element.top + element.height * slot.pivot.dy,
      );
      canvas
        ..drawCircle(pivot, 3.5, Paint()..color = Colors.white)
        ..drawCircle(
          pivot,
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = UiOverlayColors.anchor,
        );
    }
  }

  /// A small triangle at [at] pointing away from [centre].
  void _arrow(Canvas canvas, Offset at, Offset centre, Paint paint) {
    final away = at - centre;
    final angle = away.distance == 0
        ? -math.pi / 2
        : math.atan2(away.dy, away.dx);
    const length = 9.0;
    const half = 4.5;
    Offset rotate(Offset p) => Offset(
      at.dx + p.dx * math.cos(angle) - p.dy * math.sin(angle),
      at.dy + p.dx * math.sin(angle) + p.dy * math.cos(angle),
    );
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(
        rotate(const Offset(-length, -half)).dx,
        rotate(const Offset(-length, -half)).dy,
      )
      ..lineTo(
        rotate(const Offset(-length, half)).dx,
        rotate(const Offset(-length, half)).dy,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  void _grid(Canvas canvas, UiCanvasMetrics m, Rect canvasRect) {
    final step = session.gridStep.value * m.scale;
    // Too fine to see is too fine to draw: every fourth line instead.
    var every = step;
    while (every < 6) {
      every *= 4;
    }
    final paint = Paint()
      ..color = UiOverlayColors.grid
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(canvasRect);
    for (var x = canvasRect.left; x <= canvasRect.right; x += every) {
      canvas.drawLine(
        Offset(x, canvasRect.top),
        Offset(x, canvasRect.bottom),
        paint,
      );
    }
    for (var y = canvasRect.top; y <= canvasRect.bottom; y += every) {
      canvas.drawLine(
        Offset(canvasRect.left, y),
        Offset(canvasRect.right, y),
        paint,
      );
    }
    canvas.restore();
  }

  void _guides(Canvas canvas, UiCanvasMetrics m, Rect canvasRect) {
    final paint = Paint()
      ..color = UiOverlayColors.guide
      ..strokeWidth = 1;
    for (final guide in session.guides) {
      if (guide.vertical) {
        final x = m.toView(Offset(guide.at, 0)).dx;
        canvas.drawLine(
          Offset(x, canvasRect.top - 12),
          Offset(x, canvasRect.bottom + 12),
          paint,
        );
      } else {
        final y = m.toView(Offset(0, guide.at)).dy;
        canvas.drawLine(
          Offset(canvasRect.left - 12, y),
          Offset(canvasRect.right + 12, y),
          paint,
        );
      }
    }
  }

  void _label(Canvas canvas, String text, Offset topCentre) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 10.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: topCentre + Offset(0, painter.height / 2 + 3),
      width: painter.width + 10,
      height: painter.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = UiOverlayColors.selection,
    );
    painter.paint(canvas, box.topLeft + const Offset(5, 3));
  }

  /// Which handle of [r] is at [point], if any.
  static UiHandle? handleAt(Rect r, Offset point) {
    for (final handle in UiHandle.resizing) {
      if ((handle.on(r) - point).distance <= handleReach) return handle;
    }
    return null;
  }

  @override
  bool shouldRepaint(UiCanvasPainter old) => true;
}
