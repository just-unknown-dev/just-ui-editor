/// How the inspector shows the interface's own field types.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/screen/ui_slot_component.dart';
import '../../runtime/components/text_component.dart';
import '../../runtime/logic/ui_actions.dart';
import '../../runtime/logic/ui_bindings.dart';
import '../../runtime/serialization/ui_field_types.dart';
import '../../runtime/text/ui_fonts.dart';
import '../../runtime/text/ui_text_style.dart';
import '../../runtime/theme/ui_theme.dart';
import 'ui_field_editors.dart';

/// A row for each of the interface's field types, by type id — what the
/// module hands the editor's field-editor registry.
abstract final class UiFieldEditors {
  static Map<String, FieldEditorBuilder> get all => {
    UiFieldTypes.uiTextStyle.id: _textStyle,
    UiFieldTypes.uiActions.id: _actions,
    UiFieldTypes.uiAnchor.id: _anchor,
    UiFieldTypes.uiText.id: _text,
    UiFieldTypes.uiStyleRole.id: _styleRole,
    UiFieldTypes.uiColorRole.id: _colorRole,
  };

  /// Which of the theme's colours this element is drawn in. A name the
  /// palette does not carry stays listed: opening the inspector must never
  /// quietly rewrite what a game named.
  static Widget _colorRole(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    return DropdownEditorRow(
      label: c.label,
      value: current.isEmpty ? UiPalette.roles.first : current,
      options: [
        ...UiPalette.roles,
        if (current.isNotEmpty && !UiPalette.roles.contains(current)) current,
      ],
      allowCustom: true,
      onChanged: c.onChanged,
    );
  }

  /// Which of the theme's text styles this element reads as.
  static Widget _styleRole(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    return DropdownEditorRow(
      label: c.label,
      value: current.isEmpty ? UiTheme.textRoles.first : current,
      options: [
        ...UiTheme.textRoles,
        if (current.isNotEmpty && !UiTheme.textRoles.contains(current)) current,
      ],
      allowCustom: true,
      onChanged: c.onChanged,
    );
  }

  static Widget _anchor(FieldEditorContext c) => UiAnchorEditorRow(
    label: c.label,
    anchor: c.value is UiAnchor ? c.value! as UiAnchor : UiAnchor.topLeft,
    onChanged: c.onChanged,
  );

  static Widget _text(FieldEditorContext c) => c.readOnly
      ? ReadonlyRow(label: c.label, value: '${c.value}')
      : UiTextEditorRow(
          label: c.label,
          value: c.value?.toString() ?? '',
          bindings: UiBindings.names,
          onChanged: c.onChanged,
        );

  /// A text style, over the theme's style for the element's role — the
  /// theme of the screen open in the editor (see `UiThemes.preview`), so
  /// what the row says is inherited is what that screen draws.
  static Widget _textStyle(FieldEditorContext c) {
    final role = _roleOf(c.component);
    return UiTextStyleEditorRow(
      label: c.label,
      style: c.value is UiTextStyle
          ? c.value! as UiTextStyle
          : const UiTextStyle(),
      fontFamilies: UiFonts.families,
      inherited: role == null ? null : UiThemes.preview.textStyle(role),
      inheritedFrom: role ?? '',
      onChanged: c.onChanged,
    );
  }

  static String? _roleOf(Component component) => switch (component) {
    final TextComponent text => text.styleRole,
    final ButtonComponent button => button.styleRole,
    _ => null,
  };

  static Widget _actions(FieldEditorContext c) => UiActionsEditorRow(
    label: c.label,
    actions: c.value is UiActionList
        ? c.value! as UiActionList
        : UiActionList.empty,
    customNames: UiActions.customNames,
    onChanged: c.onChanged,
  );
}

/// What an unset colour on a piece of interface is drawn with — the theme's
/// colour for its role — so the inspector shows that instead of a blank.
///
/// The components decide (`colorUnder`, `borderColorUnder`), so what the
/// inspector says is inherited and what is drawn cannot drift apart.
({Color color, String from})? uiInheritedColor(
  Component component,
  String field,
) {
  final theme = UiThemes.preview;
  return switch ((component, field)) {
    (final UiPanelComponent panel, 'color') => (
      color: theme.color(panel.colorRole, fallbackColor: theme.palette.surface),
      from: panel.colorRole,
    ),
    (final UiPanelComponent _, 'borderColor') => (
      color: theme.palette.outline,
      from: 'outline',
    ),
    (final UiProgressComponent bar, 'color') => (
      color: theme.color(bar.colorRole, fallbackColor: theme.palette.accent),
      from: bar.colorRole,
    ),
    (final UiProgressComponent _, 'trackColor') => (
      color: theme.palette.outline,
      from: 'outline',
    ),
    (final ButtonComponent button, 'color') => (
      color: theme.color(
        button.colorRole,
        fallbackColor: theme.palette.primary,
      ),
      from: button.colorRole,
    ),
    _ => null,
  };
}
