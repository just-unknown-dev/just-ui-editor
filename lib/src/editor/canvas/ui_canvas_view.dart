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

import '../../bindings/bindings.dart';
import '../../controls/controls.dart';
import '../../layout/layout.dart';
import '../../screens/screens.dart';
import '../document/ui_screen_document.dart';
import '../geometry/ui_canvas_metrics.dart';
import '../geometry/ui_geometry.dart';
import '../session/ui_create.dart';
import '../session/ui_editor_session.dart';
import '../session/ui_editor_session_edits.dart';
import '../session/ui_slot_edit.dart';
import 'ui_canvas_painter.dart';
import 'ui_rulers.dart';

part 'ui_canvas_gestures.dart';
part 'ui_canvas_preview.dart';

/// What a palette drag carries: the kind to make.
class UiPaletteDrag {
  const UiPaletteDrag(this.kind);
  final String kind;
}

/// The device frame, the screen in it, and the handles over it.
class UiCanvasView extends StatefulWidget {
  const UiCanvasView({super.key, required this.session});

  final UiEditorSession session;

  @override
  State<UiCanvasView> createState() => UiCanvasViewState();
}

/// The canvas's state: the worlds it shows, the drag under way, and the
/// ticker that keeps them in step while anything changes.
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

  /// The layer the open screen is drawn by. A layer follows the world it
  /// is given, so one key serves every screen opened.
  final GlobalKey<UiLayerState> _layerKey = GlobalKey<UiLayerState>();
  UiScreenDocument? _layerFor;

  /// The other screens drawn underneath, in a world of their own so their
  /// names and ids never mix with the one being edited.
  World? _behind;
  List<String> _behindNames = const [];
  final GlobalKey<UiLayerState> _behindKey = GlobalKey<UiLayerState>();

  /// What Preview shows: a copy of the open screen, built when Preview
  /// begins and thrown away when it ends. A player's toggles, sliders and
  /// typing change the copy's components, and a Back closes the copy's
  /// canvas; the document's — what Save writes — is never touched. Made
  /// again when the document is edited while Preview is on.
  World? _preview;
  UiScreenDocument? _previewFor;
  int _previewRevision = -1;
  final GlobalKey<UiLayerState> _previewKey = GlobalKey<UiLayerState>();
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
    // Anything the canvas shows changing wakes it.
    _unwatch.addAll([
      for (final signal in <Signal<Object?>>[
        session.document,
        session.device,
        session.landscape,
        session.zoom,
        session.pan,
        session.mode,
        session.rulers,
        session.grid,
        session.gridStep,
        session.showGuides,
        session.boxes,
        session.snapGuides,
        session.textScale,
        session.forcedState,
        session.behind,
      ])
        signal.watch(wake),
    ]);
  }

  /// Whether the view is ticking: something changed in the last second,
  /// or something on it moves by itself.
  @visibleForTesting
  bool get isTicking => _ticker.isActive;

  /// What the ticker is woken by, let go of with the view.
  final List<VoidCallback> _unwatch = [];

  /// The open screen's own signals, watched while it is open.
  final List<VoidCallback> _unwatchDoc = [];
  UiScreenDocument? _watchedDoc;

  /// Whether something woke the view since the last tick.
  bool _woken = true;

  /// When, by the ticker, something last changed.
  Duration _activeAt = Duration.zero;

  /// Makes the view tick again: something changed, or the pointer moved.
  /// It stops by itself a second after the last change, while nothing in
  /// the screen moves on its own — so an editor left open lets the app
  /// idle.
  void wake() {
    _woken = true;
    if (!mounted || _ticker.isActive) return;
    _lastTick = null;
    _lastPainted = Duration.zero;
    _activeAt = Duration.zero;
    _ticker.start();
  }

  /// Watches [doc]'s edits, selection and samples, instead of the screen
  /// open before.
  void _watch(UiScreenDocument? doc) {
    if (identical(doc, _watchedDoc)) return;
    _watchedDoc = doc;
    for (final unwatch in _unwatchDoc) {
      unwatch();
    }
    _unwatchDoc.clear();
    if (doc == null) return;
    _unwatchDoc.addAll([
      doc.sceneState.revision.watch(wake),
      doc.sceneState.selectedEntity.watch(wake),
      doc.sceneState.multiSelectedIds.watch(wake),
      doc.history.revision.watch(wake),
      doc.editorData.watch(wake),
    ]);
  }

  /// Whether something on the canvas moves by itself: Preview, a drag, a
  /// text that types itself out or animates.
  bool _busy(UiScreenDocument? doc) {
    if (session.previewing || _drag != null) return true;
    final world = doc?.world;
    if (world == null) return false;
    for (final e in world.query(const [UiTextComponent])) {
      final text = e.getComponent<UiTextComponent>()!;
      if (text.isRevealing || (text.resolved?.animates ?? false)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    for (final unwatch in [..._unwatch, ..._unwatchDoc]) {
      unwatch();
    }
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
    wake();
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
    if (_woken) {
      _woken = false;
      _activeAt = elapsed;
    } else if (!_busy(doc) &&
        elapsed - _activeAt > const Duration(seconds: 1)) {
      // Nothing has changed for a second, and nothing moves by itself.
      _ticker.stop();
    }
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
        _watch(doc);
        wake();
        _syncPreview(doc);
        if (doc == null) return const _NothingOpen();
        if (!identical(_layerFor, doc)) {
          _layerFor = doc;
          session.showSamplesIn(doc.world);
        }
        _syncBehind(doc);
        return LayoutBuilder(
          builder: (context, box) => _canvas(doc, box.biggest),
        );
      },
    );
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

  Widget _interaction(UiScreenDocument doc, Listenable repaint) {
    final painted = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        wake();
        _down(e);
      },
      onPointerMove: (e) {
        wake();
        _move(e);
      },
      onPointerUp: (e) {
        wake();
        _up(e);
      },
      onPointerCancel: (_) {
        wake();
        _cancel();
      },
      onPointerSignal: (e) {
        wake();
        _signal(e);
      },
      onPointerPanZoomUpdate: (e) {
        wake();
        _panZoom(e);
      },
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
      onMove: (details) {
        wake();
        _paletteHover(details.offset);
      },
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
          onHover: (e) {
            wake();
            _hovering(e.localPosition);
          },
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

  List<UiGuide>? _pendingGuides;

  /// Escape while dragging: the drag is dropped, and nothing else happens.
  bool cancelDrag() {
    if (_drag == null) return false;
    _cancel();
    return true;
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
