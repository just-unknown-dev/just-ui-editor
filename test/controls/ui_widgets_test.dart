// Widgets a game brings: building, props, and what a missing one does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

import '../support/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What this test's interface worlds share: their engine's
  /// bindings, actions, widgets, icons, themes and fonts.
  late EngineContext engineContext;
  setUp(
    () =>
        engineContext = EngineContext(extensions: const [JustGameUi.extension]),
  );

  group('a custom widget', () {
    testWidgets('acts through the layer it is in', (tester) async {
      final pushed = <String>[];
      World? gameWorld;
      UiWidgets.of(engineContext).register(
        UiWidgetDefinition(
          id: 'probe',
          label: 'Probe',
          build: (context) {
            gameWorld = context.gameWorld;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.run(
                const UiActionList([UiAction('ui.push', 'Shop')]),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      );
      final world = uiWorld(engineContext);
      final hud = addCanvas(world, 'Hud');
      addUnder(world, hud, [UiCustomComponent(widgetId: 'probe'), fillSlot()]);
      final game = uiWorld(engineContext);
      final key = GlobalKey<UiLayerState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: UiLayer(
                key: key,
                world: world,
                gameWorld: game,
                actionHost: UiActionHost(pushScreen: pushed.add),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();

      expect(pushed, ['Shop'], reason: 'the layer\'s host, not the game\'s');
      expect(gameWorld, same(game));
    });
  });
}
