/// A line the player types into.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';

/// A line the player types into.
class UiTextFieldComponent extends Component {
  UiTextFieldComponent({
    this.value = '',
    this.hint = '',
    this.maxLength = 0,
    this.obscure = false,
    this.onSubmitted = UiActionList.empty,
    this.onChanged = UiActionList.empty,
  });

  String value;
  String hint;

  /// 0 for no limit.
  int maxLength;

  /// For a password.
  bool obscure;

  UiActionList onSubmitted;
  UiActionList onChanged;

  @override
  String toString() => 'UiTextField("$value")';
}
