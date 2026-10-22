/// The open screen's tree: what is inside what, in the order it is drawn.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/screen/ui_slot_component.dart';
import '../canvas/ui_canvas_view.dart';
import '../create/ui_create.dart';
import '../document/ui_screen_document.dart';
import '../session/ui_edit_ops.dart';
import '../session/ui_editor_session.dart';

/// The screen's elements as a tree. Click selects at once (Shift or Ctrl
/// adds), a double click renames, the eye shows or hides — saved — and a
/// hold drags a row to another place or into another container.
class UiHierarchyPanel extends StatefulWidget {
  const UiHierarchyPanel({super.key, required this.session});

  final UiEditorSession session;

  @override
  State<UiHierarchyPanel> createState() => UiHierarchyPanelState();
}

class UiHierarchyPanelState extends State<UiHierarchyPanel> {
  final Set<EntityId> _shut = {};
  EntityId? _renaming;
  String? _renameError;
  EntityId? _lastClicked;
  Duration _lastClickAt = Duration.zero;
  (EntityId, DropZone)? _dropAt;

  UiEditorSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder<UiScreenDocument?>(
      signal: session.document,
      builder: (context, doc, _) {
        if (doc == null) return const SizedBox.shrink();
        return SignalConsumer(
          signals: [
            doc.sceneState.revision,
            doc.sceneState.selectedEntity,
            doc.sceneState.multiSelectedIds,
            doc.history.revision,
          ],
          builder: (context, _) => _tree(doc),
        );
      },
    );
  }

  Widget _tree(UiScreenDocument doc) {
    final expanded = {
      for (final e in doc.world.entities)
        if (!_shut.contains(e.id)) e.id,
    };
    final tree = SceneTreeModel.build(
      world: doc.world,
      rootOrder: [doc.canvas.id],
      expanded: expanded,
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: tree.rows.length,
      itemExtent: kSceneTreeRowTileHeight,
      itemBuilder: (context, i) => _row(doc, tree.rows[i]),
    );
  }

  Widget _row(UiScreenDocument doc, TreeRow row) {
    final entity = row.entity;
    final state = doc.sceneState;
    final slot = entity.getComponent<UiSlotComponent>();
    final isCanvas = entity.id == doc.canvas.id;
    final zone = _dropAt?.$1 == entity.id ? _dropAt!.$2 : null;
    final tile = SceneTreeRowTile(
      row: row,
      isSelected: state.selectedEntity.value?.id == entity.id,
      isMultiSelected:
          state.isInMultiSelection(entity.id) &&
          state.selectedEntity.value?.id != entity.id,
      icon: uiIconFor(entity),
      isHidden: slot != null && !slot.visible,
      onToggleHidden: slot == null
          ? null
          : () => session.setVisible(entity, !slot.visible),
      onToggleExpand: ({required bool subtree}) => setState(() {
        if (!_shut.remove(entity.id)) _shut.add(entity.id);
      }),
      isRenaming: _renaming == entity.id,
      renameError: _renaming == entity.id ? _renameError : null,
      onCommitRename: (name) => _commitRename(entity, name),
      onCancelRename: () => setState(() {
        _renaming = null;
        _renameError = null;
      }),
      onShowMenu: (at) => _menu(doc, entity, at),
      dropZone: zone,
    );

    Widget child = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _pressed(doc, entity, e),
      child: tile,
    );
    if (!isCanvas) {
      final dragged = state.isInMultiSelection(entity.id)
          ? session.editableSelection
          : [entity];
      child = LongPressDraggable<List<Entity>>(
        // A click selects; a hold drags. A drag that began on the first
        // pixel of movement ate clicks and flashed a label at the pointer.
        delay: const Duration(milliseconds: 250),
        data: dragged,
        feedback: _DragLabel(
          text: dragged.length == 1
              ? dragged.first.name ?? 'Element'
              : '${dragged.length} elements',
        ),
        child: child,
      );
    }
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => _canDrop(doc, details.data, entity),
      onMove: (details) {
        final zoneNow = isCanvas
            ? DropZone.onto
            : dropZoneFor(
                _localDy(details.offset, entity),
                kSceneTreeRowTileHeight,
              );
        if (_dropAt != (entity.id, zoneNow)) {
          setState(() => _dropAt = (entity.id, zoneNow));
        }
      },
      onLeave: (_) => setState(() => _dropAt = null),
      onAcceptWithDetails: (details) {
        final zoneNow = _dropAt?.$2 ?? DropZone.onto;
        setState(() => _dropAt = null);
        _drop(doc, details.data, entity, zoneNow);
      },
      builder: (context, _, _) => KeyedSubtree(
        key: _rowKeys.putIfAbsent(entity.id, GlobalKey.new),
        child: child,
      ),
    );
  }

  final Map<EntityId, GlobalKey> _rowKeys = {};

  double _localDy(Offset global, Entity entity) {
    final box =
        _rowKeys[entity.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return kSceneTreeRowTileHeight / 2;
    return box.globalToLocal(global).dy;
  }

  bool _canDrop(UiScreenDocument doc, Object? data, Entity onto) {
    if (data is UiPaletteDrag) return true;
    if (data is! List<Entity>) return false;
    return data.every(
      (e) => e.id != onto.id && !isSelfOrDescendant(onto, e, world: doc.world),
    );
  }

  void _drop(UiScreenDocument doc, Object data, Entity onto, DropZone zone) {
    final isCanvas = onto.id == doc.canvas.id;
    Entity parent;
    int? index;
    if (zone == DropZone.onto || isCanvas) {
      parent = UiCreate.isContainer(onto) ? onto : _parentOf(doc, onto);
      if (!identical(parent, onto)) index = _indexOf(doc, onto, parent) + 1;
    } else {
      parent = _parentOf(doc, onto);
      final moving = data is List<Entity>
          ? {for (final e in data) e.id}
          : <EntityId>{};
      final siblings = [
        for (final id
            in parent.getComponent<ChildrenComponent>()?.childIds ??
                const <EntityId>[])
          if (!moving.contains(id)) id,
      ];
      final at = siblings.indexOf(onto.id);
      index = zone == DropZone.below ? at + 1 : at;
    }
    doc.history.breakMerge();
    if (data is UiPaletteDrag) {
      UiCreate.create(doc, data.kind, parent: parent, index: index ?? -1);
    } else if (data is List<Entity>) {
      session.reparent(data, parent, index: index);
    }
  }

  Entity _parentOf(UiScreenDocument doc, Entity e) {
    final id = e.getComponent<ParentComponent>()?.parentId;
    return (id == null ? null : doc.world.getEntity(id)) ?? doc.canvas;
  }

  int _indexOf(UiScreenDocument doc, Entity e, Entity parent) =>
      parent.getComponent<ChildrenComponent>()?.childIds.indexOf(e.id) ?? -1;

  void _pressed(UiScreenDocument doc, Entity entity, PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final state = doc.sceneState;
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed || keys.isControlPressed) {
      state.toggleMultiSelect(entity);
      return;
    }
    // Timed from the events, not the wall clock: a test advances one and
    // not the other.
    final again =
        _lastClicked == entity.id &&
        e.timeStamp - _lastClickAt < const Duration(milliseconds: 450);
    _lastClicked = entity.id;
    _lastClickAt = e.timeStamp;
    state.selectEntity(entity);
    if (again) {
      setState(() {
        _renaming = entity.id;
        _renameError = null;
      });
    }
  }

  void _commitRename(Entity entity, String name) {
    if (name.trim() == entity.name) {
      setState(() => _renaming = null);
      return;
    }
    final ok = session.rename(entity, name);
    setState(() {
      if (ok) {
        _renaming = null;
        _renameError = null;
      } else {
        _renameError = name.trim().isEmpty
            ? 'A name is needed'
            : 'Something else is called that';
      }
    });
  }

  Future<void> _menu(UiScreenDocument doc, Entity entity, Offset at) async {
    final state = doc.sceneState;
    if (!state.isInMultiSelection(entity.id)) state.selectEntity(entity);
    final isCanvas = entity.id == doc.canvas.id;
    final slot = entity.getComponent<UiSlotComponent>();
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem(
        'rename',
        'Rename',
        icon: Icons.edit_outlined,
        shortcut: 'F2',
      ),
      if (!isCanvas) ...[
        editorMenuItem(
          'cut',
          'Cut',
          icon: Icons.content_cut,
          shortcut: 'Ctrl+X',
        ),
        editorMenuItem('copy', 'Copy', icon: Icons.copy, shortcut: 'Ctrl+C'),
      ],
      editorMenuItem(
        'paste',
        'Paste',
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        enabled: UiEditOps.clipboard != null,
      ),
      if (!isCanvas) ...[
        editorMenuItem(
          'duplicate',
          'Duplicate',
          icon: Icons.control_point_duplicate,
          shortcut: 'Ctrl+D',
        ),
        editorMenuItem(
          'delete',
          'Delete',
          icon: Icons.delete_outline,
          shortcut: 'Del',
        ),
      ],
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
      case 'rename':
        setState(() => _renaming = entity.id);
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
      case 'visible':
        if (slot != null) session.setVisible(entity, !slot.visible);
    }
  }

  /// Starts renaming the selected row — F2.
  void renameSelected() {
    final doc = session.document.value;
    final selected = doc?.sceneState.selectedEntity.value;
    if (selected != null) setState(() => _renaming = selected.id);
  }
}

class _DragLabel extends StatelessWidget {
  const _DragLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EditorTheme.panelRaised,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EditorTheme.accent),
      ),
      child: Text(
        text,
        style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      ),
    ),
  );
}
