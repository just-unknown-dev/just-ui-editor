// Text in a screen that only the canvas painter can draw.
part of 'ui_layer.dart';

/// Text the canvas painter draws in a screen: what Flutter's `Text` cannot
/// do — letters that wave, shake or change colour, an outline, a gradient,
/// shrinking to fit — with the same [UiTextPainter] world text uses, so a
/// screen and the level agree.
///
/// Laid out at the room it is given and scaled with the player's text
/// size. It animates itself, on its own ticker, only while something in it
/// moves: nothing else about the screen rebuilds for it.
class _UiPaintedText extends StatefulWidget {
  const _UiPaintedText({
    required this.text,
    required this.icons,
    required this.style,
    required this.align,
    required this.overflow,
    required this.maxLines,
    required this.minSize,
  });

  final UiRichText text;

  /// What its `[icon=…]` draws: the layer's engine's icons.
  final UiIcons icons;
  final UiTextStyle style;
  final UiTextAlign align;
  final UiTextOverflow overflow;
  final int? maxLines;
  final double minSize;

  @override
  State<_UiPaintedText> createState() => _UiPaintedTextState();
}

class _UiPaintedTextState extends State<_UiPaintedText>
    with TickerProviderStateMixin {
  final UiTextPainter _painter = UiTextPainter();
  final ValueNotifier<double> _seconds = ValueNotifier(0);
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_UiPaintedText old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.text.animates) {
      _ticker ??= createTicker(
        (elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6,
      )..start();
    } else {
      _ticker?.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _seconds.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        _painter
          ..set(
            text: widget.text,
            style: widget.style,
            textScaler: scaler,
            icons: widget.icons,
            layout: UiTextLayout(
              align: widget.align,
              overflow: widget.overflow,
              maxWidth: box.maxWidth.isFinite ? box.maxWidth : null,
              maxHeight: box.maxHeight.isFinite ? box.maxHeight : null,
              maxLines: widget.maxLines,
              minSize: widget.minSize,
            ),
          )
          ..layout();
        return Semantics(
          label: widget.text.plain,
          child: CustomPaint(
            size: box.constrain(_painter.size),
            painter: _UiTextPaint(_painter, _seconds),
          ),
        );
      },
    );
  }
}

class _UiTextPaint extends CustomPainter {
  _UiTextPaint(this.text, this.seconds) : super(repaint: seconds);

  final UiTextPainter text;
  final ValueListenable<double> seconds;

  @override
  void paint(Canvas canvas, Size size) {
    // From the top-left, as `Text` draws: what does not fit spills below.
    final drawn = text.size;
    text.paint(
      canvas,
      Offset(drawn.width / 2, drawn.height / 2),
      animation: UiTextAnimation(seconds: seconds.value),
    );
  }

  @override
  bool shouldRepaint(_UiTextPaint old) => true;
}
