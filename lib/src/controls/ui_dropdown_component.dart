/// One of several choices.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';

/// One of several choices.
class UiDropdownComponent extends Component {
  UiDropdownComponent({
    this.value = '',
    List<String>? options,
    this.label = '',
    this.onChanged = UiActionList.empty,
  }) : options = options ?? <String>[];

  String value;
  final List<String> options;
  String label;
  UiActionList onChanged;

  @override
  String toString() => 'UiDropdown($value)';
}
