/// The root of a screen's UI.
library;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// How a canvas answers a screen that is not the size it was drawn for.
enum UiScaleMode {
  /// Pixels are pixels: a phone shows less of it than a desktop.
  none,

  /// Scaled so the design's width fits, whatever the height does.
  width,

  /// Scaled so the design's height fits.
  height,

  /// Scaled so the whole design fits, letterboxed if it must be — what
  /// keeps a HUD looking the same everywhere.
  fit;

  /// How much to scale a [design] to fill [screen].
  double scaleFor(Size design, Size screen) {
    if (design.width <= 0 || design.height <= 0) return 1;
    return switch (this) {
      none => 1,
      width => screen.width / design.width,
      height => screen.height / design.height,
      fit =>
        (screen.width / design.width) < (screen.height / design.height)
            ? screen.width / design.width
            : screen.height / design.height,
    };
  }
}

/// How a screen arrives and leaves.
enum UiTransition {
  none,
  fade,
  slideUp,
  slideLeft,
  scale;

  /// How long it takes.
  Duration get duration => this == UiTransition.none
      ? Duration.zero
      : const Duration(milliseconds: 220);
}

/// The root of a piece of interface: a HUD, a menu, a shop.
///
/// Everything under it in the entity hierarchy is laid out by real Flutter
/// widgets, so a text field is a text field and a list scrolls the way the
/// platform scrolls.
class UiCanvasComponent extends Component {
  UiCanvasComponent({
    this.designSize = const Size(1920, 1080),
    this.scaleMode = UiScaleMode.fit,
    this.safeArea = true,
    this.sortOrder = 0,
    this.theme = '',
    this.visible = true,
    this.isScreen = false,
    this.modal = false,
    this.closesOnBack = true,
    this.transition = UiTransition.fade,
    this.initialFocus = '',
  });

  /// The size this was laid out for. With a [scaleMode] other than
  /// [UiScaleMode.none], everything is scaled from here.
  Size designSize;

  /// How the design is scaled to the screen it is shown on.
  UiScaleMode scaleMode;

  /// Keep clear of notches and rounded corners.
  bool safeArea;

  /// Higher canvases draw over lower ones.
  int sortOrder;

  /// A `.uitheme.json`; empty takes the game's.
  String theme;

  /// Whether it is showing. The game's to say while it runs — opening a
  /// screen sets it — and never saved with a screen file.
  bool visible;

  /// A screen is pushed and popped like a page — a menu, a shop. A canvas
  /// that is not one is a layer that stays, like a HUD.
  bool isScreen;

  /// While this is up, the game beneath does not hear the pointer.
  bool modal;

  /// Whether a player's back — Escape, a pad's cancel, the system's back
  /// button — closes this screen when it is on top. Off, only its own
  /// buttons and the game close it: a level-complete banner, a
  /// lost-controller pause. A `ui.back` button still works.
  bool closesOnBack;

  /// How a screen comes and goes.
  UiTransition transition;

  /// The name of the entity under this that takes focus when it opens, so a
  /// screen can be used without a pointer.
  String initialFocus;

  /// Bumped when something here changes what is drawn.
  int get revision => _revision;
  int _revision = 0;

  void markDirty() => _revision++;

  @override
  String toString() =>
      'UiCanvas(${designSize.width.toInt()}×${designSize.height.toInt()}'
      '${isScreen ? ', screen' : ''})';
}
