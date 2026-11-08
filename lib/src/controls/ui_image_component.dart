/// A picture in the interface.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A picture in the interface.
class UiImageComponent extends Component {
  UiImageComponent({
    this.path = '',
    this.atlasRegion = '',
    this.fit = BoxFit.contain,
    this.tint,
    this.opacity = 1,
  });

  /// An image asset, or the atlas the region is in.
  String path;

  /// A named region of an atlas at [path]; empty uses the whole image.
  String atlasRegion;

  BoxFit fit;
  Color? tint;
  double opacity;

  @override
  String toString() => 'UiImage($path)';
}
