// What the screen-space components save, and read back.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';

/// The engine's and the interface's definitions, as a game's engine has
/// them.
final _uiDefinitions = EngineContext(
  extensions: const [JustGameUi.extension],
).definitions;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what is saved', () {
    final definitions = EngineContext(
      extensions: const [JustGameUi.extension],
    ).definitions;

    T roundTrip<T extends Component>(String type, T component) {
      final definition = definitions.definitionByType(type)!;
      final json = jsonDecode(jsonEncode(definition.encode(component)));
      return definition.decode((json as Map).cast<String, dynamic>()) as T;
    }

    test('a panel\'s gradient', () {
      final back = roundTrip(
        'UiPanelComponent',
        UiPanelComponent(
          gradient: const [Color(0xFFFF0000), Color(0xFF0000FF)],
        ),
      );
      expect(back.gradient, const [Color(0xFFFF0000), Color(0xFF0000FF)]);

      final written = definitions.definitionByType('UiPanelComponent')!.decode({
        'type': 'UiPanelComponent',
        'fields': {
          'gradient': ['#f00', 'nonsense', '#ff00ff00'],
        },
      });
      expect((written as UiPanelComponent).gradient, const [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
      ]);
    });

    test('a world text\'s layer, and a button\'s layer and switch', () {
      final text = roundTrip(
        'UiTextComponent',
        UiTextComponent(text: 'Sign', layer: 3),
      );
      expect(text.layer, 3);
      final button = roundTrip(
        'UiButtonComponent',
        UiButtonComponent(layer: 2, enabled: false),
      );
      expect((button.layer, button.enabled), (2, false));
    });

    testWidgets('a panel\'s picture is drawn', (tester) async {
      final world = uiWorld();
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [
        UiPanelComponent(image: 'assets/none.png'),
        fillSlot(),
      ]);

      await showLayer(tester, world);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration?)?.image != null,
        ),
        findsOneWidget,
      );
    });
  });

  group('saved and read back', () {
    ComponentDefinition definitionFor(String type) =>
        _uiDefinitions.definitionByType(type)!;

    /// Saves a component the way a scene does, then loads it back.
    T roundTrip<T extends Component>(String type, T component, T fresh) {
      final definition = definitionFor(type);
      final saved = {
        for (final f in definition.fields) f.name: f.encodeFrom(component),
      };
      for (final f in definition.fields) {
        f.decodeInto(fresh, saved[f.name]);
      }
      return fresh;
    }

    group('what a screen saves', () {
      test('a canvas keeps everything it was given', () {
        final canvas = UiCanvasComponent(
          designSize: const Size(1280, 720),
          scaleMode: UiScaleMode.width,
          safeArea: false,
          sortOrder: 3,
          theme: 'assets/ui/dark.uitheme.json',
          visible: false,
          isScreen: true,
          modal: true,
          closesOnBack: false,
          transition: UiTransition.slideUp,
          initialFocus: 'PlayButton',
        );

        final loaded = roundTrip(
          'UiCanvasComponent',
          canvas,
          UiCanvasComponent(),
        );

        expect(loaded.designSize, const Size(1280, 720));
        expect(loaded.scaleMode, UiScaleMode.width);
        expect(loaded.safeArea, isFalse);
        expect(loaded.sortOrder, 3);
        expect(loaded.theme, 'assets/ui/dark.uitheme.json');
        expect(loaded.visible, isFalse);
        expect(loaded.isScreen, isTrue);
        expect(loaded.modal, isTrue);
        expect(loaded.closesOnBack, isFalse);
        expect(loaded.transition, UiTransition.slideUp);
        expect(loaded.initialFocus, 'PlayButton');
      });

      test('a canvas saved before "Closes on Back" closes on Back', () {
        final definition = _uiDefinitions.definitionByType(
          'UiCanvasComponent',
        )!;
        final saved = definition.encode(
          UiCanvasComponent(isScreen: true, closesOnBack: false),
        );
        expect(saved['fields'], containsPair('closesOnBack', false));
        (saved['fields'] as Map).remove('closesOnBack');

        final loaded = definition.decode(saved) as UiCanvasComponent;

        expect(loaded.isScreen, isTrue);
        expect(loaded.closesOnBack, isTrue);
      });

      test('a slot keeps where it sits, anchors and all', () {
        final slot = UiSlotComponent(
          mode: UiSlotMode.anchored,
          anchor: UiAnchor.bottomRight,
          pivot: const Offset(1, 1),
          offset: const Offset(-24, -16),
          size: const Size(120, 32),
          margin: const EdgeInsets.fromLTRB(1, 2, 3, 4),
          flex: 2,
          alignSelf: 'stretch',
          opacity: 0.5,
          visible: false,
          ignorePointer: true,
          heroTag: 'coin',
        );

        final loaded = roundTrip('UiSlotComponent', slot, UiSlotComponent());

        expect(loaded.mode, UiSlotMode.anchored);
        expect(loaded.anchor, UiAnchor.bottomRight);
        expect(loaded.anchor.presetName, 'bottomRight');
        expect(loaded.pivot, const Offset(1, 1));
        expect(loaded.offset, const Offset(-24, -16));
        expect(loaded.size, const Size(120, 32));
        expect(loaded.margin, const EdgeInsets.fromLTRB(1, 2, 3, 4));
        expect(loaded.flex, 2);
        expect(loaded.alignSelf, 'stretch');
        expect(loaded.opacity, 0.5);
        expect(loaded.visible, isFalse);
        expect(loaded.ignorePointer, isTrue);
        expect(loaded.heroTag, 'coin');
      });

      test('a container keeps how it lays out', () {
        final layout = UiLayoutComponent(
          kind: UiLayoutKind.grid,
          mainAxis: UiFlexAlign.spaceBetween,
          crossAxis: UiFlexAlign.stretch,
          spacing: 12,
          padding: const EdgeInsets.all(6),
          columns: 4,
          tight: true,
        );

        final loaded = roundTrip(
          'UiLayoutComponent',
          layout,
          UiLayoutComponent(),
        );

        expect(loaded.kind, UiLayoutKind.grid);
        expect(loaded.mainAxis, UiFlexAlign.spaceBetween);
        expect(loaded.crossAxis, UiFlexAlign.stretch);
        expect(loaded.spacing, 12);
        expect(loaded.padding, const EdgeInsets.all(6));
        expect(loaded.columns, 4);
        expect(loaded.tight, isTrue);
      });

      test('a panel keeps its look', () {
        final panel = UiPanelComponent(
          colorRole: 'danger',
          color: const Color(0xFF102030),
          borderColor: const Color(0xFFAABBCC),
          borderWidth: 2,
          radius: 14,
          shadowBlur: 8,
          blur: 3,
          image: 'assets/ui/frame.png',
          nineSlice: const EdgeInsets.all(12),
        );

        final loaded = roundTrip('UiPanelComponent', panel, UiPanelComponent());

        expect(loaded.colorRole, 'danger');
        expect(loaded.color, const Color(0xFF102030));
        expect(loaded.borderColor, const Color(0xFFAABBCC));
        expect(loaded.borderWidth, 2);
        expect(loaded.radius, 14);
        expect(loaded.shadowBlur, 8);
        expect(loaded.blur, 3);
        expect(loaded.image, 'assets/ui/frame.png');
        expect(loaded.nineSlice, const EdgeInsets.all(12));
      });

      test('the controls keep what they do', () {
        final toggle = roundTrip(
          'UiToggleComponent',
          UiToggleComponent(
            value: true,
            label: 'Music',
            binding: 'settings.music',
            onChanged: const UiActionList([UiAction('signal', 'music')]),
          ),
          UiToggleComponent(),
        );
        expect(toggle.value, isTrue);
        expect(toggle.label, 'Music');
        expect(toggle.binding, 'settings.music');
        expect(toggle.onChanged.actions.single.kind, 'signal');
        expect(toggle.onChanged.actions.single.argument, 'music');

        final slider = roundTrip(
          'UiSliderComponent',
          UiSliderComponent(value: 0.25, min: -1, max: 3, steps: 8),
          UiSliderComponent(),
        );
        expect(slider.value, 0.25);
        expect(slider.min, -1);
        expect(slider.max, 3);
        expect(slider.steps, 8);

        final field = roundTrip(
          'UiTextFieldComponent',
          UiTextFieldComponent(
            value: 'Ada',
            hint: 'Your name',
            maxLength: 12,
            obscure: true,
          ),
          UiTextFieldComponent(),
        );
        expect(field.value, 'Ada');
        expect(field.hint, 'Your name');
        expect(field.maxLength, 12);
        expect(field.obscure, isTrue);

        final dropdown = roundTrip(
          'UiDropdownComponent',
          UiDropdownComponent(
            value: 'medium',
            options: ['low', 'medium', 'high'],
          ),
          UiDropdownComponent(),
        );
        expect(dropdown.value, 'medium');
        expect(dropdown.options, ['low', 'medium', 'high']);

        final bar = roundTrip(
          'UiProgressComponent',
          UiProgressComponent(
            value: 0.3,
            binding: 'health',
            maxBinding: 'maxHealth',
            radial: true,
            thickness: 5,
          ),
          UiProgressComponent(),
        );
        expect(bar.value, 0.3);
        expect(bar.binding, 'health');
        expect(bar.maxBinding, 'maxHealth');
        expect(bar.radial, isTrue);
        expect(bar.thickness, 5);
      });

      test('a custom widget keeps which widget and what it was told', () {
        final loaded = roundTrip(
          'UiCustomComponent',
          UiCustomComponent(
            widgetId: 'inventory_grid',
            props: {'columns': '4', 'title': 'Bag'},
          ),
          UiCustomComponent(),
        );

        expect(loaded.widgetId, 'inventory_grid');
        expect(loaded.props, {'columns': '4', 'title': 'Bag'});
      });

      test('every screen component is in the registry, under UI', () {
        for (final type in [
          'UiCanvasComponent',
          'UiSlotComponent',
          'UiLayoutComponent',
          'UiPanelComponent',
          'UiImageComponent',
          'UiProgressComponent',
          'UiToggleComponent',
          'UiSliderComponent',
          'UiTextFieldComponent',
          'UiDropdownComponent',
          'UiCustomComponent',
          'UiSpacerComponent',
        ]) {
          final definition = definitionFor(type);
          expect(definition.hints.group, 'UI', reason: type);
          // Anything the inspector shows needs a label to show it under.
          for (final field in definition.fields) {
            expect(
              definition.hints.fields[field.name]?.label,
              isNotNull,
              reason: '$type.${field.name} has no label',
            );
          }
        }
      });
    });
  });
}
