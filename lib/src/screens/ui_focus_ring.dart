// The ring round whatever holds the focus, so a player walking a menu with
// a pad or the keyboard can see where they are.
part of 'ui_layer.dart';

/// Rings [child] while the focus is anywhere in it — a button, a toggle and
/// its label, a slider, a field — and calls [onFocused] as the focus
/// arrives.
///
/// Material's own focus look is an overlay a tenth lighter, which cannot be
/// told from across a room. A ring [gap] clear of the control's edge can,
/// whatever the control's own colour: the gap shows what is behind between
/// the two.
class _UiFocusRing extends StatefulWidget {
  const _UiFocusRing({
    required this.color,
    required this.radius,
    required this.child,
    this.onFocused,
  });

  /// How thick the ring is, in design pixels.
  static const double width = 3;

  /// How far outside the control's edge the ring starts.
  static const double gap = 3;

  final Color color;

  /// How round the control's corners are; the ring follows them, further
  /// out.
  final double radius;

  final VoidCallback? onFocused;

  final Widget child;

  @override
  State<_UiFocusRing> createState() => _UiFocusRingState();
}

class _UiFocusRingState extends State<_UiFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (has) {
      if (has) widget.onFocused?.call();
      if (mounted && has != _focused) setState(() => _focused = has);
    },
    // There whether ringed or not: a widget put round the control as the
    // focus arrived would build the control again, and lose the focus.
    child: CustomPaint(
      foregroundPainter: _focused
          ? _UiFocusRingPainter(color: widget.color, radius: widget.radius)
          : null,
      child: widget.child,
    ),
  );
}

/// The ring itself, drawn outside the box it is given.
class _UiFocusRingPainter extends CustomPainter {
  const _UiFocusRingPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // The stroke's middle line, so its inner edge is [gap] out.
    const out = _UiFocusRing.gap + _UiFocusRing.width / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(out),
        Radius.circular(math.max(0, radius) + out),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _UiFocusRing.width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_UiFocusRingPainter old) =>
      old.color != color || old.radius != radius;
}
