/// A bar that fills.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../theme/theme.dart';

/// A bar that fills: health, loading, a timer.
class UiProgressComponent extends Component {
  UiProgressComponent({
    this.value = 0.5,
    this.binding = '',
    this.maxBinding = '',
    this.colorRole = 'accent',
    this.color,
    this.trackColor,
    this.radius = 6,
    this.radial = false,
    this.thickness = 8,
  });

  /// 0–1, unless a binding is reading it.
  double value;

  /// A binding to read instead of [value].
  String binding;

  /// With [binding], what to divide by — `health` over `maxHealth`.
  String maxBinding;

  String colorRole;
  Color? color;
  Color? trackColor;
  double radius;

  /// A ring rather than a bar.
  bool radial;

  /// How thick the ring is.
  double thickness;

  /// The colour the bar fills with under [theme].
  Color colorUnder(UiTheme theme) =>
      color ?? theme.color(colorRole, fallbackColor: theme.palette.accent);

  /// The colour behind it.
  Color trackColorUnder(UiTheme theme) => trackColor ?? theme.palette.outline;

  @override
  String toString() => 'UiProgress(${(value * 100).round()}%)';
}
