/// The Inspector tab: everything about what is selected on the screen.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/screen/ui_slot_component.dart';
import '../create/ui_create.dart';
import '../document/ui_screen_document.dart';
import '../session/ui_edit_ops.dart';
import '../session/ui_editor_session.dart';

/// The selected element's components — every field an undo step in the
/// screen's own history, never the level's. With nothing selected, the
/// screen's own settings; with several, how to line them up.
class UiInspectorPanel extends StatelessWidget {
  const UiInspectorPanel({
    super.key,
    required this.session,
    required this.scope,
  });

  final UiEditorSession session;
  final EditorScope scope;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder<UiScreenDocument?>(
      signal: session.document,
      builder: (context, doc, _) {
        if (doc == null) return const SizedBox.shrink();
        return SignalConsumer(
          signals: [
            doc.sceneState.selectedEntity,
            doc.sceneState.multiSelectedIds,
            doc.sceneState.revision,
          ],
          builder: (context, _) {
            final picked = session.selection;
            if (picked.length > 1) return _several(picked.length);
            final entity = picked.firstOrNull ?? doc.canvas;
            return _one(doc, entity);
          },
        );
      },
    );
  }

  Widget _one(UiScreenDocument doc, Entity entity) {
    final isCanvas = entity.id == doc.canvas.id;
    final slot = entity.getComponent<UiSlotComponent>();
    final sections = buildComponentSections(
      entity: entity,
      sceneState: doc.sceneState,
      scope: scope,
      history: doc.history,
      world: doc.world,
      // The hierarchy is where a screen's tree is seen and changed; a link
      // card here only offered to cut it.
      hidden: const {ParentComponent, ChildrenComponent},
    );
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _Title(
          icon: uiIconFor(entity) ?? Icons.crop_square,
          name: entity.name ?? '',
          subtitle: isCanvas
              ? 'The screen — its name is how the game opens it'
              : null,
          onRename: (name) => session.rename(entity, name),
        ),
        const SizedBox(height: 8),
        if (slot != null && slot.mode == UiSlotMode.anchored) ...[
          _PinTo(
            current: slot.anchor,
            onPick: (anchor) => session.setAnchor(entity, anchor),
          ),
          const SizedBox(height: 8),
        ],
        for (final s in sections) ...[s, const SizedBox(height: 8)],
        AddComponentPicker(
          entity: entity,
          sceneState: doc.sceneState,
          scope: scope,
          history: doc.history,
        ),
      ],
    );
  }

  Widget _several(int count) => ListView(
    padding: const EdgeInsets.all(10),
    children: [
      Text(
        '$count elements selected',
        style: TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: EditorMetrics.fontTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Pinned ones line up with each other; ones in a row or a column go '
        'where it puts them.',
        style: TextStyle(
          color: EditorTheme.textMuted,
          fontSize: EditorMetrics.fontLabel,
        ),
      ),
      const SizedBox(height: 10),
      const EditorSectionHeader('Align'),
      Wrap(
        spacing: 2,
        children: [
          for (final (how, icon, tip) in const [
            (UiAlign.left, Icons.align_horizontal_left, 'Left edges'),
            (UiAlign.centerX, Icons.align_horizontal_center, 'Centres, across'),
            (UiAlign.right, Icons.align_horizontal_right, 'Right edges'),
            (UiAlign.top, Icons.align_vertical_top, 'Top edges'),
            (UiAlign.centerY, Icons.align_vertical_center, 'Centres, down'),
            (UiAlign.bottom, Icons.align_vertical_bottom, 'Bottom edges'),
          ])
            EditorIconButton(
              icon: icon,
              tooltip: tip,
              onTap: () => session.align(how),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const EditorSectionHeader('Spread evenly'),
      Wrap(
        spacing: 2,
        children: [
          EditorIconButton(
            icon: Icons.horizontal_distribute,
            tooltip: 'Across — three or more',
            onTap: count >= 3
                ? () => session.distribute(horizontal: true)
                : null,
          ),
          EditorIconButton(
            icon: Icons.vertical_distribute,
            tooltip: 'Down — three or more',
            onTap: count >= 3
                ? () => session.distribute(horizontal: false)
                : null,
          ),
        ],
      ),
    ],
  );
}

class _Title extends StatelessWidget {
  const _Title({
    required this.icon,
    required this.name,
    required this.onRename,
    this.subtitle,
  });

  final IconData icon;
  final String name;
  final String? subtitle;
  final bool Function(String name) onRename;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            icon,
            size: EditorMetrics.iconMd,
            color: EditorTheme.primaryMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CommitTextField(
              key: ValueKey(name),
              value: name,
              onCommit: (value) {
                if (value.trim() != name) onRename(value);
              },
            ),
          ),
        ],
      ),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 20),
          child: Text(
            subtitle!,
            style: TextStyle(
              color: EditorTheme.textMuted,
              fontSize: EditorMetrics.fontCaption,
            ),
          ),
        ),
    ],
  );
}

/// Nine corners and edges, and the stretches: where to pin it — without it
/// moving on screen, which is what changing an anchor used to do.
class _PinTo extends StatelessWidget {
  const _PinTo({required this.current, required this.onPick});

  final UiAnchor current;
  final ValueChanged<UiAnchor> onPick;

  @override
  Widget build(BuildContext context) {
    Widget cell(UiAnchor anchor, String tip) {
      final on = anchor == current;
      return Tooltip(
        message: tip,
        waitDuration: EditorMetrics.tooltipWait,
        child: InkWell(
          onTap: () => onPick(anchor),
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: on ? EditorTheme.accent : EditorTheme.surfaceBg,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: EditorTheme.border),
            ),
            child: CustomPaint(painter: _AnchorGlyph(anchor, on)),
          ),
        ),
      );
    }

    // On the same columns as the rows in the cards below it: in by a card's
    // stripe and padding, the grid where their boxes start.
    return Padding(
      padding: const EdgeInsets.only(left: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: InspectorField.labelWidth,
            height: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Pin to', style: InspectorField.labelStyle),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  cell(UiAnchor.topLeft, 'Top left'),
                  cell(UiAnchor.topCenter, 'Top'),
                  cell(UiAnchor.topRight, 'Top right'),
                  cell(UiAnchor.stretchTop, 'Across the top'),
                ],
              ),
              Row(
                children: [
                  cell(UiAnchor.centerLeft, 'Left'),
                  cell(UiAnchor.center, 'Middle'),
                  cell(UiAnchor.centerRight, 'Right'),
                  cell(UiAnchor.stretch, 'Filling it'),
                ],
              ),
              Row(
                children: [
                  cell(UiAnchor.bottomLeft, 'Bottom left'),
                  cell(UiAnchor.bottomCenter, 'Bottom'),
                  cell(UiAnchor.bottomRight, 'Bottom right'),
                  cell(UiAnchor.stretchBottom, 'Across the bottom'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnchorGlyph extends CustomPainter {
  _AnchorGlyph(this.anchor, this.on);

  final UiAnchor anchor;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final box = (Offset.zero & size).deflate(5);
    final paint = Paint()
      ..color = on ? Colors.white : EditorTheme.textMuted
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(box, paint..color = paint.color.withValues(alpha: 0.35));
    final min = Offset(
      box.left + box.width * anchor.min.dx,
      box.top + box.height * anchor.min.dy,
    );
    final max = Offset(
      box.left + box.width * anchor.max.dx,
      box.top + box.height * anchor.max.dy,
    );
    final solid = Paint()
      ..color = on ? Colors.white : EditorTheme.textSecondary;
    if (min == max) {
      canvas.drawCircle(min, 2.2, solid);
    } else {
      canvas.drawRect(Rect.fromPoints(min, max).inflate(1), solid);
    }
  }

  @override
  bool shouldRepaint(_AnchorGlyph old) => old.anchor != anchor || old.on != on;
}
