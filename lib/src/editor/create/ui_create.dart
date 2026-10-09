/// Making new pieces of interface.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/screen/ui_slot_component.dart';
import '../../runtime/components/text_component.dart';
import '../../runtime/layer/ui_widgets.dart';
import '../document/ui_screen_document.dart';

/// One thing the widget palette offers.
class UiCreateOption {
  const UiCreateOption(
    this.id,
    this.label,
    this.icon, {
    this.group = '',
    this.description = '',
  });

  /// What [UiCreate] is asked for — `text`, `row`, `custom:inventory`.
  final String id;
  final String label;
  final IconData icon;

  /// Containers, Elements, or what the game brought.
  final String group;
  final String description;
}

/// What can be made: the built-in kinds, then the game's own widgets.
abstract final class UiCreateOptions {
  static const String containers = 'Containers';
  static const String elements = 'Elements';
  static const String fromTheGame = 'From the game';

  static const List<UiCreateOption> builtIns = [
    UiCreateOption(
      'panel',
      'Panel',
      Icons.rectangle_outlined,
      group: containers,
      description: 'A card: a colour, a border, rounded corners.',
    ),
    UiCreateOption(
      'column',
      'Column',
      Icons.view_agenda,
      group: containers,
      description: 'Lays its children out top to bottom.',
    ),
    UiCreateOption(
      'row',
      'Row',
      Icons.view_column,
      group: containers,
      description: 'Lays its children out left to right.',
    ),
    UiCreateOption(
      'stack',
      'Stack',
      Icons.layers,
      group: containers,
      description: 'Children pinned by anchors, on top of each other.',
    ),
    UiCreateOption(
      'wrap',
      'Wrap',
      Icons.wrap_text,
      group: containers,
      description: 'A row that runs on to the next line.',
    ),
    UiCreateOption(
      'grid',
      'Grid',
      Icons.grid_view,
      group: containers,
      description: 'Children in columns of equal width.',
    ),
    UiCreateOption(
      'scroll',
      'Scroll',
      Icons.swap_vert,
      group: containers,
      description: 'A column that scrolls when it is too long.',
    ),
    UiCreateOption(
      'text',
      'Text',
      Icons.text_fields,
      group: elements,
      description: 'Words — which can read the game: "Coins: {coins}".',
    ),
    UiCreateOption(
      'button',
      'Button',
      Icons.smart_button,
      group: elements,
      description: 'Pressed with a pointer, a key or a pad; runs actions.',
    ),
    UiCreateOption(
      'image',
      'Image',
      Icons.image_outlined,
      group: elements,
      description: 'A picture, or a frame of a sprite sheet.',
    ),
    UiCreateOption(
      'progress',
      'Progress bar',
      Icons.linear_scale,
      group: elements,
      description: 'A bar or ring that fills with a number from the game.',
    ),
    UiCreateOption(
      'toggle',
      'Toggle',
      Icons.toggle_on_outlined,
      group: elements,
      description: 'On or off.',
    ),
    UiCreateOption(
      'slider',
      'Slider',
      Icons.tune,
      group: elements,
      description: 'A number chosen by dragging.',
    ),
    UiCreateOption(
      'field',
      'Text field',
      Icons.keyboard_alt_outlined,
      group: elements,
      description: 'Somewhere to type: a name, a code.',
    ),
    UiCreateOption(
      'dropdown',
      'Dropdown',
      Icons.arrow_drop_down_circle_outlined,
      group: elements,
      description: 'One choice from a list.',
    ),
    UiCreateOption(
      'spacer',
      'Spacer',
      Icons.space_bar,
      group: elements,
      description: 'Room between things in a row or a column.',
    ),
  ];

  /// The built-ins, then the widgets the running game registered.
  static List<UiCreateOption> get all => [
    ...builtIns,
    for (final definition in UiWidgets.all)
      UiCreateOption(
        'custom:${definition.id}',
        definition.label,
        definition.icon ?? Icons.extension_outlined,
        group: fromTheGame,
        description: definition.description,
      ),
  ];

  /// The option for [id], or null.
  static UiCreateOption? byId(String id) {
    for (final option in all) {
      if (option.id == id) return option;
    }
    return null;
  }
}

/// The icon a piece of interface is listed with — the one it is made with.
IconData? uiIconFor(Entity entity) {
  if (entity.getComponent<UiCanvasComponent>() case final canvas?) {
    return canvas.isScreen ? Icons.web_asset_outlined : Icons.web_asset;
  }
  if (entity.getComponent<UiCustomComponent>() case final custom?) {
    return UiWidgets.of(custom.widgetId)?.icon ?? Icons.extension_outlined;
  }
  if (entity.getComponent<UiLayoutComponent>() case final layout?) {
    return switch (layout.kind) {
      UiLayoutKind.row => Icons.view_column,
      UiLayoutKind.column => Icons.view_agenda,
      UiLayoutKind.stack => Icons.layers,
      UiLayoutKind.wrap => Icons.wrap_text,
      UiLayoutKind.grid => Icons.grid_view,
      UiLayoutKind.scroll => Icons.swap_vert,
      UiLayoutKind.safeArea => Icons.crop_free,
    };
  }
  if (entity.hasComponent<TextComponent>()) return Icons.text_fields;
  if (entity.hasComponent<ButtonComponent>()) return Icons.smart_button;
  if (entity.hasComponent<UiImageComponent>()) return Icons.image_outlined;
  if (entity.hasComponent<UiProgressComponent>()) return Icons.linear_scale;
  if (entity.hasComponent<UiToggleComponent>()) {
    return Icons.toggle_on_outlined;
  }
  if (entity.hasComponent<UiSliderComponent>()) return Icons.tune;
  if (entity.hasComponent<UiTextFieldComponent>()) {
    return Icons.keyboard_alt_outlined;
  }
  if (entity.hasComponent<UiDropdownComponent>()) {
    return Icons.arrow_drop_down_circle_outlined;
  }
  if (entity.hasComponent<UiSpacerComponent>()) return Icons.space_bar;
  if (entity.hasComponent<UiPanelComponent>()) {
    return Icons.rectangle_outlined;
  }
  return entity.hasComponent<UiSlotComponent>() ? Icons.crop_square : null;
}

/// How a new piece of interface is made, where it goes, and how it sits
/// there.
abstract final class UiCreate {
  /// Whether [entity] holds children the way a container does.
  static bool isContainer(Entity entity) =>
      entity.hasComponent<UiCanvasComponent>() ||
      entity.hasComponent<UiLayoutComponent>() ||
      entity.hasComponent<UiPanelComponent>();

  /// Whether [entity]'s children are pinned by anchors — the canvas, a
  /// stack — rather than laid out one after another.
  static bool placesByAnchor(Entity entity) {
    if (entity.hasComponent<UiCanvasComponent>()) return true;
    final layout = entity.getComponent<UiLayoutComponent>();
    return layout?.kind == UiLayoutKind.stack;
  }

  /// Where something new goes when [selected] is selected: into it when it
  /// is a container, beside it otherwise, and into the canvas when nothing
  /// is — never inside a text or a button, which draw no children.
  static Entity parentFor(UiScreenDocument document, Entity? selected) {
    final world = document.world;
    Entity? at = selected;
    while (at != null) {
      if (isContainer(at)) return at;
      final parentId = at.getComponent<ParentComponent>()?.parentId;
      at = parentId == null ? null : world.getEntity(parentId);
    }
    return document.canvas;
  }

  /// The components of a new [kind] going into [parent].
  ///
  /// Under the canvas or a stack it is pinned: centred, or with its middle
  /// at [at] (design pixels in the parent) when it was dropped somewhere.
  /// Under a row, a column or a panel it joins the flow. A container
  /// dropped on the canvas gets room to hold things.
  static List<Component> componentsFor(
    String kind, {
    required Entity parent,
    Offset? at,
  }) {
    final anchored = placesByAnchor(parent);
    final size = _sizeOf(kind);
    UiSlotComponent slot() => anchored
        ? UiSlotComponent(
            mode: UiSlotMode.anchored,
            anchor: at == null ? UiAnchor.center : UiAnchor.topLeft,
            offset: at ?? Offset.zero,
            size: size,
          )
        : UiSlotComponent(size: size);

    if (kind.startsWith('custom:')) {
      final id = kind.substring(7);
      final definition = UiWidgets.of(id);
      return [
        UiCustomComponent(
          widgetId: id,
          props: {
            for (final prop in definition?.props ?? const <UiWidgetProp>[])
              if (prop.defaultValue.isNotEmpty) prop.name: prop.defaultValue,
          },
        ),
        slot(),
      ];
    }
    return switch (kind) {
      'panel' => [UiPanelComponent(), slot(), ChildrenComponent()],
      'row' => _layout(UiLayoutKind.row, slot()),
      'column' => _layout(UiLayoutKind.column, slot()),
      'stack' => _layout(UiLayoutKind.stack, slot()),
      'wrap' => _layout(UiLayoutKind.wrap, slot()),
      'grid' => _layout(UiLayoutKind.grid, slot()),
      'scroll' => _layout(UiLayoutKind.scroll, slot()),
      'text' => [TextComponent(text: 'Text', size: size), slot()],
      'button' => [ButtonComponent(label: 'Button', size: size), slot()],
      'image' => [UiImageComponent(), slot()],
      'progress' => [UiProgressComponent(), slot()],
      'toggle' => [UiToggleComponent(label: 'Toggle'), slot()],
      'slider' => [UiSliderComponent(), slot()],
      'field' => [UiTextFieldComponent(hint: 'Type here'), slot()],
      'dropdown' => [
        UiDropdownComponent(options: ['One', 'Two']),
        slot(),
      ],
      'spacer' => [UiSpacerComponent(), slot()],
      // Something from a newer editor: an empty element is easier to
      // delete than a crash is to recover from.
      _ => [slot()],
    };
  }

  static List<Component> _layout(UiLayoutKind kind, UiSlotComponent slot) => [
    UiLayoutComponent(kind: kind),
    slot,
    ChildrenComponent(),
  ];

  static Size _sizeOf(String kind) => switch (kind) {
    'panel' => const Size(360, 240),
    'row' => const Size(360, 64),
    'column' || 'stack' || 'scroll' => const Size(240, 240),
    'wrap' || 'grid' => const Size(320, 200),
    'text' => const Size(200, 40),
    'button' => const Size(180, 52),
    'image' => const Size(96, 96),
    'progress' => const Size(220, 16),
    'toggle' => const Size(180, 40),
    'slider' => const Size(220, 40),
    'field' => const Size(260, 52),
    'dropdown' => const Size(220, 52),
    'spacer' => const Size(16, 16),
    _ => const Size(160, 48),
  };

  /// The name a new [kind] is given, before it is made unique.
  static String baseNameFor(String kind) {
    if (kind.startsWith('custom:')) {
      final option = UiCreateOptions.byId(kind);
      return (option?.label ?? kind.substring(7)).replaceAll(' ', '');
    }
    final option = UiCreateOptions.byId(kind);
    return (option?.label ?? 'Element').replaceAll(' ', '');
  }

  /// Makes a [kind] in [document] — into [parent], or where the selection
  /// says — as one undoable step, and selects it.
  static Entity? create(
    UiScreenDocument document,
    String kind, {
    Entity? parent,
    Offset? at,
    int index = -1,
  }) {
    final into =
        parent ?? parentFor(document, document.sceneState.selectedEntity.value);
    final name = document.uniqueName(baseNameFor(kind));
    final components = componentsFor(kind, parent: into, at: at);
    Entity? made;
    document.history.push(
      CreateEntitiesCommand(
        label: 'Add $name',
        world: document.world,
        sceneState: document.sceneState,
        specs: [
          EntitySpec(
            name: name,
            componentsJson: document.codec.encodeAll(components),
            codec: document.codec,
            parentName: into.name,
            siblingIndex: index,
          ),
        ],
        onCreated: (created) {
          if (created.isEmpty) return;
          made = created.first;
          document.sceneState.selectEntity(created.first);
        },
      ),
    );
    return made;
  }
}
