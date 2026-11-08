// A screen as a route of the layer's own navigator.
part of 'ui_layer.dart';

/// Asking to go back one screen — Escape, or a gamepad's cancel.
class _UiBackIntent extends Intent {
  const _UiBackIntent();
}

/// Escape: closes the screen on top — unless that screen does not close on
/// Back, and then it is switched off, so the key goes on to the game as
/// any other key a layer does not want.
class _UiBackAction extends Action<_UiBackIntent> {
  _UiBackAction(this._layer);

  final UiLayerState _layer;

  @override
  bool isEnabled(_UiBackIntent intent) => _layer.navigator.canGoBack;

  @override
  Object? invoke(_UiBackIntent intent) {
    if (_layer.navigator.handleBack()) _layer.markDirty();
    return null;
  }
}

/// A screen's route.
///
/// A `PageRoute` is what buys transitions, a focus scope and Hero flights,
/// but it also lays a barrier over everything beneath it — and beneath
/// this one is the game. A screen that is not modal drops that barrier, so
/// a HUD-like screen leaves the world clickable; a modal one keeps it, and
/// that barrier *is* the input gate.
class _UiRoute extends PageRouteBuilder<void> {
  _UiRoute({
    required super.pageBuilder,
    super.settings,
    // The game is behind every screen, so none of them is ever opaque —
    // an opaque route stops what is under it being drawn at all.
  }) : super(opaque: false);

  /// The canvas this route shows, as it is now: the navigator hands a
  /// route each newer page with the same key, so a screen made modal while
  /// open, or given another transition, changes this route rather than
  /// making a second one — two routes building one screen would build its
  /// widgets twice at once.
  UiCanvasComponent? get _canvas => switch (settings) {
    final _UiScreenPage page => page.canvas,
    _ => null,
  };

  /// A modal screen is the only thing the pointer can reach; anything else
  /// lets it through to the game underneath.
  bool get gatesInput => _canvas?.modal ?? false;

  @override
  Color? get barrierColor => gatesInput ? const Color(0x66000000) : null;

  @override
  Duration get transitionDuration =>
      _canvas?.transition.duration ?? Duration.zero;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final canvas = _canvas;
    if (canvas == null) return child;
    return _UiScreenPage._transition(canvas.transition, animation, child);
  }

  /// A page route always lays a barrier over everything beneath it — and
  /// beneath these is the game. Kept, and rebuilt whenever the page
  /// changes, but only a modal screen's stops the pointer.
  @override
  Widget buildModalBarrier() => gatesInput
      ? super.buildModalBarrier()
      : const IgnorePointer(child: SizedBox.expand());
}

/// What sits under the screens: nothing, so that closing the last one
/// still has somewhere to animate back to.
class _UiRootPage extends Page<void> {
  const _UiRootPage() : super(key: const ValueKey('ui.root'));

  @override
  Route<void> createRoute(BuildContext context) => _UiRoute(
    settings: this,
    // Nothing is drawn here, so nothing should take the pointer either.
    pageBuilder: (context, animation, secondary) =>
        const IgnorePointer(child: SizedBox.expand()),
  );
}

/// One screen-space canvas, as a page.
///
/// Being a real route is what buys the transitions, the focus scope, the
/// back button and Hero flights — none of which are worth writing again.
class _UiScreenPage extends Page<void> {
  _UiScreenPage({
    required this.entity,
    required this.canvas,
    required this.builder,
  }) : super(key: ValueKey(('ui.screen', entity.world, entity.id)));

  final Entity entity;
  final UiCanvasComponent canvas;
  final WidgetBuilder builder;

  @override
  Route<void> createRoute(BuildContext context) => _UiRoute(
    settings: this,
    pageBuilder: (context, animation, secondary) => builder(context),
  );

  static Widget _transition(
    UiTransition kind,
    Animation<double> animation,
    Widget child,
  ) {
    final eased = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return switch (kind) {
      UiTransition.none => child,
      UiTransition.fade => FadeTransition(opacity: eased, child: child),
      UiTransition.slideUp => SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(eased),
        child: FadeTransition(opacity: eased, child: child),
      ),
      UiTransition.slideLeft => SlideTransition(
        position: Tween(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(eased),
        child: FadeTransition(opacity: eased, child: child),
      ),
      UiTransition.scale => ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(eased),
        child: FadeTransition(opacity: eased, child: child),
      ),
    };
  }
}
