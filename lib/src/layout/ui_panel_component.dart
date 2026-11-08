/// Something drawn behind its children.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../theme/theme.dart';

/// Something drawn behind its children: a background, a card, a bar.
class UiPanelComponent extends Component {
  UiPanelComponent({
    this.colorRole = 'surface',
    this.color,
    this.gradient,
    this.borderColor,
    this.borderWidth = 0,
    this.radius = 8,
    this.shadowBlur = 0,
    this.blur = 0,
    this.image = '',
    this.nineSlice = EdgeInsets.zero,
  });

  /// A colour from the theme, unless [color] says otherwise.
  String colorRole;
  Color? color;

  /// Two or more colours swept behind it.
  List<Color>? gradient;

  Color? borderColor;
  double borderWidth;
  double radius;

  /// A shadow under it; 0 for none.
  double shadowBlur;

  /// Frosts whatever is behind it.
  double blur;

  /// A picture instead of a colour.
  String image;

  /// Which parts of [image] stretch: the middle does, the corners do not.
  EdgeInsets nineSlice;

  bool get hasNineSlice =>
      image.isNotEmpty && (nineSlice.horizontal + nineSlice.vertical) > 0;

  /// What it is actually filled with under [theme]: its own colour where it
  /// has one, otherwise the colour its role names, otherwise the theme's
  /// surface.
  ///
  /// Here rather than in the layer so that what is drawn and what the
  /// inspector says it inherits cannot drift apart.
  Color colorUnder(UiTheme theme) =>
      color ?? theme.color(colorRole, fallbackColor: theme.palette.surface);

  /// The colour of its edge: its own, else the theme's outline. Only drawn
  /// where [borderWidth] is more than nothing.
  Color borderColorUnder(UiTheme theme) => borderColor ?? theme.palette.outline;

  @override
  String toString() => 'UiPanel($colorRole)';
}
