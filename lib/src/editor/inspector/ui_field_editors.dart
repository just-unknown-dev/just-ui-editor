/// How the inspector shows the interface's own field types.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:meta/meta.dart';

import '../../bindings/bindings.dart';
import '../../controls/controls.dart';
import '../../layout/layout.dart';
import '../../serialization/serialization.dart';
import '../../text/text.dart';
import '../../theme/theme.dart';
import 'ui_field_rows.dart';

/// A row for each of the interface's field types, by type id — what the
/// module hands the editor's field-editor registry.
@internal
abstract final class UiFieldEditors {
  /// The rows, offering what the engine [context] answers with (null
  /// before there is one) has registered: its bindings, its actions, its
  /// fonts and the theme it previews with.
  static Map<String, FieldEditorBuilder> all(
    EngineContext? Function() context,
  ) => {
    UiFieldTypes.uiTextStyle.id: (c) => _textStyle(c, context()),
    UiFieldTypes.uiActions.id: (c) => _actions(c, context()),
    UiFieldTypes.uiAnchor.id: _anchor,
    UiFieldTypes.uiText.id: (c) => _text(c, context()),
    UiFieldTypes.uiStyleRole.id: _styleRole,
    UiFieldTypes.uiColorRole.id: _colorRole,
  };

  /// What an unset colour on a piece of interface is drawn with, against
  /// the theme [context]'s engine previews with ([uiInheritedColor]).
  static InheritedColor inheritedColor(EngineContext? Function() context) =>
      (component, field) {
        final engine = context();
        return uiInheritedColor(
          component,
          field,
          theme: engine == null
              ? UiTheme.fallback
              : UiThemes.of(engine).preview,
        );
      };

  /// What an unset role — a file edited by hand — reads as: the element's
  /// own default, which is not the first role of the list (a panel with
  /// none is drawn in `surface`, a button in `primary`).
  static const String unsetRole = '(its default)';

  /// Which of the theme's colours this element is drawn in. A name the
  /// palette does not carry stays listed: opening the inspector must never
  /// quietly rewrite what a game named — nor show a role it does not have.
  static Widget _colorRole(FieldEditorContext c) => _role(c, UiPalette.roles);

  /// Which of the theme's text styles this element reads as.
  static Widget _styleRole(FieldEditorContext c) => _role(c, UiTheme.textRoles);

  static Widget _role(FieldEditorContext c, List<String> roles) {
    final current = c.value is String ? c.value! as String : '';
    if (c.readOnly) {
      return ReadonlyFieldRow(
        label: c.label,
        value: current.isEmpty ? unsetRole : current,
      );
    }
    return DropdownFieldRow(
      label: c.label,
      value: current.isEmpty ? unsetRole : current,
      options: [
        if (current.isEmpty) unsetRole,
        ...roles,
        if (current.isNotEmpty && !roles.contains(current)) current,
      ],
      allowCustom: true,
      onChanged: (picked) => c.onChanged(picked == unsetRole ? '' : picked),
    );
  }

  static Widget _anchor(FieldEditorContext c) => UiAnchorFieldRow(
    label: c.label,
    anchor: c.value is UiAnchor ? c.value! as UiAnchor : UiAnchor.topLeft,
    onChanged: c.onChanged,
  );

  static Widget _text(FieldEditorContext c, EngineContext? context) =>
      c.readOnly
      ? ReadonlyFieldRow(label: c.label, value: '${c.value}')
      : UiTextFieldRow(
          label: c.label,
          value: c.value?.toString() ?? '',
          bindings: context == null ? const [] : UiBindings.of(context).names,
          onChanged: c.onChanged,
        );

  /// A text style, over the theme's style for the element's role — the
  /// theme of the screen open in the editor (see `UiThemes.preview`), so
  /// what the row says is inherited is what that screen draws.
  static Widget _textStyle(FieldEditorContext c, EngineContext? context) {
    final role = _roleOf(c.component);
    final preview = context == null
        ? UiTheme.fallback
        : UiThemes.of(context).preview;
    return UiTextStyleFieldRow(
      label: c.label,
      style: c.value is UiTextStyle
          ? c.value! as UiTextStyle
          : const UiTextStyle(),
      fontFamilies: context == null ? const [] : UiFonts.of(context).families,
      inherited: role == null ? null : preview.textStyle(role),
      inheritedFrom: role ?? '',
      onChanged: c.onChanged,
    );
  }

  static String? _roleOf(Component component) => switch (component) {
    final UiTextComponent text => text.styleRole,
    final UiButtonComponent button => button.styleRole,
    _ => null,
  };

  static Widget _actions(FieldEditorContext c, EngineContext? context) =>
      UiActionsFieldRow(
        label: c.label,
        actions: c.value is UiActionList
            ? c.value! as UiActionList
            : UiActionList.empty,
        customNames: context == null
            ? const []
            : UiActions.of(context).customNames,
        onChanged: c.onChanged,
      );
}

/// What an unset colour on a piece of interface is drawn with — the theme's
/// colour for its role — so the inspector shows that instead of a blank.
///
/// The components decide (`colorUnder`, `borderColorUnder`), so what the
/// inspector says is inherited and what is drawn cannot drift apart.
/// [theme] is the one the open screen is drawn with.
@internal
({Color color, String from})? uiInheritedColor(
  Component component,
  String field, {
  required UiTheme theme,
}) {
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
    (final UiButtonComponent button, 'color') => (
      color: theme.color(
        button.colorRole,
        fallbackColor: theme.palette.primary,
      ),
      from: button.colorRole,
    ),
    _ => null,
  };
}
