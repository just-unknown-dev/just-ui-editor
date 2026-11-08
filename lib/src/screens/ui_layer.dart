/// The scene's UI, as real Flutter widgets.
///
/// Every screen-space canvas in the world is built here: the entity tree
/// becomes a widget tree, so a text field is a real `TextField` with an
/// IME behind it, a list scrolls with the platform's physics, and a game's
/// own widgets sit beside the built-in ones.
library;

import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/gestures.dart'
    show GestureRecognizer, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_game_engine/just_game_engine.dart';

import '../bindings/bindings.dart';
import '../controls/controls.dart';
import '../layout/layout.dart';
import '../text/text.dart';
import '../theme/theme.dart';
import 'ui_navigator.dart';

part 'ui_atlas_image.dart';
part 'ui_element_builders.dart';
part 'ui_focus_ring.dart';
part 'ui_node_boxes.dart';
part 'ui_painted_text.dart';
part 'ui_panel_image.dart';
part 'ui_screen_route.dart';

/// Draws every screen-space canvas in [world], over the game.
class UiLayer extends StatefulWidget {
  const UiLayer({
    super.key,
    required this.world,
    this.localize,
    this.themeOverride,
    this.onSound,
    this.nodes,
    this.navigator,
    this.gameWorld,
    this.actionHost,
    this.handlesBack = false,
  });

  /// Where the canvases are.
  final World world;

  /// Which screens are open. Shared with whoever else opens and closes them
  /// — the game's screens, through `ui.push`. Without one the layer keeps
  /// its own, and its buttons' `ui.*` actions reach it and nothing else.
  final UiNavigator? navigator;

  /// The game's world, when [world] is the interface's own: an action
  /// naming something (a timeline to play) looks there too.
  final World? gameWorld;

  /// Where this layer's `ui.*` and `game.*` actions go instead of the
  /// game's host — an editor previewing a screen, which must not pause a
  /// game it is not running.
  final UiActionHost? actionHost;

  /// How a `@key` becomes words.
  final String Function(String key)? localize;

  /// A theme for every canvas, whatever they name — what the editor uses to
  /// preview one.
  final UiTheme? themeOverride;

  final void Function(String path)? onSound;

  /// Filled in as the tree is built, so an editor can find where each
  /// entity's node landed on screen.
  ///
  /// Only the editor passes this: a game has no use for it, and the marks
  /// cost a widget each.
  final UiNodeBoxes? nodes;

  /// Whether the system's back — Android's back button and gesture, a
  /// browser's back — closes the screen on top while one is open, rather
  /// than leaving the app. The game's view of its screens says yes; an
  /// editor showing a screen leaves it alone.
  final bool handlesBack;

  @override
  State<UiLayer> createState() => UiLayerState();
}

/// The layer's state: one node per entity on screen, and [sync], which
/// brings the widgets in step with the world once a frame.
class UiLayerState extends State<UiLayer> {
  /// The shape of the tree as it was last built: which canvases there are,
  /// in what order, holding which entities. Only this rebuilds the layer;
  /// everything else rebuilds one node.
  int _lastStructure = -1;

  /// One per entity on screen, holding a number that changes whenever that
  /// entity would look different. A node listens to its own, so a coin
  /// counter ticking over redraws the counter and nothing else.
  final Map<int, ValueNotifier<int>> _nodes = {};

  /// Text a player is part-way through typing, kept between rebuilds.
  final Map<int, TextEditingController> _fields = {};

  /// What each text's `[link=…]` runs listen to taps with, made again
  /// whenever the text is built and let go of with it.
  final Map<int, List<TapGestureRecognizer>> _links = {};

  /// Which screens are open: the one it was given, or its own — made again
  /// when the layer is given another world or navigator.
  late UiNavigator navigator = widget.navigator ?? UiNavigator(widget.world);

  /// Flies a Hero between two screens. The app's own navigator hands its
  /// descendants none (`HeroControllerScope.none`), so without this one no
  /// `heroTag` ever flew.
  final HeroController _heroes = MaterialApp.createMaterialHeroController();

  /// Themes asked for and not yet read: each is read once, and the layer
  /// looks again when it arrives.
  final Set<String> _themesAsked = {};

  @override
  void initState() {
    super.initState();
    navigator.adopt();
    _syncedAt = _freshAfter = widget.world.updateCount;
  }

  /// Another world, or another navigator: everything built for the old one
  /// goes — its nodes, its fields' text, its links — and the layer reads
  /// the new one from scratch.
  @override
  void didUpdateWidget(UiLayer old) {
    super.didUpdateWidget(old);
    if (identical(old.world, widget.world) &&
        identical(old.navigator, widget.navigator)) {
      return;
    }
    navigator = widget.navigator ?? UiNavigator(widget.world);
    navigator.adopt();
    // Widgets of this frame still listen to the old ones: they go after it.
    final nodes = [..._nodes.values];
    final fields = [..._fields.values];
    final links = [for (final l in _links.values) ...l];
    _nodes.clear();
    _fields.clear();
    _links.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in nodes) {
        node.dispose();
      }
      for (final field in fields) {
        field.dispose();
      }
      for (final link in links) {
        link.dispose();
      }
    });
    _themesAsked.clear();
    _syncedAt = _freshAfter = widget.world.updateCount;
    markDirty();
  }

  /// Lets go of every node, field and link built so far.
  void _forgetNodes() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
    for (final recognizers in _links.values) {
      for (final recognizer in recognizers) {
        recognizer.dispose();
      }
    }
    _links.clear();
  }

  /// Where this layer's actions go. The global host is never touched: a
  /// layer used to swap it for its own while mounted and put it back after,
  /// so a second layer (an editor's preview) quietly took over the game's
  /// `ui.push` — and closing it could overwrite a host set in between.
  UiActionHost? get _host {
    if (widget.actionHost case final host?) {
      return widget.navigator == null ? navigator.fillingIn(host) : host;
    }
    // Its own navigator: its buttons open its own screens, and everything
    // else goes where the game's would.
    return widget.navigator == null
        ? navigator.fillingIn(UiActions.of(widget.world.context).host)
        : null;
  }

  /// Whether a [UiTextSystem] ticks this layer's world, resolving every
  /// text each frame — so a sync need not resolve them again.
  bool _textTicked = false;

  /// The world's update ([World.updateCount]) at the last sync, and at the
  /// one before it. A text the [UiTextSystem] resolved after the one before
  /// — in the update the game loop ran just before this sync — is reused;
  /// any other is resolved again here, so a binding that reads something
  /// new shows at the next sync whether or not the world ticked between
  /// (an editor's preview, a paused game, a test).
  late int _syncedAt, _freshAfter;

  /// What this layer's world reads bindings from: its engine's.
  UiBindings get _bindings => UiBindings.of(widget.world.context);

  /// What `[icon=…]` draws here: its engine's icons.
  UiIcons get _icons => UiIcons.of(widget.world.context);

  UiActionContext _context(Entity entity, {Object? value}) => UiActionContext(
    world: widget.world,
    entity: entity,
    value: value,
    gameWorld: widget.gameWorld,
    host: _host,
  );

  /// Rebuild the whole layer, and walk the tree again, on the next [sync].
  ///
  /// For changes nothing here can see: a `ChildrenComponent`'s list
  /// reordered in place by code that does not tell the world
  /// ([World.markStructureChanged]).
  void markDirty() {
    _lastStructure = -1;
    _walkedStructure = -1;
  }

  /// Brings the widgets back in step with the world. Called each frame by
  /// whoever owns the game loop, after it updated the world; a frame that
  /// changes nothing costs one look at each UI entity's fields and no
  /// rebuild at all, and walks the tree again only when the world's shape
  /// changed ([World.structureVersion]) or a canvas was shown, hidden or
  /// reordered.
  void sync() {
    if (!mounted) return;
    final world = widget.world;
    _textTicked = world.getSystem<UiTextSystem>() != null;
    _freshAfter = _syncedAt;
    _syncedAt = world.updateCount;
    // A screen may have been opened or closed by something other than an
    // action — the editor, a system, a scene that loaded with it open.
    navigator.adopt();
    if (!_walkHolds) _walk(_canvases);
    final structure = _structure();
    if (structure != _lastStructure) {
      _lastStructure = structure;
      _prune();
      setState(() {});
    }
    for (final parts in _walked) {
      _refreshParts(parts);
    }
  }

  /// Every canvas drawn and everything under each, in order, with what the
  /// layer reads of each: the tree, walked when it may have changed and
  /// read from there.
  final List<_UiParts> _walked = [];

  /// [_walked] by entity id.
  final Map<int, _UiParts> _walkedById = {};

  /// What [_walked] was walked from: the world's structure version, and
  /// [_canvasesKey]. While both hold, the same entities hang in the same
  /// places, and the walk would find the same tree.
  int _walkedStructure = -1;
  int _walkedCanvases = 0;

  /// How many times the tree has been walked, for tests.
  @visibleForTesting
  int get walks => _walks;
  int _walks = 0;

  void _walk(List<Entity> canvases) {
    _walks++;
    _walked.clear();
    _walkedById.clear();
    for (final canvas in canvases) {
      _walkBelow(_walkTo(canvas), 0);
    }
    _walkedStructure = widget.world.structureVersion;
    _walkedCanvases = _canvasesKey();
  }

  _UiParts _walkTo(Entity entity) {
    final parts = _UiParts(entity, widget.world);
    _walked.add(parts);
    _walkedById[entity.id] = parts;
    return parts;
  }

  /// What the layer reads of [entity]: as walked, while the world's
  /// structure holds; looked up afresh otherwise.
  _UiParts _partsOf(Entity entity) {
    final walked = _walkedById[entity.id];
    if (walked != null &&
        identical(walked.entity, entity) &&
        _walkedStructure == widget.world.structureVersion) {
      return walked;
    }
    return _UiParts(entity, widget.world);
  }

  /// Whether [_walked] is still the tree: the world's shape, and its
  /// canvases' visibility and order, are as they were when it was walked.
  bool get _walkHolds =>
      widget.world.structureVersion == _walkedStructure &&
      _canvasesKey() == _walkedCanvases;

  /// What of the world's canvases decides which are drawn, and in what
  /// order, that its structure version does not tell: whether each is
  /// visible, and its sort order.
  int _canvasesKey() {
    final parts = _canvasesHash..reset();
    for (final entity in widget.world.query(const [UiCanvasComponent])) {
      final canvas = entity.getComponent<UiCanvasComponent>()!;
      parts
        ..add(entity.id)
        ..add(canvas.visible)
        ..add(canvas.sortOrder);
    }
    return parts.value;
  }

  void _walkBelow(_UiParts parts, int depth) {
    // A UI tree deeper than this is a mistake (or a loop), not a use case.
    if (depth > 64) return;
    for (final child in parts.children) {
      _walkBelow(_walkTo(child), depth + 1);
    }
  }

  /// A number that changes when the tree's *shape* does — read from what
  /// [_walk] found.
  int _structure() {
    final parts = _structureHash..reset();
    for (final screen in navigator.stack) {
      parts.add(screen.id);
    }
    for (final walked in _walked) {
      final canvas = walked.canvas;
      if (canvas == null) {
        parts
          ..add(walked.entity.id)
          // Whether it is there at all is decided by its parent's layout,
          // not by its own node — so a shown or hidden child reshapes.
          ..add(walked.slot?.visible);
        continue;
      }
      parts
        ..add(walked.entity.id)
        ..add(canvas.revision)
        ..add(canvas.sortOrder)
        ..add(canvas.designSize)
        ..add(canvas.scaleMode)
        ..add(canvas.safeArea)
        ..add(canvas.theme)
        // A route is made once, from these: changing one makes a new one.
        ..add(canvas.isScreen)
        ..add(canvas.modal)
        ..add(canvas.transition);
    }
    return parts.value;
  }

  /// What [_structure] and [_revisionOf] fold their parts into: one each,
  /// kept, so a frame's walk makes no list per entity.
  final _UiHash _structureHash = _UiHash();
  final _UiHash _revisionHash = _UiHash();
  final _UiHash _canvasesHash = _UiHash();

  /// Wakes [entity]'s node if it now looks different. A node nothing has
  /// built yet has nothing to wake — it will read the world when it is
  /// built.
  void _refresh(Entity entity) {
    if (_nodes.containsKey(entity.id)) _refreshParts(_partsOf(entity));
  }

  void _refreshParts(_UiParts parts) {
    final node = _nodes[parts.entity.id];
    if (node == null) return;
    final now = _revisionOf(parts);
    if (node.value != now) node.value = now;
  }

  /// Forgets the nodes of entities that have gone.
  void _prune() {
    final live = <int>{for (final parts in _walked) parts.entity.id};
    _nodes.removeWhere((id, node) {
      if (live.contains(id)) return false;
      node.dispose();
      return true;
    });
    _fields.removeWhere((id, controller) {
      if (live.contains(id)) return false;
      controller.dispose();
      return true;
    });
    _links.removeWhere((id, recognizers) {
      if (live.contains(id)) return false;
      for (final recognizer in recognizers) {
        recognizer.dispose();
      }
      return true;
    });
  }

  ValueNotifier<int> _notifierFor(Entity entity) => _nodes.putIfAbsent(
    entity.id,
    () => ValueNotifier<int>(_revisionOf(_partsOf(entity))),
  );

  /// Everything about an entity that changes how it is drawn without
  /// changing the shape of the tree.
  ///
  /// Written out rather than guessed at: a field missing from here is a
  /// field the screen does not notice, so anything added to a UI component
  /// belongs in this list. An editor that changes something stranger calls
  /// [markDirty].
  int _revisionOf(_UiParts of) {
    final entity = of.entity;
    final parts = _revisionHash
      ..reset()
      ..add(entity.isActive);

    if (of.text case final text?) {
      parts
        ..add(text.revision)
        // The resolved string, so a binding reading a new number shows.
        ..add(
          // What the world's text system resolved since the last sync, when
          // one ticks the world; read here when nothing has, so a binding
          // that changed with no update between still shows.
          (_textTicked && text.resolvedIn > _freshAfter ? text.resolved : null)
                  ?.plain ??
              text
                  .resolve(_bindings, self: entity, localize: widget.localize)
                  .plain,
        )
        ..add(text.revealSpeed > 0 ? text.revealed.floor() : 0)
        ..add(text.align)
        ..add(text.overflow)
        ..add(text.styleRole)
        ..add(text.minFontSize)
        ..add(text.maxLines);
    }
    if (of.slot case final slot?) {
      parts
        ..add(slot.visible)
        ..add(slot.opacity)
        ..add(slot.mode)
        ..add(slot.anchor)
        ..add(slot.offset)
        ..add(slot.size)
        ..add(slot.margin)
        ..add(slot.flex)
        ..add(slot.alignSelf)
        ..add(slot.ignorePointer)
        ..add(slot.heroTag);
    }
    if (of.layout case final layout?) {
      parts
        ..add(layout.kind)
        ..add(layout.mainAxis)
        ..add(layout.crossAxis)
        ..add(layout.spacing)
        ..add(layout.padding)
        ..add(layout.columns)
        ..add(layout.tight);
    }
    if (of.panel case final panel?) {
      parts
        ..add(panel.colorRole)
        ..add(panel.color)
        ..add(panel.borderColor)
        ..add(panel.borderWidth)
        ..add(panel.radius)
        ..add(panel.shadowBlur)
        ..add(panel.blur)
        ..add(panel.image)
        ..add(panel.nineSlice)
        ..add(panel.gradient == null ? null : Object.hashAll(panel.gradient!));
    }
    if (of.button case final button?) {
      parts
        // As read: a label that reads the game shows the new number.
        ..add(_words(button.label, entity))
        ..add(button.labelStyle)
        ..add(button.styleRole)
        ..add(button.state)
        ..add(button.colorRole)
        ..add(button.color)
        ..add(button.enabled);
    }
    if (of.image case final image?) {
      parts
        ..add(image.path)
        ..add(image.atlasRegion)
        ..add(image.fit)
        ..add(image.tint)
        ..add(image.opacity);
    }
    if (of.progress case final bar?) {
      parts
        ..add(_progressValue(_bindings, entity, bar))
        ..add(bar.colorRole)
        ..add(bar.color)
        ..add(bar.radial)
        ..add(bar.thickness);
    }
    if (of.toggle case final toggle?) {
      parts
        ..add(toggle.value)
        ..add(_words(toggle.label, entity));
      if (toggle.binding.isNotEmpty) {
        parts.add(_bindings.readNumber(toggle.binding, self: entity));
      }
    }
    if (of.slider case final slider?) {
      parts
        ..add(slider.value)
        ..add(slider.min)
        ..add(slider.max)
        ..add(slider.steps)
        ..add(_words(slider.label, entity));
      if (slider.binding.isNotEmpty) {
        parts.add(_bindings.readNumber(slider.binding, self: entity));
      }
    }
    if (of.field case final field?) {
      parts
        ..add(field.value)
        ..add(_words(field.hint, entity))
        ..add(field.obscure)
        ..add(field.maxLength);
    }
    if (of.dropdown case final dropdown?) {
      parts
        ..add(dropdown.value)
        ..add(_words(dropdown.label, entity))
        ..addEach(dropdown.options);
    }
    if (of.custom case final custom?) {
      parts.add(custom.widgetId);
      for (final entry in custom.props.entries) {
        parts
          ..add(entry.key)
          // As a widget reads it (`context.text`), bindings filled in.
          ..add(_bindings.interpolate(entry.value, self: entity));
      }
    }
    if (of.spacer case final spacer?) {
      parts
        ..add(spacer.size)
        ..add(spacer.expand);
    }
    // Where its children sit: a parent builds that (a `Positioned`, a
    // flex), so a child moved or resized on its own — by a timeline, by
    // code — rebuilds the parent, or it would be drawn where it was.
    for (final slot in of.childSlots) {
      parts.add(_placementOf(slot));
    }
    return parts.value;
  }

  /// What of a child's [slot] its parent places it by.
  static Object? _placementOf(UiSlotComponent? slot) {
    if (slot == null) return null;
    return Object.hash(
      slot.visible,
      slot.mode,
      slot.anchor,
      slot.pivot,
      slot.offset,
      slot.size,
      slot.margin,
      slot.flex,
      slot.alignSelf,
    );
  }

  /// [source] as a player reads it: a `@key` in this game's language, with
  /// its bindings filled in.
  String _words(String source, Entity entity) =>
      _bindings.resolveText(source, self: entity, localize: widget.localize);

  @override
  void dispose() {
    _forgetNodes();
    _heroes.dispose();
    super.dispose();
  }

  /// The canvases to draw, lowest first.
  List<Entity> get _canvases {
    final found =
        [
          for (final e in widget.world.query([UiCanvasComponent]))
            if (e.isActive && e.getComponent<UiCanvasComponent>()!.visible) e,
        ]..sort(
          (a, b) => a.getComponent<UiCanvasComponent>()!.sortOrder.compareTo(
            b.getComponent<UiCanvasComponent>()!.sortOrder,
          ),
        );
    return found;
  }

  /// The entities directly under [entity], in the order the scene holds
  /// them — which is the order they were authored in.
  List<Entity> _childrenOf(Entity entity) {
    final children = entity.getComponent<ChildrenComponent>();
    if (children == null) return const [];
    return [
      for (final id in children.childIds)
        if (widget.world.getEntity(id) case final child?)
          if (child.isActive) child,
    ];
  }

  UiTheme _themeOf(UiCanvasComponent canvas) {
    if (widget.themeOverride case final theme?) return theme;
    final path = canvas.theme;
    final themes = UiThemes.of(widget.world.context);
    if (path.isEmpty) return themes.fallback;
    final cached = themes.cached(path);
    if (cached != null) return cached;
    // Not read yet — a canvas pointed at another theme, a scene opened in
    // the editor. Drawn with the fallback until it lands, then again.
    if (_themesAsked.add(path)) {
      themes.load(path).then((_) {
        _themesAsked.remove(path);
        // One that would not load is the fallback until it is evicted,
        // which is what is drawn already: nothing to rebuild.
        if (!mounted || themes.failed(path)) return;
        markDirty();
        setState(() {});
      });
    }
    return themes.fallback;
  }

  @override
  Widget build(BuildContext context) {
    // What is about to be on screen, so the first sync after it has
    // nothing to do — walked again unless a sync just did.
    final canvases = _canvases;
    if (!_walkHolds) _walk(canvases);
    _lastStructure = _structure();

    final open = navigator.stack;
    final layers = [
      for (final entity in canvases)
        if (!entity.getComponent<UiCanvasComponent>()!.isScreen) entity,
    ];
    final hasScreens = widget.world
        .query([UiCanvasComponent])
        .any((e) => e.getComponent<UiCanvasComponent>()!.isScreen);
    if (layers.isEmpty && !hasScreens) return const SizedBox.shrink();

    return Stack(
      children: [
        for (final entity in layers) _canvas(entity),
        // Screens live in a real Navigator: pushing one is a route, so the
        // transitions are Flutter's and a Hero flies between them.
        if (hasScreens) Positioned.fill(child: _screens(open)),
      ],
    );
  }

  /// The open screens, as pages of a nested navigator.
  ///
  /// There is always a page underneath them that draws nothing, so the
  /// last screen closing animates out rather than blinking away.
  Widget _screens(List<Entity> open) {
    Widget screens = HeroControllerScope(
      controller: _heroes,
      child: _screenNavigator(open),
    );
    if (widget.handlesBack) {
      // A nested navigator never hears the system's back by itself: without
      // this, Android's back with the pause menu open left the game.
      // Taken while a screen is open even when it does not close on Back:
      // Back on a level-complete banner must not leave the game either.
      screens = NavigatorPopHandler<Object?>(
        enabled: open.isNotEmpty,
        onPopWithResult: (_) {
          if (navigator.handleBack()) markDirty();
        },
        child: screens,
      );
    }
    return screens;
  }

  Widget _screenNavigator(List<Entity> open) {
    return Navigator(
      pages: [
        const _UiRootPage(),
        for (final entity in open)
          _UiScreenPage(
            entity: entity,
            canvas: entity.getComponent<UiCanvasComponent>()!,
            builder: (context) => _canvasContent(entity),
          ),
      ],
      onDidRemovePage: (page) {
        // Popped from inside — a `Navigator.pop` in a game's own widget,
        // the system's back through [UiLayer.handlesBack]. Keep the scene
        // in step.
        if (page is _UiScreenPage) {
          navigator.show(page.entity.name ?? '', false);
          markDirty();
        }
      },
    );
  }

  /// One canvas as a layer under the screens.
  Widget _canvas(Entity entity) =>
      Positioned.fill(child: _canvasContent(entity));

  /// One canvas: scaled to the screen, kept clear of notches, themed, and
  /// walkable with the keyboard.
  Widget _canvasContent(Entity entity) {
    // Gone: the screens were reset (a restart) or reloaded while this one
    // was still on its way out, and its route builds it once more.
    final canvas = entity.getComponent<UiCanvasComponent>();
    if (canvas == null) return const SizedBox.shrink();
    final theme = _themeOf(canvas);
    return Theme(
      data: theme.toThemeData(),
      // The interface is not inside the app's Scaffold — it is over the
      // game — so it brings the sheet the material widgets are printed
      // on. Transparent: the game shows through everything not drawn.
      child: Material(
        type: MaterialType.transparency,
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Shortcuts(
            // A menu must be usable without a pointer: the arrows walk it,
            // Enter or Space presses, Escape goes back (on a screen that
            // closes on Back). A gamepad's d-pad reaches this through the
            // host's key mapping.
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowUp):
                  DirectionalFocusIntent(TraversalDirection.up),
              SingleActivator(LogicalKeyboardKey.arrowDown):
                  DirectionalFocusIntent(TraversalDirection.down),
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  DirectionalFocusIntent(TraversalDirection.left),
              SingleActivator(LogicalKeyboardKey.arrowRight):
                  DirectionalFocusIntent(TraversalDirection.right),
              SingleActivator(LogicalKeyboardKey.escape): _UiBackIntent(),
            },
            child: Actions(
              actions: {_UiBackIntent: _UiBackAction(this)},
              // Nearer the focus than the arrows above: in a text field the
              // arrows move the caret, as they do everywhere else.
              child: DefaultTextEditingShortcuts(
                // Inside the safe area when the canvas keeps to it, so the
                // scale comes from the room there really is. Measured on the
                // whole screen and then squeezed in, a canvas was scaled
                // more one way than the other: squashed on any phone with a
                // notch.
                child: _inSafeArea(
                  canvas.safeArea,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screen = constraints.biggest;
                      // No room — a window minimised, a view folded away —
                      // or no limit: nothing to scale to.
                      if (!screen.isFinite || screen.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final scale = canvas.scaleMode.scaleFor(
                        canvas.designSize,
                        screen,
                      );
                      if (!scale.isFinite || scale <= 0) {
                        return const SizedBox.shrink();
                      }
                      // Everything under a canvas is laid out in design pixels
                      // and then scaled, so a HUD looks the same everywhere.
                      final design = scale == 1
                          ? screen
                          : Size(screen.width / scale, screen.height / scale);
                      Widget child = SizedBox(
                        width: design.width,
                        height: design.height,
                        // The canvas's own node: a child placed on it that
                        // moves on its own rebuilds where it is placed.
                        child: ValueListenableBuilder<int>(
                          valueListenable: _notifierFor(entity),
                          builder: (context, _, _) =>
                              _children(entity, theme, design),
                        ),
                      );
                      // So an editor can find the canvas itself — its edges
                      // and centre are what a top-level element snaps to.
                      if (widget.nodes case final nodes?) {
                        child = _UiNodeMark(
                          id: entity.id,
                          nodes: nodes,
                          child: child,
                        );
                      }
                      if (scale != 1) {
                        // `FittedBox` rather than `Transform.scale`: a
                        // transform leaves the *layout* box at the design
                        // size, so a 1920-wide HUD on a 400-wide screen drew
                        // in the right place but could not be clicked —
                        // everything above it hit-tested against a box the
                        // size of the design. This one is the size of the
                        // screen, and since the design is the screen divided
                        // by the scale, filling it is the same uniform scale
                        // it always was.
                        child = FittedBox(
                          fit: BoxFit.fill,
                          alignment: Alignment.topLeft,
                          child: child,
                        );
                      }
                      return child;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _inSafeArea(bool on, Widget child) =>
      on ? SafeArea(child: child) : child;

  /// A canvas's children: anchored ones in a stack, the rest in the flow.
  Widget _children(Entity entity, UiTheme theme, Size size) {
    final children = _childrenOf(entity);
    if (children.isEmpty) return const SizedBox.expand();
    return Stack(
      children: [for (final child in children) _placed(child, theme, size)],
    );
  }

  /// A child inside a stack: where its slot says, or filling it.
  ///
  /// A hidden one takes no room at all — sized to its slot, it could still
  /// be clicked, and picked in an editor, where nothing is drawn.
  Widget _placed(Entity entity, UiTheme theme, Size parent) {
    final slot = entity.getComponent<UiSlotComponent>();
    if (slot != null && !slot.visible) return _nowhere;
    final built = buildEntity(entity, theme);
    if (slot == null) return Positioned.fill(child: built);
    final rect = slot.rectIn(parent);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: built,
    );
  }

  /// What one entity becomes, children and all.
  ///
  /// Each is wrapped in a listener on its own number, so a frame that
  /// changes one text rebuilds that text and leaves its neighbours — and
  /// the rest of the screen — alone.
  Widget buildEntity(Entity entity, UiTheme theme) {
    final built = ValueListenableBuilder<int>(
      valueListenable: _notifierFor(entity),
      builder: (context, _, _) => _buildEntity(entity, theme),
    );
    final nodes = widget.nodes;
    if (nodes == null) return built;
    return _UiNodeMark(id: entity.id, nodes: nodes, child: built);
  }

  Widget _buildEntity(Entity entity, UiTheme theme) {
    final slot = entity.getComponent<UiSlotComponent>();
    if (slot != null && !slot.visible) return const SizedBox.shrink();

    var child = _content(entity, theme);

    final panel = entity.getComponent<UiPanelComponent>();
    if (panel != null) child = _panel(panel, theme, child);

    if (slot != null) {
      if (slot.opacity < 1) {
        child = Opacity(opacity: slot.opacity.clamp(0.0, 1.0), child: child);
      }
      if (slot.ignorePointer) child = IgnorePointer(child: child);
      if (slot.heroTag.isNotEmpty) {
        child = Hero(tag: slot.heroTag, child: child);
      }
      if (slot.margin != EdgeInsets.zero && slot.mode == UiSlotMode.flow) {
        child = Padding(padding: slot.margin, child: child);
      }
    }
    return child;
  }

  static const Widget _nowhere = Positioned(
    left: 0,
    top: 0,
    width: 0,
    height: 0,
    child: SizedBox.shrink(),
  );

  /// How full a bar is: what the scene set, or what the game says.
  static double _progressValue(
    UiBindings bindings,
    Entity entity,
    UiProgressComponent bar,
  ) {
    if (bar.binding.isEmpty) return bar.value.clamp(0.0, 1.0);
    if (bar.maxBinding.isEmpty) {
      return (bindings.readNumber(bar.binding, self: entity) ?? 0).clamp(
        0.0,
        1.0,
      );
    }
    return bindings.fraction(bar.binding, bar.maxBinding, self: entity);
  }
}

/// What the layer reads of one entity, looked up once when the tree is
/// walked rather than every frame: its UI components, and its children that
/// are switched on, with their slots. Good while the world's structure
/// version holds — a component added, removed or replaced, or a child
/// made, destroyed, moved or switched on or off, moves it on.
class _UiParts {
  _UiParts(this.entity, World world)
    : canvas = entity.getComponent<UiCanvasComponent>(),
      text = entity.getComponent<UiTextComponent>(),
      slot = entity.getComponent<UiSlotComponent>(),
      layout = entity.getComponent<UiLayoutComponent>(),
      panel = entity.getComponent<UiPanelComponent>(),
      button = entity.getComponent<UiButtonComponent>(),
      image = entity.getComponent<UiImageComponent>(),
      progress = entity.getComponent<UiProgressComponent>(),
      toggle = entity.getComponent<UiToggleComponent>(),
      slider = entity.getComponent<UiSliderComponent>(),
      field = entity.getComponent<UiTextFieldComponent>(),
      dropdown = entity.getComponent<UiDropdownComponent>(),
      custom = entity.getComponent<UiCustomComponent>(),
      spacer = entity.getComponent<UiSpacerComponent>() {
    for (final id
        in entity.getComponent<ChildrenComponent>()?.childIds ??
            const <EntityId>[]) {
      final child = world.getEntity(id);
      if (child == null || !child.isActive) continue;
      children.add(child);
      childSlots.add(child.getComponent<UiSlotComponent>());
    }
  }

  final Entity entity;
  final UiCanvasComponent? canvas;
  final UiTextComponent? text;
  final UiSlotComponent? slot;
  final UiLayoutComponent? layout;
  final UiPanelComponent? panel;
  final UiButtonComponent? button;
  final UiImageComponent? image;
  final UiProgressComponent? progress;
  final UiToggleComponent? toggle;
  final UiSliderComponent? slider;
  final UiTextFieldComponent? field;
  final UiDropdownComponent? dropdown;
  final UiCustomComponent? custom;
  final UiSpacerComponent? spacer;

  /// Its children that are switched on, in the order the scene holds them,
  /// and each one's slot.
  final List<Entity> children = [];
  final List<UiSlotComponent?> childSlots = [];
}

/// Folds values into one hash, as `Object.hashAll` does, without a list.
class _UiHash {
  int value = 0;

  void reset() => value = 0;

  void add(Object? part) => value = Object.hash(value, part);

  void addEach(Iterable<Object?> parts) {
    for (final part in parts) {
      add(part);
    }
  }
}
