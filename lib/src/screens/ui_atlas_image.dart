// One region of a sprite atlas, as a picture in a screen.
part of 'ui_layer.dart';

/// One named region of a sprite atlas, fitted into the room it is given.
class _UiAtlasImage extends StatefulWidget {
  const _UiAtlasImage({
    required this.sprites,
    required this.path,
    required this.region,
    required this.fit,
    this.tint,
  });

  final SpriteAssetLoader sprites;
  final String path;
  final String region;
  final BoxFit fit;
  final Color? tint;

  @override
  State<_UiAtlasImage> createState() => _UiAtlasImageState();
}

class _UiAtlasImageState extends State<_UiAtlasImage> {
  SpriteAtlas? _atlas;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_UiAtlasImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || !identical(old.sprites, widget.sprites)) {
      _load();
    }
  }

  void _load() {
    final path = widget.path;
    widget.sprites.loadAtlas(path).then(
      (atlas) {
        if (mounted && widget.path == path) setState(() => _atlas = atlas);
      },
      // An atlas that is not there leaves an empty space.
      onError: (Object _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    if (atlas == null || !atlas.regionNames.contains(widget.region)) {
      return const SizedBox.shrink();
    }
    final region = atlas.requireRegion(widget.region);
    final image = atlas.pages[region.pageIndex].image;
    if (image == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) => CustomPaint(
        size: box.hasBoundedWidth && box.hasBoundedHeight
            ? box.biggest
            : box.constrain(region.sourceSize),
        painter: _UiRegionPaint(image, region, widget.fit, widget.tint),
      ),
    );
  }
}

class _UiRegionPaint extends CustomPainter {
  _UiRegionPaint(this.image, this.region, this.fit, this.tint);

  final ui.Image image;
  final SpriteRegion region;
  final BoxFit fit;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final box = region.sourceSize;
    if (box.isEmpty || size.isEmpty) return;
    final fitted = applyBoxFit(fit, box, size);
    final into = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final from = Alignment.center.inscribe(fitted.source, Offset.zero & box);
    final sx = into.width / from.width, sy = into.height / from.height;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = tint == null
          ? null
          : ColorFilter.mode(tint!, BlendMode.modulate);
    canvas
      ..save()
      ..clipRect(into)
      ..translate(into.left - from.left * sx, into.top - from.top * sy)
      ..scale(sx, sy);
    // The frame sits in its untrimmed box where the exporter cut it from,
    // and one stored turned 90° clockwise is turned back.
    final source = AtlasRegionSprite.textureRectOf(region);
    final dest = Rect.fromLTWH(
      region.spriteSourceOffset.dx,
      region.spriteSourceOffset.dy,
      region.frame.width,
      region.frame.height,
    );
    if (region.rotated) {
      canvas
        ..translate(dest.center.dx, dest.center.dy)
        ..rotate(-math.pi / 2)
        ..drawImageRect(
          image,
          source,
          Rect.fromCenter(
            center: Offset.zero,
            width: dest.height,
            height: dest.width,
          ),
          paint,
        );
    } else {
      canvas.drawImageRect(image, source, dest, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UiRegionPaint old) =>
      !identical(old.image, image) ||
      !identical(old.region, region) ||
      old.fit != fit ||
      old.tint != tint;
}
