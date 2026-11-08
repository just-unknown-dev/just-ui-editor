/// A widget the game registered, placed from the editor.
library;

import 'package:just_game_engine/just_game_engine.dart';

/// A widget the game registered, placed from the editor.
///
/// This is the seam that makes the whole thing open-ended: anything
/// Flutter can do, a scene can hold.
class UiCustomComponent extends Component {
  UiCustomComponent({this.widgetId = '', Map<String, String>? props})
    : props = props ?? <String, String>{};

  /// The name it was registered under in `UiWidgets`.
  String widgetId;

  /// What the scene tells it, as plain text so it saves and shows in the
  /// inspector. A widget reads what it knows and ignores the rest.
  final Map<String, String> props;

  /// A property as a number, for a widget that wants one.
  double? number(String key) => double.tryParse(props[key] ?? '');

  /// A property as a flag.
  bool flag(String key) => props[key] == 'true';

  @override
  String toString() => 'UiCustom($widgetId)';
}
