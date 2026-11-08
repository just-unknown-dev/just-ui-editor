/// A number chosen by dragging.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';

/// A number chosen by dragging.
class UiSliderComponent extends Component {
  UiSliderComponent({
    this.value = 0.5,
    this.min = 0,
    this.max = 1,
    this.steps = 0,
    this.label = '',
    this.binding = '',
    this.onChanged = UiActionList.empty,
  });

  double value;
  double min;
  double max;

  /// How many notches; 0 slides freely.
  int steps;

  String label;
  String binding;
  UiActionList onChanged;

  /// Where the handle sits, 0–1.
  double get fraction =>
      max <= min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  @override
  String toString() => 'UiSlider($value)';
}
