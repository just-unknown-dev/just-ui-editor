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
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/screen/ui_slot_component.dart';
import '../../runtime/layer/ui_layer.dart';
import '../../runtime/logic/ui_actions.dart';
import '../../runtime/logic/ui_bindings.dart';
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
  Map<UiSlotComponent, UiSlotState> slots = const {};
  UiHandle handle = UiHandle.move;
  int insertAt = -1;

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
  final _repaint = _Tick();
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'uiCanvasView');

  /// A fresh key for every screen opened: a layer keeps the navigator of the
  /// world it was first built on, so a new world needs a new layer.
  GlobalKey<UiLayerState> _layerKey = GlobalKey<UiLayerState>();
  UiScreenDocument? _layerFor;

  /// The other screens drawn underneath, in a world of their own so their
  /// names and ids never mix with the one being edited.
  World? _behind;
  List<String> _behindNames = const [];
  final GlobalKey<UiLayerState> _behindKey = GlobalKey<UiLayerState>();

  Duration? _lastTick;
  _Drag? _drag;
  Offset? _pointer;
  Entity? _hover;
  Rect? _marquee;
  UiInsertMark? _insert;
  String? _dragLabel;
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
    _behind?.dispose();
    session.metrics = null;
    super.dispose();
  }

  // Space held down turns a drag into a pan, as in any drawing program.
  bool _onKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !WorkspaceKeyScope.isTyping) {
      _spaceHeld = event is! KeyUpEvent;
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
    if (doc != null) {
      if (session.previewing) doc.world.update(dt);
      _applyForcedState(doc);
      _layerKey.currentState?.sync();
    }
    _behindKey.currentState?.sync();
    final view = _viewKey.currentContext?.findRenderObject();
    session.metrics = doc != null && view is RenderBox && view.hasSize
        ? UiCanvasMetrics(view: view, document: doc, nodes: session.nodes)
        : null;
    session.syncShownZoom();
    _repaint.notify();
  }

  /// Buttons shown in the state the preview strip asks for — every button,
  /// or the selected ones when there are any.
  void _applyForcedState(UiScreenDocument doc) {
    final forced = session.forcedState.value;
    final selected = {for (final e in session.selection) e.id};
    for (final e in doc.world.query([ButtonComponent])) {
      final button = e.getComponent<ButtonComponent>()!;
      final applies =
          forced != null && (selected.isEmpty || selected.contains(e.id));
      final want = applies ? forced : UiInteractionState.normal;
      if (!session.previewing || applies) {
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
    _behind?.dispose();
    _behind = null;
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

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: EditorTheme.surfaceDarkest)),
          Positioned(
            left: centre.dx - shown.width / 2,
            top: centre.dy - shown.height / 2,
            width: shown.width,
            height: shown.height,
            child: _deviceFrame(
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
              child: _interaction(doc),
            ),
          ),
          if (rulers > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: UiRulersPainter(
                    metrics: () => session.metrics,
                    pointer: _pointer,
                    selection: _selectionBox,
                    repaint: _repaint,
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

  /// The screen at its device's size, scaled into the space by the zoom.
  Widget _deviceFrame(UiScreenDocument doc, Size frame, EdgeInsets insets) {
    final previewing = session.previewing;
    final media = MediaQuery.of(context).copyWith(
      size: frame,
      padding: insets,
      viewPadding: insets,
      textScaler: TextScaler.linear(session.textScale.value),
    );
    Widget layer = UiLayer(
      key: _layerKey,
      world: doc.world,
      nodes: session.nodes,
      actionHost: _previewHost(),
    );
    if (!previewing) {
      // Editing: the screen is a picture of itself. Its buttons are not
      // pressed and its fields take no keys — a click selects, and Enter
      // runs nothing.
      layer = IgnorePointer(child: ExcludeFocus(child: layer));
    }
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

  Widget _interaction(UiScreenDocument doc) {
    return DragTarget<UiPaletteDrag>(
      onWillAcceptWithDetails: (_) => !session.previewing,
      onMove: (details) => _paletteHover(details.offset),
      onLeave: (_) => setState(() => _insert = null),
      onAcceptWithDetails: (details) =>
          _paletteDrop(details.data, details.offset),
      builder: (context, _, _) => MouseRegion(
        cursor: _cursor(),
        onHover: (e) => _hovering(e.localPosition),
        onExit: (_) => setState(() {
          _pointer = null;
          _hover = null;
        }),
        child: Listener(
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
                  hovered: _drag == null ? _hover : null,
                  marquee: _marquee,
                  insertMark: _insert,
                  dragLabel: _dragLabel,
                  repaint: _repaint,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _cursor() {
    final drag = _drag;
    if (drag?.kind == _DragKind.pan || _spaceHeld) {
      return SystemMouseCursors.grab;
    }
    final m = session.metrics;
    final primary = session.selection.firstOrNull;
    final at = _pointer;
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
    setState(() {
      _pointer = p;
      _hover = m?.pick(p);
    });
  }

  // ── Pointer ────────────────────────────────────────────────────────────

  bool get _snapping =>
      session.snap.value && !HardwareKeyboard.instance.isControlPressed;

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
      if (handle != null) {
        _drag = _Drag(_DragKind.resize, p)
          ..handle = handle
          ..entities = [primary]
          ..rects = {primary: m.designRectOf(primary)!}
          ..slots = slotsOf([primary]);
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
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (picked == null || picked.id == doc.canvas.id) {
      if (!additive) state.clearSelection();
      _drag = _Drag(_DragKind.marquee, p);
      if (picked != null && !additive) state.selectEntity(picked);
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
    _drag = _Drag(flowOnly ? _DragKind.reorder : _DragKind.move, p)
      ..entities = [
        for (final e in moving)
          if (UiEditOps.isPinned(e) || flowOnly) e,
      ]
      ..rects = {for (final e in moving) e: ?m.designRectOf(e)}
      ..slots = slotsOf(moving);
  }

  void _move(PointerMoveEvent e) {
    final drag = _drag;
    final doc = _doc;
    final m = session.metrics;
    if (drag == null || doc == null || m == null) return;
    final p = e.localPosition;
    _pointer = p;
    if (!drag.started) {
      // A click is not a drag: a few pixels of hand-shake moved things
      // before, and pushed an undo step for nothing.
      if ((p - drag.start).distance < kTouchSlop) return;
      drag.started = true;
      doc.history.breakMerge();
    }
    final delta = (p - drag.start) / m.scale;
    switch (drag.kind) {
      case _DragKind.pan:
        session.pan.value = drag.panAtStart + (p - drag.start);
      case _DragKind.marquee:
        setState(() => _marquee = Rect.fromPoints(drag.start, p));
      case _DragKind.guide:
        _dragGuide(drag, m.toDesign(p));
      case _DragKind.move:
        _dragMove(doc, drag, delta);
      case _DragKind.resize:
        _dragResize(doc, drag, delta);
      case _DragKind.reorder:
        _dragReorder(doc, drag, p);
    }
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
    session.placeAt(
      targets,
      label: drag.entities.length == 1
          ? 'Move ${drag.entities.first.name}'
          : 'Move ${drag.entities.length} elements',
      from: drag.slots,
    );
    final first = targets.values.firstOrNull;
    setState(
      () => _dragLabel = first == null
          ? null
          : '${first.left.round()}, ${first.top.round()}',
    );
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
    session.placeAt({e: rect}, label: 'Resize ${e.name}', from: drag.slots);
    setState(
      () => _dragLabel = '${rect.width.round()} × ${rect.height.round()}',
    );
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
    setState(() => _insert = mark);
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
    setState(() => _dragLabel = null);
    _pendingGuides = next;
  }

  List<UiGuide>? _pendingGuides;

  void _up(PointerUpEvent e) {
    final drag = _drag;
    final doc = _doc;
    _drag = null;
    session.snapGuides.value = const [];
    if (drag == null || doc == null) {
      setState(() {});
      return;
    }
    final m = session.metrics;
    switch (drag.kind) {
      case _DragKind.marquee:
        final box = _marquee;
        if (box != null && m != null) {
          final inside = m.inside(box);
          final state = doc.sceneState;
          for (final (i, entity) in inside.indexed) {
            if (i == 0 && !state.hasAnySelection) {
              state.selectEntity(entity);
            } else if (!state.isInMultiSelection(entity.id)) {
              state.toggleMultiSelect(entity);
            }
          }
        }
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
      default:
        break;
    }
    setState(() {
      _marquee = null;
      _insert = null;
      _dragLabel = null;
    });
  }

  void _cancel() {
    final drag = _drag;
    final doc = _doc;
    _drag = null;
    // A drag cut short puts things back where they began.
    if (drag != null && drag.started && doc != null && drag.slots.isNotEmpty) {
      final command = UiSlotEditCommand(
        label: 'Cancel',
        sceneState: doc.sceneState,
        changes: {
          for (final entry in drag.slots.entries)
            entry.key: (UiSlotState.of(entry.key), entry.value),
        },
      );
      command.redo();
    }
    session.snapGuides.value = const [];
    setState(() {
      _marquee = null;
      _insert = null;
      _dragLabel = null;
    });
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
    if (HardwareKeyboard.instance.isControlPressed) {
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
    setState(() {
      _pointer = p;
      _hover = UiCreate.parentFor(doc, m.pick(p));
    });
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
    setState(() {
      _hover = null;
      _insert = null;
    });
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
        shortcut: 'Ctrl+X',
        enabled: editable,
      ),
      editorMenuItem(
        'copy',
        'Copy',
        icon: Icons.copy,
        shortcut: 'Ctrl+C',
        enabled: editable,
      ),
      editorMenuItem(
        'paste',
        'Paste',
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: UiEditOps.clipboard != null,
      ),
      editorMenuItem(
        'duplicate',
        'Duplicate',
        icon: Icons.control_point_duplicate,
        shortcut: 'Ctrl+D',
        enabled: editable,
      ),
      editorMenuItem(
        'delete',
        'Delete',
        icon: Icons.delete_outline,
        shortcut: 'Del',
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
