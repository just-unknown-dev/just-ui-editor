/// Undoable changes to where things sit.
library;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/screen/ui_slot_component.dart';

/// Everything about where an element sits that a drag can change.
class UiSlotState {
  const UiSlotState({
    required this.mode,
    required this.anchor,
    required this.pivot,
    required this.offset,
    required this.size,
    required this.margin,
  });

  factory UiSlotState.of(UiSlotComponent slot) => UiSlotState(
    mode: slot.mode,
    anchor: slot.anchor,
    pivot: slot.pivot,
    offset: slot.offset,
    size: slot.size,
    margin: slot.margin,
  );

  final UiSlotMode mode;
  final UiAnchor anchor;
  final Offset pivot;
  final Offset offset;
  final Size size;
  final EdgeInsets margin;

  UiSlotState copyWith({
    UiSlotMode? mode,
    UiAnchor? anchor,
    Offset? pivot,
    Offset? offset,
    Size? size,
    EdgeInsets? margin,
  }) => UiSlotState(
    mode: mode ?? this.mode,
    anchor: anchor ?? this.anchor,
    pivot: pivot ?? this.pivot,
    offset: offset ?? this.offset,
    size: size ?? this.size,
    margin: margin ?? this.margin,
  );

  void applyTo(UiSlotComponent slot) {
    slot
      ..mode = mode
      ..anchor = anchor
      ..pivot = pivot
      ..offset = offset
      ..size = size
      ..margin = margin;
  }

  @override
  bool operator ==(Object other) =>
      other is UiSlotState &&
      other.mode == mode &&
      other.anchor == anchor &&
      other.pivot == pivot &&
      other.offset == offset &&
      other.size == size &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(mode, anchor, pivot, offset, size, margin);
}

/// Sets the slots of one or more elements, all at once.
///
/// Keyed by entity, and the slot written is the one that entity has *when
/// the command runs*: an undone delete, or a create undone and redone,
/// makes the element again with a slot of its own, and a move recorded
/// before that still reaches it (see `EditorSceneState.liveEntity`).
///
/// A drag records one of these when it ends (`EditorHistory.pushApplied`);
/// arrow-key nudges push one per press, and consecutive ones for the same
/// elements with the same label merge.
class UiSlotEditCommand extends EditorCommand {
  UiSlotEditCommand({
    required this.label,
    required this.sceneState,
    required Map<Entity, (UiSlotState, UiSlotState)> changes,
  }) : _changes = Map.of(changes);

  @override
  final String label;

  final EditorSceneState sceneState;

  final Map<Entity, (UiSlotState, UiSlotState)> _changes;

  /// Whether this changes anything at all — a click that moved nothing is
  /// not pushed.
  bool get changesSomething =>
      _changes.values.any((change) => change.$1 != change.$2);

  /// The slot [entity] has now, as it was rebuilt if it was.
  UiSlotComponent? _slotOf(Entity entity) =>
      sceneState.liveEntity(entity)?.getComponent<UiSlotComponent>();

  void _apply(UiSlotState Function((UiSlotState, UiSlotState) change) pick) {
    for (final entry in _changes.entries) {
      final slot = _slotOf(entry.key);
      if (slot != null) pick(entry.value).applyTo(slot);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void redo() => _apply((change) => change.$2);

  @override
  void undo() => _apply((change) => change.$1);

  /// The ids of what this moves, as each is now.
  Set<EntityId> get _ids => {
    for (final e in _changes.keys) sceneState.liveEntity(e)?.id ?? e.id,
  };

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! UiSlotEditCommand || next.label != label) return false;
    final mine = _ids;
    final theirs = next._ids;
    if (mine.length != theirs.length || !mine.containsAll(theirs)) {
      return false;
    }
    final byId = {
      for (final e in _changes.keys) sceneState.liveEntity(e)?.id ?? e.id: e,
    };
    for (final entry in next._changes.entries) {
      final id = sceneState.liveEntity(entry.key)?.id ?? entry.key.id;
      final key = byId[id]!;
      _changes[key] = (_changes[key]!.$1, entry.value.$2);
    }
    return true;
  }
}

/// The slots of [entities] as they are now, by entity; an entity with no
/// slot is left out.
Map<Entity, UiSlotState> slotsOf(Iterable<Entity> entities) => {
  for (final e in entities)
    if (e.getComponent<UiSlotComponent>() case final slot?)
      e: UiSlotState.of(slot),
};
