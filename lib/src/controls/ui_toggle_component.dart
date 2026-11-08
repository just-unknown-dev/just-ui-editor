/// A switch with two states.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';

/// A switch with two states.
class UiToggleComponent extends Component {
  UiToggleComponent({
    this.value = false,
    this.label = '',
    this.binding = '',
    this.onChanged = UiActionList.empty,
  });

  bool value;
  String label;

  /// A binding read to keep this in step with the game.
  String binding;

  /// What happens when it is flipped; the new state is the action's value.
  UiActionList onChanged;

  @override
  String toString() => 'UiToggle($value)';
}
