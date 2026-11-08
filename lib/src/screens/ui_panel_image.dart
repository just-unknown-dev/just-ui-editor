// A panel's picture, stretched or nine-sliced.
part of 'ui_layer.dart';

/// A panel's picture: stretched to fill it, or — with [nineSlice] — with
/// only its middle stretched and its corners kept as drawn.
///
/// The slices are measured in the image's own pixels, so its size is read
/// first; until it is in, the panel shows no picture.
class _UiPanelImage extends StatefulWidget {
  const _UiPanelImage({
    required this.path,
    required this.nineSlice,
    required this.radius,
    required this.child,
  });

  final String path;
  final EdgeInsets nineSlice;
  final double radius;
  final Widget child;

  @override
  State<_UiPanelImage> createState() => _UiPanelImageState();
}

class _UiPanelImageState extends State<_UiPanelImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;

  bool get _sliced => widget.nineSlice != EdgeInsets.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_UiPanelImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _size = null;
      _stop();
    }
    // Slicing needs the picture's size: read it when slices are set on a
    // panel that had none, let go of it when they are taken off.
    if (old.path != widget.path || old.nineSlice != widget.nineSlice) {
      _resolve();
    }
  }

  void _resolve() {
    if (!_sliced) {
      _stop();
      return;
    }
    final stream = AssetImage(
      widget.path,
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stop();
    final listener = ImageStreamListener(
      (info, _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        if (mounted && size != _size) setState(() => _size = size);
      },
      // A picture that is not there leaves the panel without one.
      onError: (_, _) {},
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _stop() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Rect? centre;
    if (_sliced) {
      final size = _size;
      if (size == null) return widget.child;
      final slice = widget.nineSlice;
      final rect = Rect.fromLTRB(
        slice.left,
        slice.top,
        size.width - slice.right,
        size.height - slice.bottom,
      );
      // Slices that meet or cross leave nothing to stretch: stretch it all.
      if (rect.width > 0 && rect.height > 0) centre = rect;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        image: DecorationImage(
          image: AssetImage(widget.path),
          fit: BoxFit.fill,
          centerSlice: centre,
          onError: (_, _) {},
        ),
      ),
      child: widget.child,
    );
  }
}
