/// The scene's UI, as real Flutter widgets.
///
/// Every screen-space canvas in the world is built here: the entity tree
/// becomes a widget tree, so a text field is a real `TextField` with an
/// IME behind it, a list scrolls with the platform's physics, and a game's
/// own widgets sit beside the built-in ones.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:just_game_engine/just_game_engine.dart';
import '../logic/ui_actions.dart';
import '../logic/ui_bindings.dart';
import 'ui_navigator.dart';
import '../text/ui_rich_text.dart';
import '../text/ui_text_style.dart';
import '../theme/ui_theme.dart';
import 'ui_widgets.dart';
import '../components/button_component.dart';
import '../components/screen/ui_canvas_component.dart';
import '../components/screen/ui_elements.dart';
import '../components/screen/ui_slot_component.dart';
import '../components/text_component.dart';

/// Draws every screen-space canvas in [world], over the game.
class UiLayer extends StatefulWidget {
  const UiLayer({
    super.key,
    required this.world,
    this.localise,
    this.themeOverride,
    this.onSound,
    this.nodes,
    this.navigator,
    this.gameWorld,
    this.actionHost,
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
  final String Function(String key)? localise;

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

  @override
  State<UiLayer> createState() => UiLayerState();
}

/// Where each entity's node is on screen, as a [UiLayer] built it.
///
/// Not a `GlobalKey` per entity: a key can be in one place at a time, and
/// one entity can be built in two — a screen opened again while it is
/// still closing has a leaving route and an arriving one. The arriving one
/// tore the canvas out of the leaving one in mid-layout, and Flutter
/// reported a duplicate key, a mutated render box and a broken semantics
/// tree. Here both are kept, and the newer one is the answer.
class UiNodeBoxes {
  final Map<int, List<BuildContext>> _built = {};

  /// Where [id]'s node is laid out, or null when it is not on screen.
  RenderBox? operator [](int id) {
    final built = _built[id];
    if (built == null) return null;
    for (final context in built.reversed) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) return box;
    }
    return null;
  }

  void _add(int id, BuildContext context) =>
      (_built[id] ??= <BuildContext>[]).add(context);

  void _remove(int id, BuildContext context) {
    final built = _built[id];
    if (built == null) return;
    built.remove(context);
    if (built.isEmpty) _built.remove(id);
  }
}

/// Puts [child] in [nodes] under [id] for as long as it is in the tree.
///
/// Only while it is active: an element taken out of the tree in this frame
/// has no render object to ask about.
class _UiNodeMark extends StatefulWidget {
  const _UiNodeMark({
    required this.id,
    required this.nodes,
    required this.child,
  });

  final int id;
  final UiNodeBoxes nodes;
  final Widget child;

  @override
  State<_UiNodeMark> createState() => _UiNodeMarkState();
}

class _UiNodeMarkState extends State<_UiNodeMark> {
  @override
  void initState() {
    super.initState();
    widget.nodes._add(widget.id, context);
  }

  @override
  void didUpdateWidget(_UiNodeMark old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id && identical(old.nodes, widget.nodes)) return;
    old.nodes._remove(old.id, context);
    widget.nodes._add(widget.id, context);
  }

  @override
  void deactivate() {
    widget.nodes._remove(widget.id, context);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.nodes._add(widget.id, context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

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

  /// Which screens are open: the one it was given, or its own.
  late final UiNavigator navigator =
      widget.navigator ?? UiNavigator(widget.world);

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
        ? navigator.fillingIn(UiActions.host)
        : null;
  }

  UiActionContext _context(Entity entity, {Object? value}) => UiActionContext(
    world: widget.world,
    entity: entity,
    value: value,
    gameWorld: widget.gameWorld,
    host: _host,
  );

  /// Rebuild the whole layer on the next [sync].
  ///
  /// For changes nothing here can see — the editor moving an entity from
  /// one parent to another, a system swapping components around.
  void markDirty() => _lastStructure = -1;

  /// Brings the widgets back in step with the world. Called each frame by
  /// whoever owns the game loop; a frame that changes nothing costs one
  /// walk of the UI entities and no rebuild at all.
  void sync() {
    if (!mounted) return;
    // A screen may have been opened or closed by something other than an
    // action — the editor, a system, a scene that loaded with it open.
    navigator.adopt();
    final structure = _structure();
    if (structure != _lastStructure) {
      _lastStructure = structure;
      _prune();
      setState(() {});
    }
    _refreshAll();
  }

  /// A number that changes when the tree's *shape* does.
  int _structure() {
    final parts = <Object?>[for (final screen in navigator.stack) screen.id];
    for (final entity in _canvases) {
      final canvas = entity.getComponent<UiCanvasComponent>()!;
      parts
        ..add(entity.id)
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
      for (final child in _descendants(entity)) {
        parts
          ..add(child.id)
          // Whether it is there at all is decided by its parent's layout,
          // not by its own node — so a shown or hidden child reshapes.
          ..add(child.getComponent<UiSlotComponent>()?.visible);
      }
    }
    return Object.hashAll(parts);
  }

  void _refreshAll() {
    for (final canvas in _canvases) {
      _refresh(canvas);
      for (final child in _descendants(canvas)) {
        _refresh(child);
      }
    }
  }

  /// Wakes [entity]'s node if it now looks different. A node nothing has
  /// built yet has nothing to wake — it will read the world when it is
  /// built.
  void _refresh(Entity entity) {
    final node = _nodes[entity.id];
    if (node == null) return;
    final now = _revisionOf(entity);
    if (node.value != now) node.value = now;
  }

  /// Forgets the nodes of entities that have gone.
  void _prune() {
    final live = <int>{
      for (final canvas in _canvases) ...[
        canvas.id,
        for (final child in _descendants(canvas)) child.id,
      ],
    };
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
  }

  ValueNotifier<int> _notifierFor(Entity entity) => _nodes.putIfAbsent(
    entity.id,
    () => ValueNotifier<int>(_revisionOf(entity)),
  );

  /// Everything about an entity that changes how it is drawn without
  /// changing the shape of the tree.
  ///
  /// Written out rather than guessed at: a field missing from here is a
  /// field the screen does not notice, so anything added to a UI component
  /// belongs in this list. An editor that changes something stranger calls
  /// [markDirty].
  int _revisionOf(Entity entity) {
    final parts = <Object?>[entity.isActive];

    if (entity.getComponent<TextComponent>() case final text?) {
      parts
        ..add(text.revision)
        // The resolved string, so a binding reading a new number shows.
        ..add(text.resolve(self: entity, localise: widget.localise).plain)
        ..add(text.revealSpeed > 0 ? text.revealed.floor() : 0)
        ..add(text.align)
        ..add(text.maxLines);
    }
    if (entity.getComponent<UiSlotComponent>() case final slot?) {
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
    if (entity.getComponent<UiLayoutComponent>() case final layout?) {
      parts
        ..add(layout.kind)
        ..add(layout.mainAxis)
        ..add(layout.crossAxis)
        ..add(layout.spacing)
        ..add(layout.padding)
        ..add(layout.columns)
        ..add(layout.tight);
    }
    if (entity.getComponent<UiPanelComponent>() case final panel?) {
      parts
        ..add(panel.colorRole)
        ..add(panel.color)
        ..add(panel.borderColor)
        ..add(panel.borderWidth)
        ..add(panel.radius)
        ..add(panel.shadowBlur)
        ..add(panel.blur)
        ..add(panel.image);
    }
    if (entity.getComponent<ButtonComponent>() case final button?) {
      parts
        ..add(button.label)
        ..add(button.state)
        ..add(button.colorRole)
        ..add(button.color)
        ..add(button.enabled);
    }
    if (entity.getComponent<UiImageComponent>() case final image?) {
      parts
        ..add(image.path)
        ..add(image.atlasRegion)
        ..add(image.fit)
        ..add(image.tint)
        ..add(image.opacity);
    }
    if (entity.getComponent<UiProgressComponent>() case final bar?) {
      parts
        ..add(_progressValue(entity, bar))
        ..add(bar.colorRole)
        ..add(bar.color)
        ..add(bar.radial)
        ..add(bar.thickness);
    }
    if (entity.getComponent<UiToggleComponent>() case final toggle?) {
      parts
        ..add(toggle.value)
        ..add(toggle.label);
    }
    if (entity.getComponent<UiSliderComponent>() case final slider?) {
      parts
        ..add(slider.value)
        ..add(slider.min)
        ..add(slider.max);
    }
    if (entity.getComponent<UiTextFieldComponent>() case final field?) {
      parts
        ..add(field.value)
        ..add(field.hint)
        ..add(field.obscure);
    }
    if (entity.getComponent<UiDropdownComponent>() case final dropdown?) {
      parts
        ..add(dropdown.value)
        ..addAll(dropdown.options);
    }
    if (entity.getComponent<UiCustomComponent>() case final custom?) {
      parts.add(custom.widgetId);
      for (final entry in custom.props.entries) {
        parts
          ..add(entry.key)
          ..add(entry.value);
      }
    }
    if (entity.getComponent<UiSpacerComponent>() case final spacer?) {
      parts
        ..add(spacer.size)
        ..add(spacer.expand);
    }
    return Object.hashAll(parts);
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();
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

  Iterable<Entity> _descendants(Entity entity) sync* {
    for (final child in _childrenOf(entity)) {
      yield child;
      yield* _descendants(child);
    }
  }

  UiTheme _themeOf(UiCanvasComponent canvas) {
    if (widget.themeOverride case final theme?) return theme;
    final path = canvas.theme;
    if (path.isEmpty) return UiThemes.fallback;
    final cached = UiThemes.cached(path);
    if (cached != null) return cached;
    // Not read yet — a canvas pointed at another theme, a scene opened in
    // the editor. Drawn with the fallback until it lands, then again.
    if (_themesAsked.add(path)) {
      UiThemes.load(path).then((_) {
        _themesAsked.remove(path);
        if (!mounted) return;
        markDirty();
        setState(() {});
      });
    }
    return UiThemes.fallback;
  }

  @override
  Widget build(BuildContext context) {
    // What is about to be on screen, so the first sync after it has
    // nothing to do.
    _lastStructure = _structure();

    final open = navigator.stack;
    final layers = [
      for (final entity in _canvases)
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
    return HeroControllerScope(
      controller: _heroes,
      child: _screenNavigator(open),
    );
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
        // The system popped it — Android's back gesture, a `Navigator.pop`
        // from inside a screen. Keep the scene in step.
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
    final canvas = entity.getComponent<UiCanvasComponent>()!;
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
            // Enter or Space presses, Escape goes back. A gamepad's d-pad
            // reaches this through the host's key mapping.
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
              actions: {
                _UiBackIntent: CallbackAction<_UiBackIntent>(
                  onInvoke: (_) {
                    navigator.back();
                    markDirty();
                    return null;
                  },
                ),
              },
              // Inside the safe area when the canvas keeps to it, so the scale
              // comes from the room there really is. Measured on the whole
              // screen and then squeezed in, a canvas was scaled more one way
              // than the other: squashed on any phone with a notch.
              child: _inSafeArea(
                canvas.safeArea,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final screen = constraints.biggest;
                    final scale = canvas.scaleMode.scaleFor(
                      canvas.designSize,
                      screen,
                    );
                    // Everything under a canvas is laid out in design pixels
                    // and then scaled, so a HUD looks the same everywhere.
                    final design = scale == 1
                        ? screen
                        : Size(screen.width / scale, screen.height / scale);
                    Widget child = SizedBox(
                      width: design.width,
                      height: design.height,
                      child: _children(entity, theme, design),
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

  /// The entity's own element, before its slot and its panel.
  Widget _content(Entity entity, UiTheme theme) {
    final children = _childrenOf(entity);
    final built = [for (final child in children) _flow(child, theme)];

    final custom = entity.getComponent<UiCustomComponent>();
    if (custom != null) {
      return UiWidgets.build(
            UiBuildContext(
              entity: entity,
              world: widget.world,
              theme: theme,
              children: built,
              localise: widget.localise,
              gameWorld: widget.gameWorld,
              host: _host,
            ),
          ) ??
          const SizedBox.shrink();
    }

    final layout = entity.getComponent<UiLayoutComponent>();
    if (layout != null) return _layout(layout, theme, built, entity);

    final text = entity.getComponent<TextComponent>();
    if (text != null) return _text(entity, text, theme);

    final button = entity.getComponent<ButtonComponent>();
    if (button != null) return _button(entity, button, theme, built);

    final image = entity.getComponent<UiImageComponent>();
    if (image != null) return _image(image);

    final progress = entity.getComponent<UiProgressComponent>();
    if (progress != null) return _progress(entity, progress, theme);

    final toggle = entity.getComponent<UiToggleComponent>();
    if (toggle != null) return _toggle(entity, toggle, theme);

    final slider = entity.getComponent<UiSliderComponent>();
    if (slider != null) return _slider(entity, slider, theme);

    final field = entity.getComponent<UiTextFieldComponent>();
    if (field != null) return _textField(entity, field, theme);

    final dropdown = entity.getComponent<UiDropdownComponent>();
    if (dropdown != null) return _dropdown(entity, dropdown, theme);

    final spacer = entity.getComponent<UiSpacerComponent>();
    if (spacer != null) {
      return spacer.expand
          ? const Spacer()
          : SizedBox(width: spacer.size, height: spacer.size);
    }

    // A bare entity with children is a plain box holding them.
    if (built.isEmpty) return const SizedBox.shrink();
    return built.length == 1 ? built.first : Stack(children: built);
  }

  /// A child inside a row, a column or another container — with its flex
  /// and alignment applied.
  Widget _flow(Entity entity, UiTheme theme) {
    final slot = entity.getComponent<UiSlotComponent>();
    final built = buildEntity(entity, theme);
    if (slot == null) return built;
    if (slot.mode == UiSlotMode.anchored) {
      // An anchored child of a flow container keeps the size its slot asks
      // for; the stack case is handled by the container itself.
      return SizedBox(
        width: slot.size.width,
        height: slot.size.height,
        child: built,
      );
    }
    if (slot.flex > 0) return Expanded(flex: slot.flex, child: built);
    // The size the slot says — which the inspector shows and the handles
    // drag — and not whatever the content happens to want. A parent that
    // stretches its children, or `alignSelf: stretch`, still wins across.
    return SizedBox(
      width: slot.size.width,
      height: slot.size.height,
      child: built,
    );
  }

  Widget _layout(
    UiLayoutComponent layout,
    UiTheme theme,
    List<Widget> children,
    Entity entity,
  ) {
    if (layout.kind == UiLayoutKind.row || layout.kind == UiLayoutKind.column) {
      children = _alignedSelf(
        children,
        _childrenOf(entity),
        across: layout.kind == UiLayoutKind.row
            ? Axis.vertical
            : Axis.horizontal,
      );
    }
    final spaced = _spaced(children, layout);
    Widget result;
    switch (layout.kind) {
      case UiLayoutKind.row:
        result = Row(
          mainAxisAlignment: layout.mainAxis.main,
          crossAxisAlignment: layout.crossAxis.cross,
          mainAxisSize: layout.tight ? MainAxisSize.min : MainAxisSize.max,
          children: spaced,
        );
      case UiLayoutKind.column:
        result = Column(
          mainAxisAlignment: layout.mainAxis.main,
          crossAxisAlignment: layout.crossAxis.cross,
          mainAxisSize: layout.tight ? MainAxisSize.min : MainAxisSize.max,
          children: spaced,
        );
      case UiLayoutKind.stack:
        result = Stack(
          children: [
            for (final child in _childrenOf(entity)) _stacked(child, theme),
          ],
        );
      case UiLayoutKind.wrap:
        result = Wrap(
          spacing: layout.spacing,
          runSpacing: layout.spacing,
          children: children,
        );
      case UiLayoutKind.grid:
        result = GridView.count(
          crossAxisCount: layout.columns < 1 ? 1 : layout.columns,
          mainAxisSpacing: layout.spacing,
          crossAxisSpacing: layout.spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      case UiLayoutKind.scroll:
        result = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: layout.crossAxis.cross,
            mainAxisSize: MainAxisSize.min,
            children: spaced,
          ),
        );
      case UiLayoutKind.safeArea:
        result = SafeArea(
          child: children.isEmpty
              ? const SizedBox.shrink()
              : children.length == 1
              ? children.first
              : Column(mainAxisSize: MainAxisSize.min, children: spaced),
        );
    }
    if (layout.padding != EdgeInsets.zero) {
      result = Padding(padding: layout.padding, child: result);
    }
    return result;
  }

  /// A child of a stack container, placed by its anchors — by the same
  /// rule as a child of the canvas, pivot and all.
  ///
  /// It used to align on the anchor's corner and ignore the pivot, so the
  /// same slot put a button in two different places depending on whether
  /// it sat in the canvas or in a stack inside it.
  Widget _stacked(Entity entity, UiTheme theme) {
    final slot = entity.getComponent<UiSlotComponent>();
    if (slot != null && !slot.visible) return _nowhere;
    final built = buildEntity(entity, theme);
    if (slot == null || slot.mode != UiSlotMode.anchored) return built;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned.fromRect(rect: slot.rectIn(box.biggest), child: built),
          ],
        ),
      ),
    );
  }

  static const Widget _nowhere = Positioned(
    left: 0,
    top: 0,
    width: 0,
    height: 0,
    child: SizedBox.shrink(),
  );

  /// [built] with each child's own `alignSelf` applied across the parent's
  /// direction — the one place a child may sit differently from its
  /// siblings.
  List<Widget> _alignedSelf(
    List<Widget> built,
    List<Entity> entities, {
    required Axis across,
  }) {
    if (built.length != entities.length) return built;
    return [
      for (var i = 0; i < built.length; i++)
        switch (entities[i].getComponent<UiSlotComponent>()?.crossAlignment) {
          null || CrossAxisAlignment.baseline => built[i],
          CrossAxisAlignment.stretch =>
            across == Axis.horizontal
                ? SizedBox(width: double.infinity, child: built[i])
                : SizedBox(height: double.infinity, child: built[i]),
          final align => Align(
            alignment: _alignmentAcross(align, across),
            child: built[i],
          ),
        },
    ];
  }

  static Alignment _alignmentAcross(CrossAxisAlignment align, Axis across) {
    final t = switch (align) {
      CrossAxisAlignment.start => -1.0,
      CrossAxisAlignment.end => 1.0,
      _ => 0.0,
    };
    return across == Axis.horizontal ? Alignment(t, 0) : Alignment(0, t);
  }

  /// [children] with the container's gap between them.
  List<Widget> _spaced(List<Widget> children, UiLayoutComponent layout) {
    if (layout.spacing <= 0 || children.length < 2) return children;
    final gap = layout.kind == UiLayoutKind.row
        ? SizedBox(width: layout.spacing)
        : SizedBox(height: layout.spacing);
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) gap,
        children[i],
      ],
    ];
  }

  // ── Controls ────────────────────────────────────────────────────────────

  /// Runs what an element was told to do, with [value] as what changed.
  void _run(Entity entity, UiActionList actions, {Object? value}) {
    if (actions.isEmpty) return;
    actions.run(_context(entity, value: value));
    markDirty();
  }

  void _sound(String path) {
    if (path.isNotEmpty) widget.onSound?.call(path);
  }

  /// Whether [entity] is the one its screen wants focused when it opens.
  ///
  /// Walked up rather than handed down, because a node is built by its own
  /// listener long after its canvas was.
  bool _takesInitialFocus(Entity entity) {
    final name = entity.name;
    if (name == null || name.isEmpty) return false;
    var current = entity;
    // A UI tree deeper than this is a mistake, not a use case.
    for (var step = 0; step < 32; step++) {
      final parentId = current.getComponent<ParentComponent>()?.parentId;
      if (parentId == null) return false;
      final parent = widget.world.getEntity(parentId);
      if (parent == null) return false;
      final canvas = parent.getComponent<UiCanvasComponent>();
      if (canvas != null) return canvas.initialFocus == name;
      current = parent;
    }
    return false;
  }

  /// Plays the theme's hover sound as focus arrives, so walking a menu
  /// with the keyboard sounds like moving a pointer over it.
  Widget _focusHeard(UiTheme theme, Widget child) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (has) {
      if (has) _sound(theme.sounds.hover);
    },
    child: child,
  );

  Widget _toggle(Entity entity, UiToggleComponent toggle, UiTheme theme) {
    final value = toggle.binding.isEmpty
        ? toggle.value
        : (UiBindings.readNumber(toggle.binding, self: entity) ?? 0) != 0;
    final control = Switch(
      value: value,
      autofocus: _takesInitialFocus(entity),
      onChanged: (next) {
        toggle.value = next;
        _sound(theme.sounds.toggle);
        _run(entity, toggle.onChanged, value: next);
        _refresh(entity);
      },
    );
    if (toggle.label.isEmpty) return _focusHeard(theme, control);
    return _focusHeard(
      theme,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              UiBindings.interpolate(toggle.label, self: entity),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          control,
        ],
      ),
    );
  }

  Widget _slider(Entity entity, UiSliderComponent slider, UiTheme theme) {
    final value = slider.binding.isEmpty
        ? slider.value
        : (UiBindings.readNumber(slider.binding, self: entity) ?? slider.value);
    return _focusHeard(
      theme,
      Slider(
        value: value.clamp(slider.min, slider.max),
        min: slider.min,
        max: slider.max,
        divisions: slider.steps > 0 ? slider.steps : null,
        autofocus: _takesInitialFocus(entity),
        label: slider.label.isEmpty ? null : slider.label,
        onChanged: (next) {
          slider.value = next;
          _run(entity, slider.onChanged, value: next);
          _refresh(entity);
        },
      ),
    );
  }

  Widget _textField(Entity entity, UiTextFieldComponent field, UiTheme theme) {
    // The controller outlives the widget, so a rebuild half-way through a
    // word does not swallow what has been typed or move the caret.
    final controller = _fields.putIfAbsent(
      entity.id,
      () => TextEditingController(text: field.value),
    );
    if (controller.text != field.value) {
      controller.value = TextEditingValue(
        text: field.value,
        selection: TextSelection.collapsed(offset: field.value.length),
      );
    }
    return _focusHeard(
      theme,
      TextField(
        controller: controller,
        autofocus: _takesInitialFocus(entity),
        obscureText: field.obscure,
        maxLength: field.maxLength > 0 ? field.maxLength : null,
        decoration: InputDecoration(
          hintText: field.hint.isEmpty ? null : field.hint,
          counterText: '',
        ),
        onChanged: (next) {
          field.value = next;
          _run(entity, field.onChanged, value: next);
        },
        onSubmitted: (next) {
          field.value = next;
          _run(entity, field.onSubmitted, value: next);
        },
      ),
    );
  }

  Widget _dropdown(Entity entity, UiDropdownComponent dropdown, UiTheme theme) {
    final options = dropdown.options.isEmpty
        ? <String>[dropdown.value]
        : dropdown.options;
    final value = options.contains(dropdown.value)
        ? dropdown.value
        : options.first;
    return _focusHeard(
      theme,
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        autofocus: _takesInitialFocus(entity),
        hint: dropdown.label.isEmpty ? null : Text(dropdown.label),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (next) {
          if (next == null) return;
          dropdown.value = next;
          _sound(theme.sounds.press);
          _run(entity, dropdown.onChanged, value: next);
          _refresh(entity);
        },
      ),
    );
  }

  Widget _panel(UiPanelComponent panel, UiTheme theme, Widget child) {
    final color = panel.colorUnder(theme);
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: panel.gradient == null ? color : null,
        gradient: panel.gradient != null && panel.gradient!.length > 1
            ? LinearGradient(colors: panel.gradient!)
            : null,
        borderRadius: BorderRadius.circular(panel.radius),
        border: panel.borderWidth > 0
            ? Border.all(
                color: panel.borderColorUnder(theme),
                width: panel.borderWidth,
              )
            : null,
        boxShadow: panel.shadowBlur > 0
            ? [
                BoxShadow(
                  color: const Color(0x66000000),
                  blurRadius: panel.shadowBlur,
                  offset: Offset(0, panel.shadowBlur / 3),
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (panel.blur > 0) {
      result = ClipRRect(
        borderRadius: BorderRadius.circular(panel.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: panel.blur, sigmaY: panel.blur),
          child: result,
        ),
      );
    }
    return result;
  }

  Widget _text(Entity entity, TextComponent text, UiTheme theme) {
    final resolved = text.resolve(self: entity, localise: widget.localise);
    final shown = text.revealSpeed > 0
        ? resolved.take(text.revealed.floor())
        : resolved;
    final style = text.styleUnder(theme);
    return Align(
      alignment: switch (text.align) {
        UiTextAlign.left => Alignment.centerLeft,
        UiTextAlign.right => Alignment.centerRight,
        _ => Alignment.center,
      },
      child: Text.rich(
        shown.toTextSpan(style),
        textAlign: text.align.flutter,
        maxLines: text.maxLines,
        overflow: text.overflow.flutter,
      ),
    );
  }

  Widget _button(
    Entity entity,
    ButtonComponent button,
    UiTheme theme,
    List<Widget> children,
  ) {
    final label = UiRichText.parse(
      UiBindings.interpolate(button.label, self: entity),
    );
    return _focusHeard(
      theme,
      FilledButton(
        autofocus: _takesInitialFocus(entity),
        onPressed: button.isInteractive
            ? () {
                _sound(theme.sounds.press);
                button.press(_context(entity));
                markDirty();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              button.color ??
              theme.color(
                button.colorRole,
                fallbackColor: theme.palette.primary,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(button.borderRadius),
            side: button.borderColor == null
                ? BorderSide.none
                : BorderSide(color: button.borderColor!),
          ),
        ),
        child: children.isNotEmpty
            ? (children.length == 1 ? children.first : Row(children: children))
            : Text.rich(label.toTextSpan(button.labelStyleUnder(theme))),
      ),
    );
  }

  Widget _image(UiImageComponent image) {
    if (image.path.isEmpty) return const SizedBox.shrink();
    Widget result = Image.asset(
      image.path,
      fit: image.fit,
      color: image.tint,
      colorBlendMode: image.tint == null ? null : BlendMode.modulate,
      // A picture that is not there must not take the interface down.
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
    if (image.opacity < 1) {
      result = Opacity(opacity: image.opacity.clamp(0.0, 1.0), child: result);
    }
    return result;
  }

  /// How full a bar is: what the scene set, or what the game says.
  static double _progressValue(Entity entity, UiProgressComponent bar) {
    if (bar.binding.isEmpty) return bar.value.clamp(0.0, 1.0);
    if (bar.maxBinding.isEmpty) {
      return (UiBindings.readNumber(bar.binding, self: entity) ?? 0).clamp(
        0.0,
        1.0,
      );
    }
    return UiBindings.fraction(bar.binding, bar.maxBinding, self: entity);
  }

  Widget _progress(Entity entity, UiProgressComponent bar, UiTheme theme) {
    final value = _progressValue(entity, bar);
    final color = bar.colorUnder(theme);
    final track = bar.trackColorUnder(theme);
    if (bar.radial) {
      return CircularProgressIndicator(
        value: value.toDouble(),
        color: color,
        backgroundColor: track,
        strokeWidth: bar.thickness,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(bar.radius),
      child: LinearProgressIndicator(
        value: value.toDouble(),
        color: color,
        backgroundColor: track,
        minHeight: bar.thickness,
      ),
    );
  }
}

/// Asking to go back one screen — Escape, or a gamepad's cancel.
class _UiBackIntent extends Intent {
  const _UiBackIntent();
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
  }) : super(key: ValueKey('ui.screen.${entity.id}'));

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
