// Actions: what a button does, built-in or the game's, per engine.

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

  group('actions', () {
    test('a list round-trips, and runs in order', () {
      const list = UiActionList([
        UiAction('signal', 'open'),
        UiAction('custom:log', 'hello'),
      ]);
      expect(UiActionList.fromJson(list.toJson()), list);
      expect(list.toJson().first, {'kind': 'signal', 'arg': 'open'});

      final ran = <String>[];
      UiActions.of(
        engineContext,
      ).register('log', (c) => ran.add('log:${c.argument}'));
      final signals = <String>[];
      final world = uiWorld(engineContext);
      addTearDown(world.dispose);
      final stop = world.context.signals.stream.listen(signals.add);
      addTearDown(stop.cancel);

      list.run(UiActionContext(world: world));
      expect(signals, ['open']);
      expect(ran, ['log:hello']);
    });

    test('built-ins reach the game through the host', () {
      final done = <String>[];
      UiActions.of(engineContext).host = UiActionHost(
        loadScene: (s) => done.add('scene:$s'),
        pause: () => done.add('pause'),
        showUi: (name, visible) => done.add('ui:$name=$visible'),
        back: () => done.add('back'),
      );
      final world = uiWorld(engineContext);
      for (final action in const [
        UiAction('scene.load', 'level_02'),
        UiAction('game.pause'),
        UiAction('ui.hide', 'HUD'),
        UiAction('ui.toggle', 'Menu'),
        UiAction('ui.back'),
      ]) {
        UiActions.of(engineContext).run(action, UiActionContext(world: world));
      }
      expect(done, [
        'scene:level_02',
        'pause',
        'ui:HUD=false',
        'ui:Menu=null',
        'back',
      ]);
    });

    test('an action nobody can carry out does nothing at all', () {
      final world = uiWorld(engineContext);
      // No host, no handler, an unknown kind: none of these may throw
      // mid-frame — a button is not worth taking the game down for.
      for (final action in const [
        UiAction('scene.load', 'x'),
        UiAction('custom:missing'),
        UiAction('from.a.newer.engine'),
        UiAction('none'),
      ]) {
        expect(
          () => UiActions.of(
            engineContext,
          ).run(action, UiActionContext(world: world)),
          returnsNormally,
        );
      }
    });

    test('a timeline action plays the entity it names', () {
      final world = uiWorld(engineContext);
      registerSpriteSystems(world);
      final player = TimelinePlayerComponent(
        inline: TimelineAsset(duration: 1),
      );
      world.createEntityWithComponents([
        TransformComponent(),
        player,
      ], name: 'Door');
      world.update(0);
      expect(player.isPlaying, isFalse);
      UiActions.of(engineContext).run(
        const UiAction('timeline.play', 'Door'),
        UiActionContext(world: world),
      );
      world.update(0);
      expect(player.isPlaying, isTrue);
    });
  });
}
