// The canvas's gestures: picking, dragging, resizing, reordering,
// guides, the marquee, the wheel, palette drops and the menu.
part of 'ui_canvas_view.dart';

/// How [UiCanvasViewState] answers the pointer.
extension _UiCanvasGestures on UiCanvasViewState {
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
    final flowOnly =
        moving.length == 1 && !UiEditorSessionEdits.isPinned(moving.first);
    final entities = [
      for (final e in moving)
        if (UiEditorSessionEdits.isPinned(e) || flowOnly) e,
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
        enabled: UiEditorSessionEdits.clipboard != null,
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
