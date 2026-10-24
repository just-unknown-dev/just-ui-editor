/// How a game's screens reach the screen and the frame loop.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../components/screen/ui_canvas_component.dart';
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
        // While the game plays on under a screen that is not modal — a
        // banner, a dialogue line — the stick and the jump button are the
        // player's, not the menu's.
        takesPad: (ui) =>
            engine.isPaused ||
            (ui.navigator.top?.getComponent<UiCanvasComponent>()?.modal ??
                false),
      );
    }
  }

  final UiScreensLayer layer;
  final Engine engine;
  final GlobalKey<UiLayerState> _key = GlobalKey<UiLayerState>();
  UiInputBridge? _bridge;

  /// The pointer the world's buttons follow — the first one down, so a
  /// second finger (one held on a joystick, say) neither starts nor ends
  /// a press — and where it is on screen, kept so its place in the world
  /// can be worked out again as the camera moves.
  int? _following;
  Offset? _at;
  bool _down = false;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Under the interface, not around it: only what the screens let
      // through — not a press on a HUD button, not a tap on a modal
      // screen's barrier — reaches the buttons in the world. It takes
      // nothing itself, so the game underneath hears the pointer too.
      Positioned.fill(
        child: MouseRegion(
          opaque: false,
          onExit: (_) {
            if (_following == null) _move(null);
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: (e) {
              if (_following == null) _move(e.localPosition);
            },
            onPointerMove: (e) {
              if (e.pointer == _following) _move(e.localPosition);
            },
            onPointerDown: (e) {
              if (_following != null) return;
              _following = e.pointer;
              _down = true;
              _move(e.localPosition);
            },
            onPointerUp: (e) {
              if (e.pointer != _following) return;
              _following = null;
              _down = false;
              _move(e.localPosition);
              // A finger that has lifted is nowhere: nothing stays hovered.
              if (e.kind != PointerDeviceKind.mouse) _move(null);
            },
            onPointerCancel: (e) {
              if (e.pointer != _following) return;
              _following = null;
              _down = false;
              _move(null);
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
      Positioned.fill(
        child: UiLayer(
          key: _key,
          world: layer.screens.world,
          navigator: layer.screens.navigator,
          gameWorld: engine.world,
          localise: layer.localise,
          onSound: layer.onSound,
          handlesBack: true,
        ),
      ),
    ],
  );

  UiPointerSystem? get _pointer => engine.world.getSystem<UiPointerSystem>();

  void _move(Offset? at) {
    _at = at;
    _send();
  }

  /// Tells the world's buttons where the pointer is, in world units.
  void _send() {
    final system = _pointer;
    if (system == null) return;
    final at = _at;
    if (at == null) {
      system.pointer = UiPointer(isDown: _down);
      return;
    }
    final camera = engine.cameraSystem.mainCamera;
    system.pointer = UiPointer(
      position: camera.screenToWorld(at),
      isDown: _down,
      ray: camera.isPlanar ? null : camera.screenToWorldRay(at),
    );
  }

  @override
  void onFrame() {
    // The camera may have moved under a still pointer: where it points in
    // the world is worked out again. A press made while the game is paused
    // is the menu's, not the world's.
    if (engine.isPaused) {
      _pointer?.discardPending();
    } else if (_at != null) {
      _send();
    }
    // Each node watches what it shows, bindings and typing included, so a
    // frame where nothing about the screens' shape changed rebuilds only
    // the nodes that read differently.
    _key.currentState?.sync();
  }

  @override
  void dispose() => _bridge?.dispose();
}
