/// The field types the interface saves with — the same ids the engine used
/// to carry, so saved scenes and screens read back unchanged.
///
/// A schema field holds its type directly, so nothing needs registering:
/// the editor finds each one's row by [FieldType.id].
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../components/screen/ui_slot_component.dart';
import '../logic/ui_actions.dart';
import '../text/ui_text_style.dart';

abstract final class UiFieldTypes {
  /// Everything about how a piece of text looks, in one field.
  static const uiTextStyle = UiTextStyleFieldType();

  /// What a UI element does when it is used.
  static const uiActions = UiActionsFieldType();

  /// Where a child is pinned in its parent.
  static const uiAnchor = UiAnchorFieldType();

  /// Text a player reads: tags, bindings and language keys.
  static const uiText = UiTextFieldType();

  /// The name of a text style in the theme.
  static const uiStyleRole = UiStyleRoleFieldType();

  /// The name of a colour in the theme's palette.
  static const uiColorRole = UiColorRoleFieldType();

  /// Every type above.
  static const List<FieldType> all = [
    uiTextStyle,
    uiActions,
    uiAnchor,
    uiText,
    uiStyleRole,
    uiColorRole,
  ];
}

/// A [UiTextStyle], written as the style's own JSON — every choice about
/// how a piece of text looks, in one field.
class UiTextStyleFieldType extends FieldType<UiTextStyle> {
  const UiTextStyleFieldType();
  @override
  String get id => 'uiTextStyle';
  @override
  Object? encode(UiTextStyle value) => value.toJson();
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is Map ? UiTextStyle.fromJson(json.cast<String, dynamic>()) : json;
}

/// A [UiActionList]: what a button does, as a list of {kind, arg}.
class UiActionsFieldType extends FieldType<UiActionList> {
  const UiActionsFieldType();
  @override
  String get id => 'uiActions';
  @override
  Object? encode(UiActionList value) => value.toJson();
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is List ? UiActionList.fromJson(json) : json;
}

/// Where a child is pinned in its parent, as four fractions.
///
/// Saved as numbers rather than the preset's name so an anchor dragged off
/// a preset still saves; the editor shows the preset grid regardless.
class UiAnchorFieldType extends FieldType<UiAnchor> {
  const UiAnchorFieldType();
  @override
  String get id => 'uiAnchor';
  @override
  Object? encode(UiAnchor value) => value.toJson();
  @override
  Object? decode(Object? json, FieldConstraints c) =>
      json is Map ? UiAnchor.fromJson(json.cast<String, dynamic>()) : json;
}

/// Text a player will read: it may carry tags (`[b]`), bindings
/// (`{coins}`) or be a key into the current language (`@hud.coins`).
///
/// Stored exactly as plain text — the separate type is so the inspector
/// can offer the tag buttons and suggest what the game has to read.
class UiTextFieldType extends FieldType<String> {
  const UiTextFieldType();
  @override
  String get id => 'uiText';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// The name of a text style in the theme — `body`, `title`, `caption`.
///
/// Stored as plain text so a game may name a role of its own; the separate
/// type is so the inspector offers the ones a theme is expected to carry
/// instead of a box to misspell.
class UiStyleRoleFieldType extends FieldType<String> {
  const UiStyleRoleFieldType();
  @override
  String get id => 'uiStyleRole';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}

/// The name of a colour in the theme's palette — `primary`, `surface`,
/// `danger`.
///
/// Same bargain as [UiStyleRoleFieldType]: stored as plain text so a game
/// may name a colour of its own, typed so the inspector can offer the ones
/// a palette carries.
class UiColorRoleFieldType extends FieldType<String> {
  const UiColorRoleFieldType();
  @override
  String get id => 'uiColorRole';
  @override
  Object? encode(String value) => value;
  @override
  Object? decode(Object? json, FieldConstraints c) => json;
}
