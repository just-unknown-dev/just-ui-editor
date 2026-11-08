/// Empty room in a row or a column.
library;

import 'package:just_game_engine/just_game_engine.dart';

/// Empty room in a row or a column.
class UiSpacerComponent extends Component {
  UiSpacerComponent({this.size = 8, this.expand = false});

  /// How much room, when it is not expanding.
  double size;

  /// Take everything that is left, as Flutter's `Spacer` does.
  bool expand;

  @override
  String toString() => 'UiSpacer(${expand ? 'expand' : size})';
}
