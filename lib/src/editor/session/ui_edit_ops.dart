/// Everything done to a screen's elements, each one an undo step.
library;

import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/screen/ui_slot_component.dart';
import '../canvas/ui_geometry.dart';
import '../create/ui_create.dart';
import '../document/ui_screen_document.dart';
import 'ui_editor_session.dart';
import 'ui_slot_edit.dart';

/// How a set of elements is lined up.
enum UiAlign { left, centerX, right, top, centerY, bottom }

/// The screen's own clipboard: what was copied, as it would be saved, with
/// each copy's parent named relative to the copied set.
class UiClipboard {
  UiClipboard(this.records);

  /// Parents first. A root's parent name is null.
  final List<EntitySpec> records;
}

extension UiEditOps on UiEditorSession {
  UiScreenDocument? get _document => document.value;

  /// The selection without the canvas — which is the screen, and is never
  /// deleted, copied or moved from here — and without anything inside
  /// something else selected, which comes along with it.
  List<Entity> get editableSelection {
    final doc = _document;
    if (doc == null) return const [];
    final picked = [
      for (final e in selection)
        if (e.id != doc.canvas.id) e,
    ];
    return [
      for (final e in picked)
        if (!picked.any(
          (other) =>
              other.id != e.id &&
              isSelfOrDescendant(e, other, world: doc.world),
        ))
          e,
    ];
  }

  // ── Delete, duplicate, clipboard ───────────────────────────────────────

  void deleteSelection() {
    final doc = _document;
    final doomed = editableSelection;
    if (doc == null || doomed.isEmpty) return;
    doc.history.push(
      DeleteEntitiesCommand(
        label: doomed.length == 1
            ? 'Delete ${doomed.first.name}'
            : 'Delete ${doomed.length} elements',
        world: doc.world,
        sceneState: doc.sceneState,
        entities: doomed,
        codec: doc.codec,
      ),
    );
  }

  /// [roots] and everything under them, as records whose parent names
  /// refer to one another — ready to be made again elsewhere.
  List<EntitySpec> _recordsOf(UiScreenDocument doc, List<Entity> roots) {
    final out = <EntitySpec>[];
    void walk(Entity e, String? parentName) {
      final spec = EntitySpec.of(e, doc.codec, world: doc.world);
      out.add(
        EntitySpec(
          name: e.name,
          componentsJson: [
            for (final json in spec.componentsJson)
              if (json['type'] != 'ParentComponent' &&
                  json['type'] != 'ChildrenComponent')
                json,
          ],
          codec: doc.codec,
          parentName: parentName,
          // A copy of something switched off is switched off too.
          enabled: spec.enabled,
        ),
      );
      for (final id
          in e.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        final child = doc.world.getEntity(id);
        if (child != null) walk(child, e.name);
      }
    }

    for (final root in roots) {
      walk(root, null);
    }
    return out;
  }

  /// Makes [records] again, with names of their own, as one step, and
  /// selects the new roots: the root numbered `n` (in the order the roots
  /// come in [records]) under the parent [placeOf] gives it, at the index it
  /// gives (-1 for last). [nudge] moves pinned copies so they do not sit
  /// exactly on what they were copied from.
  List<Entity> _makeAgain(
    UiScreenDocument doc,
    List<EntitySpec> records, {
    required (Entity, int) Function(int root) placeOf,
    required String label,
    Offset nudge = Offset.zero,
  }) {
    final renamed = <String?, String>{};
    final taken = {for (final e in doc.world.entities) e.name};
    String fresh(String? base) {
      final stem = (base ?? 'Element').replaceFirst(RegExp(r'\d+$'), '');
      var name = stem;
      var n = 2;
      while (taken.contains(name)) {
        name = '$stem${n++}';
      }
      taken.add(name);
      return name;
    }

    final specs = <EntitySpec>[];
    var roots = 0;
    for (final record in records) {
      final name = fresh(record.name);
      renamed[record.name] = name;
      final isRoot = record.parentName == null;
      var json = record.componentsJson;
      final (Entity, int)? place = isRoot ? placeOf(roots++) : null;
      if (place != null) {
        json = _fitSlotTo(doc, json, place.$1, nudge);
      }
      specs.add(
        EntitySpec(
          name: name,
          componentsJson: json,
          codec: doc.codec,
          // A root goes under its parent by id — names need not tell two
          // entities apart; a child under its copied parent, by the name
          // that copy was just given.
          parentId: place?.$1.id,
          parentName: place != null
              ? place.$1.name
              : renamed[record.parentName],
          siblingIndex: place?.$2 ?? -1,
          enabled: record.enabled,
        ),
      );
    }
    final made = <Entity>[];
    doc.history.push(
      CreateEntitiesCommand(
        label: label,
        world: doc.world,
        sceneState: doc.sceneState,
        specs: specs,
        onCreated: (created) {
          made
            ..clear()
            ..addAll(created);
          final roots = [
            for (var i = 0; i < specs.length; i++)
              if (i < created.length && records[i].parentName == null)
                created[i],
          ];
          if (roots.isEmpty) return;
          doc.sceneState.selectEntity(roots.first);
          for (final r in roots.skip(1)) {
            doc.sceneState.toggleMultiSelect(r);
          }
        },
      ),
    );
    return made;
  }

  /// A copied element's slot, made right for its new parent: pinned where a
  /// canvas or a stack pins, in the flow where a row or a column flows.
  List<Map<String, dynamic>> _fitSlotTo(
    UiScreenDocument doc,
    List<Map<String, dynamic>> json,
    Entity parent,
    Offset nudge,
  ) {
    final components = doc.codec.decodeAll(json);
    final slot = components.whereType<UiSlotComponent>().firstOrNull;
    if (slot != null) {
      final pins = UiCreate.placesByAnchor(parent);
      if (pins && slot.mode != UiSlotMode.anchored) {
        slot
          ..mode = UiSlotMode.anchored
          ..anchor = UiAnchor.center
          ..offset = Offset.zero;
      } else if (!pins && slot.mode != UiSlotMode.flow) {
        slot.mode = UiSlotMode.flow;
      }
      if (pins && !slot.anchor.stretchesX && !slot.anchor.stretchesY) {
        slot.offset += nudge;
      }
    }
    return doc.codec.encodeAll(components);
  }

  void duplicateSelection() {
    final doc = _document;
    final originals = editableSelection;
    if (doc == null || originals.isEmpty) return;
    // Each beside its own original, under that one's parent. Made from the
    // last place in a parent to the first, so a copy put in never moves the
    // place the next one is counted from.
    final placed = <({Entity entity, Entity parent, int index})>[];
    for (final e in originals) {
      final parent = _parentOf(doc, e);
      final siblings = parent.getComponent<ChildrenComponent>()?.childIds;
      placed.add((
        entity: e,
        parent: parent,
        index: siblings?.indexOf(e.id) ?? -1,
      ));
    }
    placed.sort((a, b) {
      final byParent = a.parent.id.compareTo(b.parent.id);
      return byParent != 0 ? byParent : b.index.compareTo(a.index);
    });
    _makeAgain(
      doc,
      _recordsOf(doc, [for (final p in placed) p.entity]),
      placeOf: (root) {
        final p = placed[root];
        return (p.parent, p.index < 0 ? -1 : p.index + 1);
      },
      label: originals.length == 1
          ? 'Duplicate ${originals.first.name}'
          : 'Duplicate ${originals.length} elements',
      nudge: const Offset(16, 16),
    );
  }

  static Entity _parentOf(UiScreenDocument doc, Entity e) {
    final id = e.getComponent<ParentComponent>()?.parentId;
    return (id == null ? null : doc.world.getEntity(id)) ?? doc.canvas;
  }

  /// The screen editor's clipboard, shared by every screen it opens.
  static UiClipboard? clipboard;

  void copySelection() {
    final doc = _document;
    final picked = editableSelection;
    if (doc == null || picked.isEmpty) return;
    UiEditOps.clipboard = UiClipboard(_recordsOf(doc, picked));
  }

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  void paste() {
    final doc = _document;
    final copied = UiEditOps.clipboard;
    if (doc == null || copied == null || copied.records.isEmpty) return;
    final parent = UiCreate.parentFor(doc, doc.sceneState.selectedEntity.value);
    _makeAgain(
      doc,
      copied.records,
      placeOf: (_) => (parent, -1),
      label: 'Paste',
      nudge: const Offset(16, 16),
    );
  }

  // ── Moving and sizing ──────────────────────────────────────────────────

  /// Whether a drag can move or size [entity] freely: pinned by anchors.
  /// One in a row or a column goes where the row puts it, and is moved by
  /// reordering instead.
  static bool isPinned(Entity entity) =>
      entity.getComponent<UiSlotComponent>()?.mode == UiSlotMode.anchored;

  /// [value] to a hundredth of a design pixel: what a drag measures back
  /// from the layout carries the transform's rounding (`199.99999999999997`),
  /// which is noise in a file and makes a drag that ended where it began
  /// look like an edit.
  static double _tidy(double value) => (value * 100).roundToDouble() / 100;

  static Offset _tidyOffset(Offset o) => Offset(_tidy(o.dx), _tidy(o.dy));

  static Size _tidySize(Size s) => Size(_tidy(s.width), _tidy(s.height));

  static EdgeInsets _tidyInsets(EdgeInsets e) => EdgeInsets.fromLTRB(
    _tidy(e.left),
    _tidy(e.top),
    _tidy(e.right),
    _tidy(e.bottom),
  );

  /// The slot that would put each of [targets] at its rectangle (design
  /// pixels of the canvas), or leaves one it cannot place alone.
  ///
  /// [from] is where each started (a drag in progress); [keepSize] keeps
  /// each slot's own size along the axes it is not stretched on — a move,
  /// which must not take the size back from the layout.
  Map<Entity, (UiSlotState, UiSlotState)> _placements(
    Map<Entity, Rect> targets, {
    Map<Entity, UiSlotState>? from,
    bool keepSize = false,
  }) {
    final doc = _document;
    final metrics = this.metrics;
    final out = <Entity, (UiSlotState, UiSlotState)>{};
    if (doc == null || metrics == null) return out;
    for (final entry in targets.entries) {
      final entity = entry.key;
      final slot = entity.getComponent<UiSlotComponent>();
      if (slot == null) continue;
      final before = from?[entity] ?? UiSlotState.of(slot);
      final parentId = entity.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : doc.world.getEntity(parentId);
      final content = parent == null ? null : metrics.contentRectOf(parent);
      if (content == null) continue;
      final local = entry.value.shift(-content.topLeft);
      if (before.mode == UiSlotMode.anchored) {
        final fitted = UiGeometry.fit(_slotFrom(before), local, content.size);
        out[entity] = (
          before,
          before.copyWith(
            offset: _tidyOffset(fitted.offset),
            size: keepSize ? before.size : _tidySize(fitted.size),
            margin: _tidyInsets(fitted.margin),
          ),
        );
      } else if (!keepSize) {
        // In the flow only the size is the element's own to change.
        out[entity] = (before, before.copyWith(size: _tidySize(local.size)));
      }
    }
    return out;
  }

  static UiSlotComponent _slotFrom(UiSlotState state) => UiSlotComponent(
    mode: state.mode,
    anchor: state.anchor,
    pivot: state.pivot,
    offset: state.offset,
    size: state.size,
    margin: state.margin,
  );

  /// Puts each of [targets] at its rectangle, as one step labelled [label].
  /// Nothing is recorded when nothing changes. [keepSize]: see
  /// [_placements] — true for a move.
  void placeAt(
    Map<Entity, Rect> targets, {
    required String label,
    bool keepSize = false,
  }) {
    final doc = _document;
    if (doc == null) return;
    final command = UiSlotEditCommand(
      label: label,
      sceneState: doc.sceneState,
      changes: _placements(targets, keepSize: keepSize),
    );
    if (!command.changesSomething) return;
    doc.history.push(command);
  }

  /// Puts each of [targets] at its rectangle *now*, recording nothing: a
  /// drag in progress, measured from [from], where each began. Each move of
  /// it is applied whatever it is — back where it began included — and
  /// [endDrag] records the whole drag as one step, or [cancelDrag] puts it
  /// back.
  void dragTo(
    Map<Entity, Rect> targets, {
    required Map<Entity, UiSlotState> from,
    bool keepSize = false,
  }) {
    final doc = _document;
    if (doc == null) return;
    final changes = _placements(targets, from: from, keepSize: keepSize);
    for (final MapEntry(key: entity, value: (_, after)) in changes.entries) {
      final slot = doc.sceneState
          .liveEntity(entity)
          ?.getComponent<UiSlotComponent>();
      if (slot != null) after.applyTo(slot);
    }
    doc.sceneState.refresh();
  }

  /// Records a drag that ended, from [from] to where its elements are now,
  /// as one step labelled [label]. False when it moved nothing.
  bool endDrag(Map<Entity, UiSlotState> from, {required String label}) {
    final doc = _document;
    if (doc == null) return false;
    final command = UiSlotEditCommand(
      label: label,
      sceneState: doc.sceneState,
      changes: {
        for (final MapEntry(key: entity, value: before) in from.entries)
          if (doc.sceneState.liveEntity(entity)?.getComponent<UiSlotComponent>()
              case final slot?)
            entity: (before, UiSlotState.of(slot)),
      },
    );
    if (!command.changesSomething) return false;
    // Its own step: two drags of one thing are two.
    doc.history
      ..breakMerge()
      ..pushApplied(command);
    doc.sceneState
      ..markDirty()
      ..refresh();
    return true;
  }

  /// Puts what a drag moved back where it was in [from], recording nothing.
  void cancelDrag(Map<Entity, UiSlotState> from) {
    final doc = _document;
    if (doc == null) return;
    for (final MapEntry(key: entity, value: before) in from.entries) {
      final slot = doc.sceneState
          .liveEntity(entity)
          ?.getComponent<UiSlotComponent>();
      if (slot != null) before.applyTo(slot);
    }
    doc.sceneState.refresh();
  }

  /// Moves the pinned elements of the selection by [delta] design pixels —
  /// the arrow keys.
  void nudge(Offset delta) {
    final metrics = this.metrics;
    if (metrics == null) return;
    final targets = <Entity, Rect>{
      for (final e in editableSelection)
        if (isPinned(e))
          if (metrics.designRectOf(e) case final rect?) e: rect.shift(delta),
    };
    placeAt(targets, label: 'Nudge', keepSize: true);
  }

  /// Pins [entity] by [anchor] without moving it on screen.
  void setAnchor(Entity entity, UiAnchor anchor) {
    final doc = _document;
    final metrics = this.metrics;
    final slot = entity.getComponent<UiSlotComponent>();
    if (doc == null || metrics == null || slot == null) return;
    final rect = metrics.designRectOf(entity);
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : doc.world.getEntity(parentId);
    final content = parent == null ? null : metrics.contentRectOf(parent);
    final before = UiSlotState.of(slot);
    var after = before.copyWith(anchor: anchor, mode: UiSlotMode.anchored);
    if (rect != null && content != null) {
      final fitted = UiGeometry.fit(
        _slotFrom(after),
        rect.shift(-content.topLeft),
        content.size,
      );
      after = after.copyWith(
        offset: _tidyOffset(fitted.offset),
        size: _tidySize(fitted.size),
        margin: _tidyInsets(fitted.margin),
      );
    }
    doc.history.breakMerge();
    final command = UiSlotEditCommand(
      label: 'Anchor ${entity.name}',
      sceneState: doc.sceneState,
      changes: {entity: (before, after)},
    );
    if (command.changesSomething) doc.history.push(command);
  }

  /// Lines the selection up by [how]: to one another when several are
  /// selected, to their parent when one is.
  void align(UiAlign how) {
    final doc = _document;
    final metrics = this.metrics;
    if (doc == null || metrics == null) return;
    final picked = [
      for (final e in editableSelection)
        if (isPinned(e)) e,
    ];
    if (picked.isEmpty) return;
    final rects = {for (final e in picked) e: ?metrics.designRectOf(e)};
    Rect? bounds;
    if (rects.length == 1) {
      final e = rects.keys.first;
      final parentId = e.getComponent<ParentComponent>()?.parentId;
      final parent = parentId == null ? null : doc.world.getEntity(parentId);
      bounds = parent == null ? null : metrics.contentRectOf(parent);
    } else {
      for (final r in rects.values) {
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
    }
    if (bounds == null) return;
    final target = bounds;
    doc.history.breakMerge();
    placeAt(
      {
        for (final entry in rects.entries)
          entry.key: switch (how) {
            UiAlign.left => entry.value.translate(
              target.left - entry.value.left,
              0,
            ),
            UiAlign.right => entry.value.translate(
              target.right - entry.value.right,
              0,
            ),
            UiAlign.centerX => entry.value.translate(
              target.center.dx - entry.value.center.dx,
              0,
            ),
            UiAlign.top => entry.value.translate(
              0,
              target.top - entry.value.top,
            ),
            UiAlign.bottom => entry.value.translate(
              0,
              target.bottom - entry.value.bottom,
            ),
            UiAlign.centerY => entry.value.translate(
              0,
              target.center.dy - entry.value.center.dy,
            ),
          },
      },
      label: 'Align',
      keepSize: true,
    );
  }

  /// Spreads three or more pinned elements evenly between the outermost
  /// two, along [horizontal] or down.
  void distribute({required bool horizontal}) {
    final doc = _document;
    final metrics = this.metrics;
    if (doc == null || metrics == null) return;
    final rects = <Entity, Rect>{
      for (final e in editableSelection)
        if (isPinned(e)) e: ?metrics.designRectOf(e),
    };
    if (rects.length < 3) return;
    final ordered = rects.entries.toList()
      ..sort(
        (a, b) => horizontal
            ? a.value.left.compareTo(b.value.left)
            : a.value.top.compareTo(b.value.top),
      );
    double start(Rect r) => horizontal ? r.left : r.top;
    double extent(Rect r) => horizontal ? r.width : r.height;
    final first = ordered.first.value;
    final last = ordered.last.value;
    final total = ordered.fold<double>(0, (sum, e) => sum + extent(e.value));
    final span = (start(last) + extent(last)) - start(first);
    final gap = (span - total) / (ordered.length - 1);
    var at = start(first);
    final targets = <Entity, Rect>{};
    for (final entry in ordered) {
      final r = entry.value;
      targets[entry.key] = horizontal
          ? r.translate(at - r.left, 0)
          : r.translate(0, at - r.top);
      at += extent(r) + gap;
    }
    doc.history.breakMerge();
    placeAt(targets, label: 'Distribute', keepSize: true);
  }

  // ── The tree ───────────────────────────────────────────────────────────

  /// Moves [entity] to [index] among its siblings.
  void reorder(Entity entity, int index) {
    final doc = _document;
    if (doc == null || entity.id == doc.canvas.id) return;
    doc.history.push(
      ReorderCommand(
        label: 'Reorder ${entity.name}',
        world: doc.world,
        sceneState: doc.sceneState,
        entity: entity,
        index: index,
      ),
    );
  }

  /// Moves [entities] under [parent], at [index] among its children, as
  /// one step — each changing how it sits to suit its new parent.
  void reparent(List<Entity> entities, Entity parent, {int? index}) {
    final doc = _document;
    if (doc == null) return;
    final moving = [
      for (final e in entities)
        if (e.id != doc.canvas.id &&
            !isSelfOrDescendant(parent, e, world: doc.world))
          e,
    ];
    if (moving.isEmpty) return;
    final pins = UiCreate.placesByAnchor(parent);
    final slots = <Entity, (UiSlotState, UiSlotState)>{};
    for (final e in moving) {
      final slot = e.getComponent<UiSlotComponent>();
      if (slot == null) continue;
      final before = UiSlotState.of(slot);
      if (pins && before.mode != UiSlotMode.anchored) {
        slots[e] = (
          before,
          before.copyWith(
            mode: UiSlotMode.anchored,
            anchor: UiAnchor.center,
            offset: Offset.zero,
          ),
        );
      } else if (!pins && before.mode != UiSlotMode.flow) {
        slots[e] = (before, before.copyWith(mode: UiSlotMode.flow));
      }
    }
    doc.history.push(
      CompositeCommand(
        label: moving.length == 1
            ? 'Move ${moving.first.name} into ${parent.name}'
            : 'Move ${moving.length} elements into ${parent.name}',
        commands: [
          ReparentCommand(
            label: 'Move',
            world: doc.world,
            sceneState: doc.sceneState,
            entities: moving,
            parent: parent,
            index: index,
          ),
          if (slots.isNotEmpty)
            UiSlotEditCommand(
              label: 'Fit',
              sceneState: doc.sceneState,
              changes: slots,
            ),
        ],
      ),
    );
  }

  /// Renames [entity]. The canvas is the screen: renaming it renames the
  /// screen, its file and its place on the list. False when the name is
  /// empty or taken.
  bool rename(Entity entity, String name) {
    final doc = _document;
    if (doc == null) return false;
    if (entity.id == doc.canvas.id) return renameScreen(doc.path, name);
    if (!RenameCommand.isAvailable(name, entity, world: doc.world)) {
      return false;
    }
    doc.history.push(
      RenameCommand(sceneState: doc.sceneState, entity: entity, name: name),
    );
    return true;
  }

  /// Shows or hides [entity] — saved, and what the game starts with.
  void setVisible(Entity entity, bool visible) {
    final doc = _document;
    final slot = entity.getComponent<UiSlotComponent>();
    if (doc == null || slot == null || slot.visible == visible) return;
    doc.history.breakMerge();
    doc.history.push(
      ComponentFieldCommand(
        label: visible ? 'Show ${entity.name}' : 'Hide ${entity.name}',
        component: slot,
        write: (c, v) => (c as UiSlotComponent).visible = v as bool,
        before: slot.visible,
        after: visible,
        sceneState: doc.sceneState,
        entity: entity,
      ),
    );
  }

  /// Switches [entity] on or off — its saved Enabled flag. One switched
  /// off is not drawn and takes no room; the game has it, and can switch it
  /// on. The canvas is the screen and stays on.
  void setEnabled(Entity entity, bool enabled) {
    final doc = _document;
    if (doc == null || entity.id == doc.canvas.id) return;
    if (entity.isActive == enabled) return;
    doc.history.breakMerge();
    doc.history.push(
      SetEnabledCommand(
        sceneState: doc.sceneState,
        entity: entity,
        enabled: enabled,
      ),
    );
  }
}
