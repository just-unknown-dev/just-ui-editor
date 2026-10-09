/// Undoable changes to where things sit.
library;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

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
/// A drag pushes one of these per pointer move; consecutive ones for the
/// same elements with the same label merge, so a drag is one step — and
/// the history's `breakMerge` at the start of each drag keeps two drags
/// two steps.
class UiSlotEditCommand extends EditorCommand {
  UiSlotEditCommand({
    required this.label,
    required this.sceneState,
    required Map<UiSlotComponent, (UiSlotState, UiSlotState)> changes,
  }) : _changes = Map.of(changes);

  @override
  final String label;

  final EditorSceneState sceneState;

  final Map<UiSlotComponent, (UiSlotState, UiSlotState)> _changes;

  /// Whether this changes anything at all — a click that moved nothing is
  /// not pushed.
  bool get changesSomething =>
      _changes.values.any((change) => change.$1 != change.$2);

  @override
  void redo() {
    for (final entry in _changes.entries) {
      entry.value.$2.applyTo(entry.key);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  void undo() {
    for (final entry in _changes.entries) {
      entry.value.$1.applyTo(entry.key);
    }
    sceneState
      ..markDirty()
      ..refresh();
  }

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! UiSlotEditCommand || next.label != label) return false;
    if (next._changes.keys
            .toSet()
            .difference(_changes.keys.toSet())
            .isNotEmpty ||
        _changes.length != next._changes.length) {
      return false;
    }
    for (final entry in next._changes.entries) {
      final mine = _changes[entry.key]!;
      _changes[entry.key] = (mine.$1, entry.value.$2);
    }
    return true;
  }
}

/// The slots of [entities], or none for an entity with no slot.
Map<UiSlotComponent, UiSlotState> slotsOf(Iterable<Entity> entities) {
  final out = <UiSlotComponent, UiSlotState>{};
  for (final e in entities) {
    final slot = e.getComponent<UiSlotComponent>();
    if (slot != null) out[slot] = UiSlotState.of(slot);
  }
  return out;
}
