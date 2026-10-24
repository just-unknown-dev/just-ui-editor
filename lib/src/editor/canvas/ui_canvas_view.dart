/// The middle of the interface editor: the screen on a device, and
/// everything done to it with a pointer.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/screen/ui_slot_component.dart';
import '../../runtime/layer/ui_layer.dart';
import '../../runtime/logic/ui_actions.dart';
import '../../runtime/logic/ui_bindings.dart';
import '../../runtime/systems/ui_system.dart';
import '../create/ui_create.dart';
import '../document/ui_screen_document.dart';
import '../session/ui_edit_ops.dart';
import '../session/ui_editor_session.dart';
import '../session/ui_slot_edit.dart';
import 'ui_canvas_metrics.dart';
import 'ui_canvas_painter.dart';
import 'ui_geometry.dart';
import 'ui_rulers.dart';

/// What a palette drag carries: the kind to make.
class UiPaletteDrag {
  const UiPaletteDrag(this.kind);
  final String kind;
}

enum _DragKind { move, resize, marquee, pan, guide, reorder }

class _Drag {
  _Drag(this.kind, this.start);

  final _DragKind kind;

  /// Where it began, in view pixels.
  final Offset start;
  bool started = false;

  // move / resize / reorder
  List<Entity> entities = const [];
  Map<Entity, Rect> rects = const {};
  Map<Entity, UiSlotState> slots = const {};
  UiHandle handle = UiHandle.move;
  int insertAt = -1;

  /// What the step is called in the history: "Move Resume".
  String label = '';

  // marquee: whether the press was on the canvas itself, which a click —
  // a press that never became a marquee — selects.
  bool onCanvas = false;

  // pan
  Offset panAtStart = Offset.zero;

  // guide
  bool vertical = false;
  int guideIndex = -1;
  List<UiGuide> guides = const [];
}

/// The device frame, the screen in it, and the handles over it.
class UiCanvasView extends StatefulWidget {
  const UiCanvasView({super.key, required this.session});

  final UiEditorSession session;

  @override
  State<UiCanvasView> createState() => UiCanvasViewState();
}

class UiCanvasViewState extends State<UiCanvasView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Repaints the overlay and the rulers: when what they show has moved,
  /// not every frame.
  final _repaint = _Tick();

  /// What follows the pointer. Changing it repaints; it never rebuilds.
  final UiCanvasOverlay _overlay = UiCanvasOverlay();

  /// The pointer's shape over the canvas, the one thing a hover changes
  /// that a painter cannot draw.
  final ValueNotifier<MouseCursor> _cursor = ValueNotifier(
    SystemMouseCursors.basic,
  );

  final GlobalKey _viewKey = GlobalKey(debugLabel: 'uiCanvasView');

  /// A fresh key for every screen opened: a layer keeps the navigator of the
  /// world it was first built on, so a new world needs a new layer.
  GlobalKey<UiLayerState> _layerKey = GlobalKey<UiLayerState>();
  UiScreenDocument? _layerFor;

  /// The other screens drawn underneath, in a world of their own so their
  /// names and ids never mix with the one being edited — and a key of its
  /// own for each such world, for the reason above.
  World? _behind;
  List<String> _behindNames = const [];
  GlobalKey<UiLayerState> _behindKey = GlobalKey<UiLayerState>();

  /// What Preview shows: a copy of the open screen, built when Preview
  /// begins and thrown away when it ends. A player's toggles, sliders and
  /// typing change the copy's components, and a Back closes the copy's
  /// canvas; the document's — what Save writes — is never touched. Made
  /// again when the document is edited while Preview is on.
  World? _preview;
  UiScreenDocument? _previewFor;
  int _previewRevision = -1;
  GlobalKey<UiLayerState> _previewKey = GlobalKey<UiLayerState>();
  UiNodeBoxes _previewNodes = UiNodeBoxes();

  /// The copy's id for each of the document's entities.
  Map<EntityId, EntityId> _previewIds = const {};

  /// The device frame as last built, and what it was built from: reused
  /// while those stay the same, so a pan or a zoom moves it rather than
  /// building the whole screen again.
  Object? _frameKey;
  Widget? _frame;

  Duration? _lastTick;
  Duration _lastPainted = Duration.zero;

  /// The open screen's revision the layer was last built for.
  int? _shownRevision;
  int? _lastSignature;
  _Drag? _drag;
  bool _spaceHeld = false;

  UiEditorSession get session => widget.session;
  UiScreenDocument? get _doc => session.document.value;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _repaint.dispose();
    _overlay.dispose();
    _cursor.dispose();
    _behind?.dispose();
    _preview?.dispose();
    session
      ..metrics = null
      ..previewCanvas = null;
    super.dispose();
  }

  /// Lets [world] go once the frame that stopped showing it is done: the
  /// layer that drew it is taken down in that frame, after this.
  static void _disposeLater(World? world) {
    if (world == null) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => world.dispose())
      ..ensureVisualUpdate();
  }

  // Space held down turns a drag into a pan, as in any drawing program.
  bool _onKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !WorkspaceKeyScope.isTyping) {
      final held = event is! KeyUpEvent;
      if (held != _spaceHeld) {
        _spaceHeld = held;
        _updateCursor();
      }
    }
    return false;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = _lastTick == null
        ? 0.0
        : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final doc = _doc;
    final previewing = session.previewing;
    if (doc != null) {
      if (previewing) {
        // Edited while Preview is on: show the edit, from a fresh copy.
        if (!identical(_previewFor, doc) ||
            _previewRevision != doc.history.revision.value) {
          setState(() {});
        }
        _preview?.update(dt);
      }
      final shown = previewing ? _preview : doc.world;
      if (shown != null) _applyForcedState(shown, previewing: previewing);
      // An edit can move an element, which its parent places: the layer
      // sees a node change, not where its parent puts it, so it is told to
      // build the screen again — once per edit, not once per frame.
      final revision = doc.sceneState.revision.value;
      if (revision != _shownRevision) {
        _shownRevision = revision;
        _layerKey.currentState?.markDirty();
      }
      (previewing ? _previewKey : _layerKey).currentState?.sync();
    }
    _behindKey.currentState?.sync();
    final view = _viewKey.currentContext?.findRenderObject();
    session.metrics = doc != null && view is RenderBox && view.hasSize
        ? UiCanvasMetrics(
            view: view,
            document: doc,
            nodes: previewing ? _previewNodes : session.nodes,
            ids: previewing ? _previewIds : null,
          )
        : null;
    session.syncShownZoom();
    _repaintIfMoved(elapsed, doc);
  }

  /// Repaints the overlay and the rulers when anything they draw from has
  /// changed — and at least four times a second, for what changes nothing
  /// they can see (a theme or a font arriving reflows the screen); every
  /// frame in Preview, where the screen moves by itself.
  void _repaintIfMoved(Duration now, UiScreenDocument? doc) {
    final m = session.metrics;
    final state = doc?.sceneState;
    final signature = Object.hashAll([
      m?.canvasView,
      m?.view.size,
      state?.revision.value,
      doc?.history.revision.value,
      state?.selectedEntity.value?.id,
      Object.hashAll(state?.multiSelectedIds.value ?? const <EntityId>[]),
      doc?.editorData.value,
      session.snapGuides.value,
      session.grid.value,
      session.gridStep.value,
      session.showGuides.value,
      session.boxes.value,
      session.rulers.value,
    ]);
    final due = now - _lastPainted >= const Duration(milliseconds: 250);
    if (signature == _lastSignature && !session.previewing && !due) return;
    _lastSignature = signature;
    _lastPainted = now;
    _repaint.notify();
  }

  /// Buttons shown in the state the preview strip asks for — every button,
  /// or the selected ones when there are any — in [world], the one shown.
  void _applyForcedState(World world, {required bool previewing}) {
    final forced = session.forcedState.value;
    final selected = {
      for (final e in session.selection)
        ?(previewing ? _previewIds[e.id] : e.id),
    };
    for (final e in world.query([ButtonComponent])) {
      final button = e.getComponent<ButtonComponent>()!;
      final applies =
          forced != null && (selected.isEmpty || selected.contains(e.id));
      final want = applies ? forced : UiInteractionState.normal;
      if (!previewing || applies) {
        if (button.state != want) button.state = want;
      }
    }
  }

  // ── Building ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        session.document,
        session.device,
        session.landscape,
        session.zoom,
        session.pan,
        session.mode,
        session.rulers,
        session.textScale,
        session.behind,
      ],
      builder: (context, _) {
        final doc = _doc;
        _syncPreview(doc);
        if (doc == null) return const _NothingOpen();
        if (!identical(_layerFor, doc)) {
          _layerFor = doc;
          _layerKey = GlobalKey<UiLayerState>();
        }
        _syncBehind(doc);
        return LayoutBuilder(
          builder: (context, box) => _canvas(doc, box.biggest),
        );
      },
    );
  }

  void _syncBehind(UiScreenDocument doc) {
    final names = [
      for (final n in session.behind.value)
        if (n != doc.name) n,
    ];
    if (listEquals(names, _behindNames)) return;
    _behindNames = names;
    _disposeLater(_behind);
    _behind = null;
    // A new world needs a new layer: the old one's navigator would go on
    // reading the world it was first built on.
    _behindKey = GlobalKey<UiLayerState>();
    if (names.isEmpty) return;
    final world = World(context: doc.world.context)..initialize();
    for (final name in names) {
      final path = session.screensByName[name];
      if (path == null) continue;
      try {
        final canvas = session.project
            .readScreen(path)
            .instantiate(world, decode: doc.codec.decodeAll);
        canvas.getComponent<UiCanvasComponent>()?.visible = true;
      } on Object {
        continue;
      }
    }
    _behind = world;
  }

  /// Builds the copy Preview shows, or lets it go outside Preview.
  void _syncPreview(UiScreenDocument? doc) {
    if (doc == null || !session.previewing) {
      if (_preview == null) return;
      _disposeLater(_preview);
      _preview = null;
      _previewFor = null;
      _previewIds = const {};
      session.previewCanvas = null;
      return;
    }
    final revision = doc.history.revision.value;
    if (_preview != null &&
        identical(_previewFor, doc) &&
        _previewRevision == revision) {
      return;
    }
    _disposeLater(_preview);
    final world = World(context: doc.world.context)
      ..initialize()
      // Text that types itself out, bindings re-read — as in the document.
      ..addSystem(UiSystem());
    final canvas = doc.capture().instantiate(
      world,
      decode: doc.codec.decodeAll,
    );
    canvas.getComponent<UiCanvasComponent>()?.visible = true;
    // A file lists parents first and siblings in order, and is built in
    // that order: walked the same way, the copy's entities line up with the
    // document's one for one.
    final copies = <Entity>[];
    void walk(Entity e) {
      copies.add(e);
      for (final id
          in e.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        if (world.getEntity(id) case final child?) walk(child);
      }
    }

    walk(canvas);
    final originals = doc.entities;
    _previewIds = {
      for (var i = 0; i < originals.length && i < copies.length; i++)
        originals[i].id: copies[i].id,
    };
    _preview = world;
    _previewFor = doc;
    _previewRevision = revision;
    _previewKey = GlobalKey<UiLayerState>();
    _previewNodes = UiNodeBoxes();
    session.previewCanvas = canvas;
  }

  Widget _canvas(UiScreenDocument doc, Size space) {
    final rulers = session.rulers.value ? UiRulersPainter.thickness : 0.0;
    final device = session.device.value;
    final landscape = session.landscape.value;
    final frame = device.sizeFor(landscape: landscape);
    final room = Size(
      math.max(40, space.width - rulers - 48),
      math.max(40, space.height - rulers - 48),
    );
    session.fittedZoom = math.min(
      room.width / frame.width,
      room.height / frame.height,
    );
    final zoom = session.currentZoom;
    final centre =
        Offset(
          rulers + (space.width - rulers) / 2,
          rulers + (space.height - rulers) / 2,
        ) +
        session.pan.value;
    final shown = Size(frame.width * zoom, frame.height * zoom);
    final previewing = session.previewing;
    final repaint = Listenable.merge([_repaint, _overlay]);

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: EditorTheme.surfaceDarkest)),
          Positioned(
            left: centre.dx - shown.width / 2,
            top: centre.dy - shown.height / 2,
            width: shown.width,
            height: shown.height,
            child: _frameFor(
              doc,
              frame,
              device.insetsFor(landscape: landscape),
            ),
          ),
          // Everything the pointer does in Edit, and what is drawn over the
          // screen. In Preview it steps aside: the screen takes the pointer.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: previewing,
              child: _interaction(doc, repaint),
            ),
          ),
          if (rulers > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: UiRulersPainter(
                    metrics: () => session.metrics,
                    pointer: () => _overlay.pointer,
                    selection: _selectionBox,
                    repaint: repaint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Rect? _selectionBox() {
    final m = session.metrics;
    if (m == null) return null;
    Rect? box;
    for (final e in session.selection) {
      final r = m.viewRectOf(e);
      if (r != null) box = box == null ? r : box.expandToInclude(r);
    }
    return box;
  }

  /// [_deviceFrame], built again only when what it shows changed.
  Widget _frameFor(UiScreenDocument doc, Size frame, EdgeInsets insets) {
    final media = MediaQuery.of(context);
    final key = (
      doc,
      frame,
      insets,
      session.previewing,
      session.textScale.value,
      _behind,
      _behindKey,
      _preview,
      _previewKey,
      _layerKey,
      media,
    );
    final built = _frame;
    if (built != null && key == _frameKey) return built;
    _frameKey = key;
    return _frame = _deviceFrame(doc, frame, insets, media);
  }

  /// The screen at its device's size, scaled into the space by the zoom.
  Widget _deviceFrame(
    UiScreenDocument doc,
    Size frame,
    EdgeInsets insets,
    MediaQueryData outer,
  ) {
    final media = outer.copyWith(
      size: frame,
      padding: insets,
      viewPadding: insets,
      textScaler: TextScaler.linear(session.textScale.value),
    );
    final preview = session.previewing ? _preview : null;
    // Editing: the screen is a picture of itself. Its buttons are not
    // pressed and its fields take no keys — a click selects, and Enter
    // runs nothing. Previewing: the copy, to be played with.
    final Widget layer = preview != null
        ? UiLayer(
            key: _previewKey,
            world: preview,
            nodes: _previewNodes,
            actionHost: _previewHost(),
          )
        : IgnorePointer(
            child: ExcludeFocus(
              child: UiLayer(
                key: _layerKey,
                world: doc.world,
                nodes: session.nodes,
                actionHost: _previewHost(),
              ),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 24)],
        border: Border.all(color: EditorTheme.borderStrong),
      ),
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: frame.width,
            height: frame.height,
            child: MediaQuery(
              data: media,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF2B3A4A)),
                  ),
                  if (_behind case final behind?)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeFocus(
                          child: Opacity(
                            opacity: 0.75,
                            child: UiLayer(
                              key: _behindKey,
                              world: behind,
                              actionHost: const UiActionHost(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(child: layer),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the preview's buttons go: nowhere near the game. What they would
  /// do is said in the strip instead.
  UiActionHost _previewHost() {
    void said(String what) => session.lastAction.value = what;
    return UiActionHost(
      loadScene: (scene) => said('Opens the level $scene'),
      pause: () => said('Pauses the game'),
      resume: () => said('Resumes the game'),
      quit: () => said('Quits'),
      playSound: (path) => said('Plays $path'),
      pushScreen: (name) => name == _doc?.name
          ? said('Opens $name — this screen')
          : said('Opens $name'),
      back: () => said('Goes back — closes this screen'),
      showUi: (name, visible) => said(
        visible == false
            ? 'Hides $name'
            : (visible == true ? 'Shows $name' : 'Flips $name'),
      ),
    );
  }

  Widget _interaction(UiScreenDocument doc, Listenable repaint) {
    final painted = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (_) => _cancel(),
      onPointerSignal: _signal,
      onPointerPanZoomUpdate: _panZoom,
      child: GestureDetector(
        onSecondaryTapUp: (d) => _menu(d.localPosition, d.globalPosition),
        child: SizedBox.expand(
          key: _viewKey,
          child: CustomPaint(
            painter: UiCanvasPainter(
              session: session,
              overlay: _overlay,
              repaint: repaint,
            ),
          ),
        ),
      ),
    );
    return DragTarget<UiPaletteDrag>(
      onWillAcceptWithDetails: (_) => !session.previewing,
      onMove: (details) => _paletteHover(details.offset),
      onLeave: (_) {
        _overlay.insertMark = null;
        _overlay.changed();
      },
      onAcceptWithDetails: (details) =>
          _paletteDrop(details.data, details.offset),
      builder: (context, _, _) => ValueListenableBuilder<MouseCursor>(
        valueListenable: _cursor,
        builder: (context, cursor, child) => MouseRegion(
          cursor: cursor,
          onHover: (e) => _hovering(e.localPosition),
          onExit: (_) {
            _overlay
              ..pointer = null
              ..hovered = null
              ..changed();
            _updateCursor();
          },
          child: child,
        ),
        child: painted,
      ),
    );
  }

  /// Gives the pointer the shape for what is under it.
  void _updateCursor() {
    final next = _cursorNow();
    if (_cursor.value != next) _cursor.value = next;
  }

  MouseCursor _cursorNow() {
    final drag = _drag;
    if (drag?.kind == _DragKind.pan || _spaceHeld) {
      return SystemMouseCursors.grab;
    }
    final m = session.metrics;
    final primary = session.selection.firstOrNull;
    final at = _overlay.pointer;
    if (m != null &&
        primary != null &&
        at != null &&
        primary.id != _doc?.canvas.id) {
      final r = m.viewRectOf(primary);
      final handle = r == null ? null : UiCanvasPainter.handleAt(r, at);
      if (handle != null) return _cursorFor(handle);
    }
    return SystemMouseCursors.basic;
  }

  static MouseCursor _cursorFor(UiHandle handle) => switch (handle) {
    UiHandle.left || UiHandle.right => SystemMouseCursors.resizeLeftRight,
    UiHandle.top || UiHandle.bottom => SystemMouseCursors.resizeUpDown,
    UiHandle.topLeft ||
    UiHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    UiHandle.topRight ||
    UiHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    UiHandle.move => SystemMouseCursors.move,
  };

  void _hovering(Offset p) {
    final m = session.metrics;
    _overlay
      ..pointer = p
      ..hovered = m?.pick(p)
      ..changed();
    _updateCursor();
  }

  // ── Pointer ────────────────────────────────────────────────────────────

  bool get _snapping => session.snap.value && !EditorKeys.primaryPressed;

  /// How near counts as lined up, in design pixels: the same few pixels on
  /// screen whatever the zoom.
  double get _threshold => 6 / (session.metrics?.scale ?? 1);

  void _down(PointerDownEvent e) {
    final doc = _doc;
    final m = session.metrics;
    if (doc == null || m == null) return;
    final p = e.localPosition;
    if (e.buttons == kMiddleMouseButton ||
        (e.buttons == kPrimaryButton && _spaceHeld)) {
      _drag = _Drag(_DragKind.pan, p)..panAtStart = session.pan.value;
      _updateCursor();
      return;
    }
    if (e.buttons != kPrimaryButton) return;

    // A ruler: a new guide, dragged out of it.
    if (session.rulers.value) {
      const t = UiRulersPainter.thickness;
      if (p.dy < t || p.dx < t) {
        if (p.dx < t && p.dy < t) return;
        _drag = _Drag(_DragKind.guide, p)
          ..vertical = p.dx < t
          ..guides = session.guides
          ..guideIndex = -1;
        return;
      }
    }

    // A guide already there: moved, or dragged back out to be removed.
    if (session.showGuides.value) {
      final guides = session.guides;
      for (var i = 0; i < guides.length; i++) {
        final g = guides[i];
        final at = m.toView(Offset(g.at, g.at));
        final near = g.vertical ? (p.dx - at.dx).abs() : (p.dy - at.dy).abs();
        if (near <= 3) {
          _drag = _Drag(_DragKind.guide, p)
            ..vertical = g.vertical
            ..guides = guides
            ..guideIndex = i;
          return;
        }
      }
    }

    final primary = session.selection.firstOrNull;
    if (primary != null && primary.id != doc.canvas.id) {
      final r = m.viewRectOf(primary);
      final handle = r == null ? null : UiCanvasPainter.handleAt(r, p);
      final rect = m.designRectOf(primary);
      if (handle != null && rect != null) {
        _drag = _Drag(_DragKind.resize, p)
          ..handle = handle
          ..entities = [primary]
          ..rects = {primary: rect}
          ..slots = slotsOf([primary])
          ..label = 'Resize ${primary.name}';
        return;
      }
    }

    final state = doc.sceneState;
    var picked = m.pick(p);
    if (picked != null && HardwareKeyboard.instance.isAltPressed) {
      // Alt: the one it sits in.
      final parentId = picked.getComponent<ParentComponent>()?.parentId;
      picked = parentId == null
          ? picked
          : doc.world.getEntity(parentId) ?? picked;
    }
    final additive =
        HardwareKeyboard.instance.isShiftPressed || EditorKeys.primaryPressed;
    if (picked == null || picked.id == doc.canvas.id) {
      // Empty space: a marquee if the pointer moves, and the canvas — the
      // screen's own settings — if it was only a click there. Selected on
      // release, so the canvas is never left in what a marquee catches.
      if (!additive) state.clearSelection();
      _drag = _Drag(_DragKind.marquee, p)..onCanvas = picked != null;
      return;
    }
    if (additive) {
      state.toggleMultiSelect(picked);
      return;
    }
    if (!state.isInMultiSelection(picked.id)) state.selectEntity(picked);
    final moving = session.editableSelection;
    if (moving.isEmpty) return;
    final flowOnly = moving.length == 1 && !UiEditOps.isPinned(moving.first);
    final entities = [
      for (final e in moving)
        if (UiEditOps.isPinned(e) || flowOnly) e,
    ];
    _drag = _Drag(flowOnly ? _DragKind.reorder : _DragKind.move, p)
      ..entities = entities
      ..rects = {for (final e in moving) e: ?m.designRectOf(e)}
      ..slots = slotsOf(moving)
      ..label = entities.length == 1
          ? 'Move ${entities.first.name}'
          : 'Move ${entities.length} elements';
  }

  void _move(PointerMoveEvent e) {
    final drag = _drag;
    final doc = _doc;
    final m = session.metrics;
    if (drag == null || doc == null || m == null) return;
    final p = e.localPosition;
    _overlay.pointer = p;
    if (!drag.started) {
      // A click is not a drag: a few pixels of hand-shake moved things
      // before, and pushed an undo step for nothing.
      if ((p - drag.start).distance < kTouchSlop) return;
      drag.started = true;
      doc.history.breakMerge();
      if (drag.kind == _DragKind.move || drag.kind == _DragKind.resize) {
        // The panels showing what the drag changes catch up when it ends.
        _overlay.dragging = true;
        session.dragging.value = true;
      }
    }
    final delta = (p - drag.start) / m.scale;
    switch (drag.kind) {
      case _DragKind.pan:
        session.pan.value = drag.panAtStart + (p - drag.start);
      case _DragKind.marquee:
        _overlay.marquee = Rect.fromPoints(drag.start, p);
      case _DragKind.guide:
        _dragGuide(drag, m.toDesign(p));
      case _DragKind.move:
        _dragMove(doc, drag, delta);
      case _DragKind.resize:
        _dragResize(doc, drag, delta);
      case _DragKind.reorder:
        _dragReorder(doc, drag, p);
    }
    _overlay.changed();
  }

  void _dragMove(UiScreenDocument doc, _Drag drag, Offset delta) {
    if (drag.entities.isEmpty) return;
    var shift = delta;
    var guides = const <SnapGuide>[];
    // The whole selection moves as one box, snapped as one.
    Rect? box;
    for (final e in drag.entities) {
      final r = drag.rects[e];
      if (r != null) box = box == null ? r : box.expandToInclude(r);
    }
    if (box != null && _snapping) {
      final (snapped, lines) = _targetsFor(
        doc,
        drag.entities,
      ).move(box.shift(delta), _threshold);
      shift = snapped.topLeft - box.topLeft;
      guides = lines;
    }
    session.snapGuides.value = guides;
    final targets = {
      for (final e in drag.entities)
        if (drag.rects[e] case final r?) e: r.shift(shift),
    };
    // Applied as it goes — back where it began included — and recorded as
    // one step when it ends.
    session.dragTo(targets, from: drag.slots, keepSize: true);
    final first = targets.values.firstOrNull;
    _overlay.dragLabel = first == null
        ? null
        : '${first.left.round()}, ${first.top.round()}';
  }

  void _dragResize(UiScreenDocument doc, _Drag drag, Offset delta) {
    final e = drag.entities.first;
    final start = drag.rects[e];
    if (start == null) return;
    var rect = UiGeometry.resize(
      start,
      drag.handle,
      delta,
      keepAspect: HardwareKeyboard.instance.isShiftPressed,
      fromCentre: HardwareKeyboard.instance.isAltPressed,
    );
    var guides = const <SnapGuide>[];
    if (_snapping) {
      (rect, guides) = _targetsFor(doc, [
        e,
      ]).resize(rect, drag.handle, _threshold);
    }
    session.snapGuides.value = guides;
    session.dragTo({e: rect}, from: drag.slots);
    _overlay.dragLabel = '${rect.width.round()} × ${rect.height.round()}';
  }

  /// A flow child dragged along its row or column: where it would land.
  void _dragReorder(UiScreenDocument doc, _Drag drag, Offset p) {
    final m = session.metrics!;
    final e = drag.entities.first;
    final parentId = e.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : doc.world.getEntity(parentId);
    if (parent == null) return;
    final siblings = [
      for (final id
          in parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[])
        if (id != e.id) ?doc.world.getEntity(id),
    ];
    final horizontal =
        parent.getComponent<UiLayoutComponent>()?.kind == UiLayoutKind.row ||
        parent.getComponent<UiLayoutComponent>()?.kind == UiLayoutKind.wrap;
    var index = 0;
    Rect? before;
    Rect? after;
    for (final s in siblings) {
      final r = m.viewRectOf(s);
      if (r == null) continue;
      final past = horizontal ? p.dx > r.center.dx : p.dy > r.center.dy;
      if (past) {
        index++;
        before = r;
      } else {
        after ??= r;
      }
    }
    drag.insertAt = index;
    final own = m.viewRectOf(parent);
    UiInsertMark? mark;
    if (horizontal) {
      final x = before != null && after != null
          ? (before.right + after.left) / 2
          : before?.right ?? after?.left ?? own?.left ?? p.dx;
      final top = (before ?? after ?? own)?.top ?? p.dy - 10;
      final bottom = (before ?? after ?? own)?.bottom ?? p.dy + 10;
      mark = UiInsertMark(Offset(x, top), Offset(x, bottom));
    } else {
      final y = before != null && after != null
          ? (before.bottom + after.top) / 2
          : before?.bottom ?? after?.top ?? own?.top ?? p.dy;
      final left = (before ?? after ?? own)?.left ?? p.dx - 10;
      final right = (before ?? after ?? own)?.right ?? p.dx + 10;
      mark = UiInsertMark(Offset(left, y), Offset(right, y));
    }
    _overlay.insertMark = mark;
  }

  void _dragGuide(_Drag drag, Offset design) {
    final at = drag.vertical ? design.dx : design.dy;
    final value = session.grid.value
        ? UiGeometry.onGrid(at, session.gridStep.value)
        : at.roundToDouble();
    final next = [...drag.guides];
    final guide = UiGuide(vertical: drag.vertical, at: value);
    if (drag.guideIndex < 0) {
      next.add(guide);
    } else {
      next[drag.guideIndex] = guide;
    }
    session.snapGuides.value = [
      SnapGuide(
        vertical: drag.vertical,
        position: value,
        start: -100000,
        end: 100000,
      ),
    ];
    _overlay.dragLabel = null;
    _pendingGuides = next;
  }

  List<UiGuide>? _pendingGuides;

  void _up(PointerUpEvent e) {
    final drag = _drag;
    final doc = _doc;
    _drag = null;
    session.snapGuides.value = const [];
    if (drag == null || doc == null) {
      _endGesture();
      return;
    }
    final m = session.metrics;
    switch (drag.kind) {
      case _DragKind.marquee:
        _endMarquee(doc, drag, m);
      case _DragKind.move || _DragKind.resize:
        if (drag.started) session.endDrag(drag.slots, label: drag.label);
      case _DragKind.reorder:
        if (drag.started && drag.insertAt >= 0) {
          session.reorder(drag.entities.first, drag.insertAt);
        }
      case _DragKind.guide:
        final pending = _pendingGuides;
        _pendingGuides = null;
        if (drag.started && pending != null) {
          const t = UiRulersPainter.thickness;
          final p = e.localPosition;
          // Dropped back on a ruler: gone.
          final onRuler = drag.vertical ? p.dx < t : p.dy < t;
          if (onRuler && drag.guideIndex >= 0) {
            final left = [...drag.guides]..removeAt(drag.guideIndex);
            session.setGuides(left, label: 'Remove guide');
          } else if (!onRuler) {
            session.setGuides(
              pending,
              label: drag.guideIndex < 0 ? 'Add guide' : 'Move guide',
            );
          }
        }
      case _DragKind.pan:
        break;
    }
    _endGesture();
  }

  /// A press on empty space let go: what a marquee caught is selected —
  /// added to the selection when Shift or the primary modifier was held —
  /// and a click that never became one selects the canvas.
  void _endMarquee(UiScreenDocument doc, _Drag drag, UiCanvasMetrics? m) {
    final state = doc.sceneState;
    final box = _overlay.marquee;
    if (!drag.started || box == null || m == null) {
      if (drag.onCanvas && !state.hasAnySelection) {
        state.selectEntity(doc.canvas);
      }
      return;
    }
    final inside = m.inside(box);
    // A screen and its elements are not selected together: the canvas
    // gives way to what was caught.
    if (state.selectedEntity.value?.id == doc.canvas.id && inside.isNotEmpty) {
      state.clearSelection();
    }
    for (final entity in inside) {
      if (!state.hasAnySelection) {
        state.selectEntity(entity);
      } else if (!state.isInMultiSelection(entity.id)) {
        state.toggleMultiSelect(entity);
      }
    }
  }

  /// Clears what a gesture drew, and lets the panels catch up.
  void _endGesture() {
    _overlay
      ..marquee = null
      ..insertMark = null
      ..dragLabel = null
      ..dragging = false
      ..changed();
    if (session.dragging.value) session.dragging.value = false;
    _updateCursor();
  }

  void _cancel() {
    final drag = _drag;
    final doc = _doc;
    _drag = null;
    // A drag cut short puts things back where they began, and leaves no
    // step behind: nothing of it was recorded yet.
    if (drag != null &&
        drag.started &&
        doc != null &&
        (drag.kind == _DragKind.move || drag.kind == _DragKind.resize)) {
      session.cancelDrag(drag.slots);
    }
    _pendingGuides = null;
    session.snapGuides.value = const [];
    _endGesture();
  }

  /// Escape while dragging: the drag is dropped, and nothing else happens.
  bool cancelDrag() {
    if (_drag == null) return false;
    _cancel();
    return true;
  }

  /// What a moving [entities] may line up with: their siblings, their
  /// parent and the canvas, the guides, and the grid.
  UiSnapTargets _targetsFor(UiScreenDocument doc, List<Entity> entities) {
    final m = session.metrics!;
    final moving = {for (final e in entities) e.id};
    final rects = <Rect>[];
    final parents = <Entity>{};
    for (final e in entities) {
      final parentId = e.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : doc.world.getEntity(parentId);
      if (parent != null) parents.add(parent);
    }
    for (final parent in parents) {
      if (m.contentRectOf(parent) case final r?) rects.add(r);
      for (final id
          in parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        if (moving.contains(id)) continue;
        final sibling = doc.world.getEntity(id);
        if (sibling == null) continue;
        final slot = sibling.getComponent<UiSlotComponent>();
        if (slot != null && !slot.visible) continue;
        if (m.designRectOf(sibling) case final r?) rects.add(r);
      }
    }
    final canvas = Offset.zero & m.designSize;
    rects.add(canvas);
    final guides = session.showGuides.value
        ? session.guides
        : const <UiGuide>[];
    return UiSnapTargets(
      rects: rects,
      xLines: [
        for (final g in guides)
          if (g.vertical) g.at,
      ],
      yLines: [
        for (final g in guides)
          if (!g.vertical) g.at,
      ],
      grid: session.grid.value ? session.gridStep.value : 0,
    );
  }

  // ── Wheel and trackpad ─────────────────────────────────────────────────

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (EditorKeys.primaryPressed) {
      final factor = math.pow(0.9985, e.scrollDelta.dy).toDouble();
      _zoomAt(e.localPosition, session.currentZoom * factor);
      return;
    }
    // A wheel scrolls the view, as everywhere else; Shift turns it sideways.
    final d = HardwareKeyboard.instance.isShiftPressed
        ? Offset(e.scrollDelta.dy, e.scrollDelta.dx)
        : e.scrollDelta;
    session.pan.value -= d;
  }

  void _panZoom(PointerPanZoomUpdateEvent e) {
    session.pan.value += e.panDelta;
    if (e.scale != 1) {
      _zoomAt(e.localPosition, session.currentZoom * e.scale);
    }
  }

  /// Zooms to [zoom] keeping the design point under [at] where it is.
  void _zoomAt(Offset at, double zoom) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final old = session.currentZoom;
    final next = zoom.clamp(0.05, 8.0);
    final rulers = session.rulers.value ? UiRulersPainter.thickness : 0.0;
    final centre = Offset(
      rulers + (box.size.width - rulers) / 2,
      rulers + (box.size.height - rulers) / 2,
    );
    final pan = session.pan.value;
    final fromCentre = at - centre - pan;
    session.zoom.value = next;
    session.pan.value = at - centre - fromCentre * (next / old);
  }

  // ── Palette ────────────────────────────────────────────────────────────

  void _paletteHover(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    final m = session.metrics;
    final doc = _doc;
    if (box == null || m == null || doc == null) return;
    final p = box.globalToLocal(global);
    _overlay
      ..pointer = p
      ..hovered = UiCreate.parentFor(doc, m.pick(p))
      ..changed();
  }

  void _paletteDrop(UiPaletteDrag data, Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    final m = session.metrics;
    final doc = _doc;
    if (box == null || m == null || doc == null) return;
    final p = box.globalToLocal(global);
    final parent = UiCreate.parentFor(doc, m.pick(p));
    final content = m.contentRectOf(parent);
    final at = content == null ? null : m.toDesign(p) - content.topLeft;
    doc.history.breakMerge();
    UiCreate.create(
      doc,
      data.kind,
      parent: parent,
      at: UiCreate.placesByAnchor(parent) ? at : null,
    );
    _overlay
      ..hovered = null
      ..insertMark = null
      ..changed();
  }

  // ── Menu ───────────────────────────────────────────────────────────────

  Future<void> _menu(Offset local, Offset global) async {
    final doc = _doc;
    final m = session.metrics;
    if (doc == null || m == null || session.previewing) return;
    final picked = m.pick(local);
    final state = doc.sceneState;
    if (picked != null && !state.isInMultiSelection(picked.id)) {
      state.selectEntity(picked);
    }
    final entity = state.selectedEntity.value;
    final editable = session.editableSelection.isNotEmpty;
    final slot = entity?.getComponent<UiSlotComponent>();
    final parentId = entity?.getComponent<ParentComponent>()?.parentId;
    final chosen = await showEditorMenu<String>(context, global, [
      editorMenuItem(
        'cut',
        'Cut',
        icon: Icons.content_cut,
        shortcut: EditorKeys.withPrimary('X'),
        enabled: editable,
      ),
      editorMenuItem(
        'copy',
        'Copy',
        icon: Icons.copy,
        shortcut: EditorKeys.withPrimary('C'),
        enabled: editable,
      ),
      editorMenuItem(
        'paste',
        'Paste',
        icon: Icons.content_paste,
        shortcut: EditorKeys.withPrimary('V'),
        enabled: UiEditOps.clipboard != null,
      ),
      editorMenuItem(
        'duplicate',
        'Duplicate',
        icon: Icons.control_point_duplicate,
        shortcut: EditorKeys.withPrimary('D'),
        enabled: editable,
      ),
      editorMenuItem(
        'delete',
        'Delete',
        icon: Icons.delete_outline,
        shortcut: EditorKeys.isMac ? 'Delete' : 'Del',
        enabled: editable,
      ),
      editorMenuDivider(),
      editorMenuItem(
        'parent',
        'Select what it sits in',
        icon: Icons.north_west,
        enabled: parentId != null,
      ),
      editorMenuItem(
        'front',
        'Bring to front',
        icon: Icons.flip_to_front,
        enabled: editable,
      ),
      editorMenuItem(
        'back',
        'Send to back',
        icon: Icons.flip_to_back,
        enabled: editable,
      ),
      if (slot != null) ...[
        editorMenuDivider(),
        editorMenuItem(
          'visible',
          slot.visible ? 'Hide' : 'Show',
          icon: slot.visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
      ],
    ]);
    if (chosen == null || !mounted) return;
    switch (chosen) {
      case 'cut':
        session.cutSelection();
      case 'copy':
        session.copySelection();
      case 'paste':
        session.paste();
      case 'duplicate':
        session.duplicateSelection();
      case 'delete':
        session.deleteSelection();
      case 'parent':
        final parent = parentId == null ? null : doc.world.getEntity(parentId);
        if (parent != null) state.selectEntity(parent);
      case 'front' || 'back':
        if (entity == null || parentId == null) break;
        final parent = doc.world.getEntity(parentId);
        final count =
            parent?.getComponent<ChildrenComponent>()?.childIds.length ?? 1;
        session.reorder(entity, chosen == 'front' ? count - 1 : 0);
      case 'visible':
        if (entity != null && slot != null) {
          session.setVisible(entity, !slot.visible);
        }
    }
  }
}

class _Tick extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _NothingOpen extends StatelessWidget {
  const _NothingOpen();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: EditorTheme.surfaceDarkest,
    child: const EditorEmptyState(
      icon: Icons.web_asset_outlined,
      title: 'No screen open',
      hint: 'Pick one on the left, or make a new one.',
    ),
  );
}

/// Keeps [UiBindings.samples] set to the open screen's sample values while
/// [child] is shown — so `{coins}` reads something in the editor, and never
/// in the game.
class UiSamplesScope extends StatefulWidget {
  const UiSamplesScope({super.key, required this.session, required this.child});

  final UiEditorSession session;
  final Widget child;

  @override
  State<UiSamplesScope> createState() => _UiSamplesScopeState();
}

class _UiSamplesScopeState extends State<UiSamplesScope> {
  late final VoidCallback _unwatchDocument;
  VoidCallback? _unwatchData;

  @override
  void initState() {
    super.initState();
    _unwatchDocument = widget.session.document.watch(_follow);
    _follow();
  }

  /// Listens to the open screen's samples, whichever screen that is.
  void _follow() {
    _unwatchData?.call();
    _unwatchData = widget.session.document.value?.editorData.watch(_apply);
    _apply();
  }

  void _apply() {
    UiBindings.samples = {
      for (final entry in widget.session.samples.entries)
        entry.key: num.tryParse(entry.value) ?? entry.value,
    };
  }

  @override
  void dispose() {
    _unwatchDocument();
    _unwatchData?.call();
    UiBindings.samples = const {};
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
