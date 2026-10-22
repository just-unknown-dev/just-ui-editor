/// What the interface editor adds to UI components beyond their fields.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_ui_editor/just_ui_editor.dart' as ui;

abstract final class UiExtras {
  static List<ComponentEditorExtras> get all => [
    // A custom widget is whatever the game registered: offer those by
    // name, and then the properties that widget said it takes.
    ComponentEditorExtras(
      type: 'UiCustomComponent',
      summary: (c) {
        final id = (c as ui.UiCustomComponent).widgetId;
        return id.isEmpty ? 'nothing chosen' : id;
      },
      fieldEditors: {
        'widgetId': (c) => _WidgetIdField(
          label: c.label,
          value: c.value as String? ?? '',
          readOnly: c.readOnly,
          onChanged: c.onChanged,
        ),
        'props': (c) => _CustomWidgetProps(
          label: c.label,
          component: c.component as ui.UiCustomComponent,
          readOnly: c.readOnly,
          onChanged: c.onChanged,
        ),
      },
    ),
    ComponentEditorExtras(
      type: 'UiSlotComponent',
      fieldEditors: {
        // Saved as a word the flow layout reads; offered as the words it
        // knows, rather than an empty box to guess what to type into.
        'alignSelf': (c) {
          const follow = 'as the parent lays it';
          final value = c.value as String? ?? '';
          if (c.readOnly) {
            return ReadonlyRow(
              label: c.label,
              value: value.isEmpty ? follow : value,
            );
          }
          return DropdownEditorRow(
            label: c.label,
            value: value.isEmpty ? follow : value,
            options: const [follow, 'start', 'center', 'end', 'stretch'],
            onChanged: (v) => c.onChanged(v == follow ? '' : v),
          );
        },
      },
    ),
    ComponentEditorExtras(
      type: 'UiCanvasComponent',
      summary: (c) {
        final canvas = c as ui.UiCanvasComponent;
        final size =
            '${canvas.designSize.width.toInt()}'
            '×${canvas.designSize.height.toInt()}';
        return canvas.isScreen ? 'screen, $size' : size;
      },
      fieldEditors: {
        // Whether a screen is showing is the game's to say while it runs,
        // and is never saved with it: a box here would be ticked and lost.
        'visible': (c) =>
            ReadonlyRow(label: 'Showing', value: '▶ in Screens starts it open'),
      },
    ),
  ];
}

/// Which widget a `UiCustomComponent` is, chosen from what the game
/// registered.
class _WidgetIdField extends StatelessWidget {
  const _WidgetIdField({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final definition in ui.UiWidgets.all) definition.id,
      // A scene naming a widget this build does not have keeps its name,
      // so opening the inspector never quietly rewrites it.
      if (value.isNotEmpty && !ui.UiWidgets.has(value)) value,
    ];
    if (readOnly || ids.isEmpty) {
      return ReadonlyRow(
        label: label,
        value: value.isEmpty ? '(none registered)' : value,
      );
    }
    return DropdownEditorRow(
      label: label,
      value: ids.contains(value) ? value : ids.first,
      options: ids,
      searchable: ids.length > 8,
      onChanged: onChanged,
    );
  }
}

/// What the scene tells a custom widget: one row per property the widget
/// said it takes, rather than a map to hand-edit.
class _CustomWidgetProps extends StatelessWidget {
  const _CustomWidgetProps({
    required this.label,
    required this.component,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final ui.UiCustomComponent component;
  final bool readOnly;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final definition = ui.UiWidgets.of(component.widgetId);
    // Nothing known about this widget: the raw map is better than nothing,
    // and it is what a scene from another build leaves behind.
    if (definition == null || definition.props.isEmpty) {
      return CollectionEditor(
        label: label,
        value: component.props,
        readOnly: readOnly,
        onChanged: onChanged,
      );
    }
    void set(String name, String value) {
      onChanged({...component.props, name: value});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final prop in definition.props) ...[
          _propRow(prop, set),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _propRow(ui.UiWidgetProp prop, void Function(String, String) set) {
    final value = component.props[prop.name] ?? prop.defaultValue;
    if (readOnly) return ReadonlyRow(label: prop.label, value: value);
    return switch (prop.kind) {
      ui.UiPropKind.flag => BoolEditorRow(
        label: prop.label,
        value: value == 'true',
        onChanged: (v) => set(prop.name, '$v'),
      ),
      ui.UiPropKind.number => TextEditorRow(
        label: prop.label,
        initialValue: value,
        onSubmitted: (text) {
          final parsed = double.tryParse(text.trim());
          if (parsed != null) set(prop.name, text.trim());
        },
      ),
      ui.UiPropKind.color => ColorEditorRow(
        label: prop.label,
        paintStyle: jge.ShapePaintStyle(color: _colorOf(value)),
        onChanged: (style) => set(
          prop.name,
          '#${style.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
        ),
      ),
      ui.UiPropKind.asset => AssetRefEditorRow(
        label: prop.label,
        value: value,
        extensions: const ['png', 'jpg', 'jpeg', 'webp', 'json'],
        onChanged: (path) => set(prop.name, path),
      ),
      ui.UiPropKind.text => TextEditorRow(
        label: prop.label,
        initialValue: value,
        onSubmitted: (text) => set(prop.name, text),
      ),
    };
  }

  static Color _colorOf(String value) {
    final text = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.tryParse(text, radix: 16);
    if (parsed == null) return const Color(0xFFFFFFFF);
    return Color(text.length <= 6 ? 0xFF000000 | parsed : parsed);
  }
}
