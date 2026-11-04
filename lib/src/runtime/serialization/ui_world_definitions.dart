/// How world-space text and buttons are saved: the definitions for
/// [TextComponent] and [ButtonComponent], with the same type names and ids
/// the engine used to register, so a scene saved before the move loads
/// unchanged.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../components/button_component.dart';
import '../components/text_component.dart';
import '../components/ui_component.dart';
import '../components/ui_painters.dart';
import '../logic/ui_actions.dart';
import '../text/ui_text_style.dart';
import 'ui_field_types.dart';

abstract final class UiWorldDefinitions {
  /// [TextComponent]: text in the world, and everything about how it looks.
  static ComponentDefinition<TextComponent>
  get text => ComponentDefinition<TextComponent>(
    type: 'TextComponent',
    hints: const ComponentHints(
      name: 'Text',
      group: 'UI',
      description:
          'Text at this entity. It can read the game — "Coins: {coins}" — '
          'be looked up in the current language with @a.key, and carry tags '
          'like [b]bold[/b].',
      icon: Icons.text_fields,
      accentColor: Color(0xFF5C6BC0),
      fieldGroups: {
        'Content': ['textValue', 'styleRole'],
        'Look': ['style'],
        'Layout': ['w', 'h', 'align', 'overflow', 'wrap', 'maxLines', 'layer'],
        'Reveal': ['revealSpeed'],
      },
      fieldRows: [
        FieldRowHint('Size', {'w': 'W', 'h': 'H'}),
      ],
      fields: {
        'textValue': FieldHint(
          label: 'Text',
          description:
              'Tags: [b] [i] [color=#f80] [size=20] [icon=name] [wave] '
              '[shake]. Bindings: {coins}, {time:mm:ss}, {self.name}.',
        ),
        'styleRole': FieldHint(
          label: 'Role',
          description:
              'What kind of text this is. The theme decides what a role '
              'looks like, so restyling every label in the game is one '
              'file rather than every entity.',
        ),
        'style': FieldHint(
          label: 'Style',
          description:
              'What this text says for itself, over the role. Anything '
              'left unset is the role’s, shown greyed.',
        ),
        'w': FieldHint(
          label: 'Width',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
        'h': FieldHint(
          label: 'Height',
          scrub: ScrubHint(step: 4, fractionDigits: 0),
        ),
        'align': FieldHint(label: 'Align'),
        'overflow': FieldHint(
          label: 'Overflow',
          description: 'Shrink fits the text to the box.',
        ),
        'wrap': FieldHint(
          label: 'Wrap',
          description: 'Break lines at the width above.',
        ),
        'maxLines': FieldHint(
          label: 'Max lines',
          scrub: ScrubHint(integer: true),
        ),
        'revealSpeed': FieldHint(
          label: 'Type out',
          description: 'Characters a second; 0 shows it all at once.',
          scrub: ScrubHint(step: 1, fractionDigits: 0),
        ),
        'layer': FieldHint(
          label: 'Layer',
          description: 'Higher draws over lower, among text and buttons.',
          scrub: ScrubHint(integer: true),
        ),
      },
    ),
    painter: const TextComponentPainter(),
    id: 'text_effcff19',
    create: () => TextComponent(text: 'Text'),
    extent: const _UiExtent(),
    fields: [
      FieldDefinition(
        name: 'textValue',
        kind: UiFieldTypes.uiText,
        read: (c) => (c as TextComponent).text,
        write: (c, v) => (c as TextComponent).text = v as String? ?? '',
      ),
      FieldDefinition(
        name: 'style',
        kind: UiFieldTypes.uiTextStyle,
        read: (c) => (c as TextComponent).style,
        write: (c, v) => (c as TextComponent).style = v is UiTextStyle
            ? v
            : const UiTextStyle(),
      ),
      FieldDefinition(
        name: 'styleRole',
        kind: UiFieldTypes.uiStyleRole,
        read: (c) => (c as TextComponent).styleRole,
        write: (c, v) =>
            (c as TextComponent).styleRole = v as String? ?? 'body',
      ),
      FieldDefinition(
        name: 'w',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).size.width,
        write: (c, v) {
          final t = c as TextComponent;
          t.size = Size((v as num).toDouble(), t.size.height);
        },
        min: 0.0,
      ),
      FieldDefinition(
        name: 'h',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).size.height,
        write: (c, v) {
          final t = c as TextComponent;
          t.size = Size(t.size.width, (v as num).toDouble());
        },
        min: 0.0,
      ),
      FieldDefinition(
        name: 'align',
        kind: const EnumFieldType(
          UiTextAlign.values,
          fallback: UiTextAlign.center,
          id: 'enum.uiTextAlign',
        ),
        read: (c) => (c as TextComponent).align,
        write: (c, v) => (c as TextComponent).align = v as UiTextAlign,
      ),
      FieldDefinition(
        name: 'overflow',
        kind: const EnumFieldType(
          UiTextOverflow.values,
          fallback: UiTextOverflow.visible,
          id: 'enum.uiTextOverflow',
        ),
        read: (c) => (c as TextComponent).overflow,
        write: (c, v) => (c as TextComponent).overflow = v as UiTextOverflow,
      ),
      FieldDefinition(
        name: 'wrap',
        kind: FieldTypes.boolean,
        read: (c) => (c as TextComponent).wrap,
        write: (c, v) => (c as TextComponent).wrap = v as bool? ?? false,
      ),
      FieldDefinition(
        name: 'maxLines',
        kind: FieldTypes.integer,
        read: (c) => (c as TextComponent).maxLines,
        write: (c, v) => (c as TextComponent).maxLines = (v as num?)?.toInt(),
        min: 0,
      ),
      FieldDefinition(
        name: 'revealSpeed',
        kind: FieldTypes.decimal,
        read: (c) => (c as TextComponent).revealSpeed,
        write: (c, v) =>
            (c as TextComponent).revealSpeed = (v as num?)?.toDouble() ?? 0,
        min: 0,
      ),
      _layer(),
    ],
  );

  /// The draw (and, for a button, press) order among text and buttons.
  static FieldDefinition _layer() => FieldDefinition(
    name: 'layer',
    kind: FieldTypes.integer,
    read: (c) => (c as UIComponent).layer,
    write: (c, v) => (c as UIComponent).layer = (v as num?)?.toInt() ?? 0,
  );

  /// [ButtonComponent]: a button in the world, and what pressing it does.
  static ComponentDefinition<ButtonComponent> get button =>
      ComponentDefinition<ButtonComponent>(
        type: 'ButtonComponent',
        hints: const ComponentHints(
          name: 'Button',
          group: 'UI',
          description:
              'A button at this entity. What it does is a list of actions the '
              'scene holds by name, so it survives a save.',
          icon: Icons.smart_button,
          accentColor: Color(0xFF7E57C2),
          fieldGroups: {
            'Label': ['label', 'styleRole', 'labelStyle'],
            'Does': ['onPressed'],
            'Look': ['colorRole', 'color', 'borderColor', 'borderRadius'],
            'Size': ['w', 'h', 'layer', 'enabled'],
          },
          fieldRows: [
            FieldRowHint('Size', {'w': 'W', 'h': 'H'}),
          ],
          fields: {
            'label': FieldHint(
              label: 'Label',
              description: 'Bindings and tags work here as they do in a text.',
            ),
            'styleRole': FieldHint(
              label: 'Role',
              description: 'The theme style the label reads as.',
            ),
            'labelStyle': FieldHint(label: 'Label style'),
            'onPressed': FieldHint(
              label: 'On pressed',
              description: 'What happens when the button is released on.',
            ),
            'colorRole': FieldHint(
              label: 'Colour role',
              description: 'A colour from the theme: primary, danger, surface…',
            ),
            'color': FieldHint(
              label: 'Colour',
              description: 'Its own colour, which wins over the role.',
            ),
            'borderColor': FieldHint(label: 'Border'),
            'borderRadius': FieldHint(
              label: 'Corner',
              scrub: ScrubHint(step: 1, fractionDigits: 0),
            ),
            'w': FieldHint(
              label: 'Width',
              scrub: ScrubHint(step: 4, fractionDigits: 0),
            ),
            'h': FieldHint(
              label: 'Height',
              scrub: ScrubHint(step: 4, fractionDigits: 0),
            ),
            'layer': FieldHint(
              label: 'Layer',
              description:
                  'Higher draws over lower and takes the press where two '
                  'overlap.',
              scrub: ScrubHint(integer: true),
            ),
            'enabled': FieldHint(
              label: 'Can be pressed',
              description: 'Off draws it faded, and it does nothing.',
            ),
          },
        ),
        painter: const ButtonComponentPainter(),
        id: 'button_388d5c40',
        create: () => ButtonComponent(),
        extent: const _UiExtent(),
        fields: [
          FieldDefinition(
            name: 'label',
            kind: UiFieldTypes.uiText,
            read: (c) => (c as ButtonComponent).label,
            write: (c, v) => (c as ButtonComponent).label = v as String? ?? '',
          ),
          FieldDefinition(
            name: 'labelStyle',
            kind: UiFieldTypes.uiTextStyle,
            read: (c) => (c as ButtonComponent).labelStyle,
            write: (c, v) => (c as ButtonComponent).labelStyle =
                v is UiTextStyle ? v : const UiTextStyle(),
          ),
          FieldDefinition(
            name: 'styleRole',
            kind: UiFieldTypes.uiStyleRole,
            read: (c) => (c as ButtonComponent).styleRole,
            write: (c, v) =>
                (c as ButtonComponent).styleRole = v as String? ?? 'button',
          ),
          FieldDefinition(
            name: 'onPressed',
            kind: UiFieldTypes.uiActions,
            read: (c) => (c as ButtonComponent).onPressed,
            write: (c, v) => (c as ButtonComponent).onPressed =
                v is UiActionList ? v : UiActionList.empty,
          ),
          FieldDefinition(
            name: 'colorRole',
            kind: UiFieldTypes.uiColorRole,
            read: (c) => (c as ButtonComponent).colorRole,
            write: (c, v) =>
                (c as ButtonComponent).colorRole = v as String? ?? 'primary',
          ),
          FieldDefinition(
            name: 'color',
            kind: FieldTypes.color,
            read: (c) => (c as ButtonComponent).color,
            write: (c, v) => (c as ButtonComponent).color = v as Color?,
          ),
          FieldDefinition(
            name: 'borderColor',
            kind: FieldTypes.color,
            read: (c) => (c as ButtonComponent).borderColor,
            write: (c, v) => (c as ButtonComponent).borderColor = v as Color?,
          ),
          FieldDefinition(
            name: 'borderRadius',
            kind: FieldTypes.decimal,
            read: (c) => (c as ButtonComponent).borderRadius,
            write: (c, v) => (c as ButtonComponent).borderRadius =
                (v as num?)?.toDouble() ?? 8,
            min: 0,
          ),
          FieldDefinition(
            name: 'w',
            kind: FieldTypes.decimal,
            read: (c) => (c as ButtonComponent).size.width,
            write: (c, v) {
              final b = c as ButtonComponent;
              b.size = Size((v as num).toDouble(), b.size.height);
            },
            min: 0.0,
          ),
          FieldDefinition(
            name: 'h',
            kind: FieldTypes.decimal,
            read: (c) => (c as ButtonComponent).size.height,
            write: (c, v) {
              final b = c as ButtonComponent;
              b.size = Size(b.size.width, (v as num).toDouble());
            },
            min: 0.0,
          ),
          _layer(),
          FieldDefinition(
            name: 'enabled',
            kind: FieldTypes.boolean,
            read: (c) => (c as ButtonComponent).enabled,
            write: (c, v) =>
                (c as ButtonComponent).enabled = v as bool? ?? true,
          ),
        ],
      );

  /// Every definition above.
  static List<ComponentCodec> get all => [text, button];
}

/// A UI element is its own size.
class _UiExtent extends ComponentExtent {
  const _UiExtent();

  @override
  Size? sizeOf(Component component) => (component as UIComponent).size;

  @override
  bool scale(Component component, double sx, double sy) {
    final ui = component as UIComponent;
    ui.size = Size(ui.size.width * sx, ui.size.height * sy);
    return true;
  }
}
