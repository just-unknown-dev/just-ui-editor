/// How a game's screens reach the screen and the frame loop.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../layer/ui_input_bridge.dart';
import '../layer/ui_layer.dart';
import '../logic/ui_actions.dart';
import '../systems/ui_pointer_system.dart';
import 'ui_screens.dart';

/// Ticks the screens every frame — paused or not, since a pause menu has to
/// work while the game it paused is stopped — and makes them the actions'
/// defaults while attached.
class UiScreensPlugin extends EnginePlugin {
  UiScreensPlugin(this.screens);

  /// What it is registered on [Engine.plugins] as.
  static const String pluginId = 'just_ui_editor.screens';

  final UiScreens screens;

  late final UiActionHost _host = screens.host;

  @override
  String get id => pluginId;

  @override
  Future<void> attach(Engine engine) async {
    UiActions.defaults = _host;
  }

  @override
  void update(double dt) => screens.update(dt);

  @override
  void detach() {
    if (identical(UiActions.defaults, _host)) {
      UiActions.defaults = const UiActionHost();
    }
    screens.dispose();
  }
}

/// Draws the screens over the game, in every game widget showing it.
class UiScreensLayer extends GameLayer {
  const UiScreensLayer(
    this.screens, {
    this.input = const UiInputActions(),
    this.localise,
    this.onSound,
  });

  /// What it is registered on [Engine.layers] as.
  static const String layerId = 'just_ui_editor.screens';

  final UiScreens screens;

  /// The input actions that work menus from a gamepad; null leaves menus to
  /// keyboard, mouse and touch.
  final UiInputActions? input;

  final String Function(String key)? localise;
  final void Function(String path)? onSound;

  @override
  String get id => layerId;

  @override
  GameLayerController createController(Engine engine) =>
      _UiScreensView(this, engine);
}

class _UiScreensView extends GameLayerController {
  _UiScreensView(this.layer, this.engine) {
    if (layer.input case final actions?) {
      _bridge = UiInputBridge(
        input: engine.input,
        layer: () => _key.currentState,
        actions: actions,
      );
    }
  }

  final UiScreensLayer layer;
  final Engine engine;
  final GlobalKey<UiLayerState> _key = GlobalKey<UiLayerState>();
  UiInputBridge? _bridge;
  int _seen = -1;

  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
    // Watches the pointer over the whole game without taking it: buttons
    // placed in the world press through this, and nothing else changes.
    behavior: HitTestBehavior.translucent,
    onPointerHover: (e) => _point(e.localPosition),
    onPointerMove: (e) => _point(e.localPosition),
    onPointerDown: (e) {
      _down = true;
      _point(e.localPosition);
    },
    onPointerUp: (e) {
      _down = false;
      _point(e.localPosition);
    },
    onPointerCancel: (_) {
      _down = false;
      _pointer?.pointer = UiPointer.away;
    },
    child: UiLayer(
      key: _key,
      world: layer.screens.world,
      navigator: layer.screens.navigator,
      gameWorld: engine.world,
      localise: layer.localise,
      onSound: layer.onSound,
    ),
  );

  UiPointerSystem? get _pointer => engine.world.getSystem<UiPointerSystem>();

  /// Tells the world's buttons where the pointer is, in world units.
  void _point(Offset local) {
    final system = _pointer;
    if (system == null) return;
    final camera = engine.cameraSystem.mainCamera;
    system.pointer = UiPointer(
      position: camera.screenToWorld(local),
      isDown: _down,
      ray: camera.isPlanar ? null : camera.screenToWorldRay(local),
    );
  }

  @override
  void onFrame() {
    final state = _key.currentState;
    if (state == null) return;
    // Something the layer cannot see changed — a binding read a new
    // number, a text typed on — so the whole of it looks again.
    final changes = layer.screens.system.changes;
    if (changes != _seen) {
      _seen = changes;
      state.markDirty();
    }
    state.sync();
  }

  @override
  void dispose() => _bridge?.dispose();
}
