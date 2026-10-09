/// What can be put on a screen: the built-in elements and the game's own.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_signals/just_signals.dart';

import '../canvas/ui_canvas_view.dart';
import '../create/ui_create.dart';
import '../document/ui_screen_document.dart';
import '../session/ui_editor_session.dart';
import 'screens_panel.dart';

/// Tiles to click — which adds one where the selection says — or to drag
/// onto the screen, or onto a row of the tree.
class UiWidgetPalette extends StatefulWidget {
  const UiWidgetPalette({super.key, required this.session});

  final UiEditorSession session;

  @override
  State<UiWidgetPalette> createState() => _UiWidgetPaletteState();
}

class _UiWidgetPaletteState extends State<UiWidgetPalette> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final o in UiCreateOptions.all)
        if (_filter.isEmpty ||
            o.label.toLowerCase().contains(_filter) ||
            o.group.toLowerCase().contains(_filter))
          o,
    ];
    final groups = <String, List<UiCreateOption>>{};
    for (final o in options) {
      (groups[o.group] ??= []).add(o);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UiPanelHeader(title: 'WIDGETS'),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: EditorSearchField(
            hint: 'Find a widget',
            onChanged: (text) =>
                setState(() => _filter = text.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: SignalBuilder<UiScreenDocument?>(
            signal: widget.session.document,
            builder: (context, doc, _) => LayoutBuilder(
              builder: (context, box) {
                // As many tiles to a row as fit, sharing the whole width,
                // so the grid's edges are the search field's.
                const gap = 4.0;
                final width = box.maxWidth - 20;
                final perRow = ((width + gap) / (_Tile.minWidth + gap))
                    .floor()
                    .clamp(1, 8);
                final tile = (width - gap * (perRow - 1)) / perRow;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: EditorTheme.textMuted,
                            fontSize: EditorMetrics.fontCaption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final option in entry.value)
                            _Tile(option: option, document: doc, width: tile),
                        ],
                      ),
                    ],
                    if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Nothing called that.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: EditorTheme.textMuted,
                            fontSize: EditorMetrics.fontLabel,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.option,
    required this.document,
    required this.width,
  });

  final UiCreateOption option;
  final UiScreenDocument? document;
  final double width;

  /// The narrowest a tile gets before a row holds one fewer.
  static const double minWidth = 70;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: width,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(option.icon, size: 16, color: EditorTheme.primaryMuted),
          const SizedBox(height: 4),
          Text(
            option.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: EditorMetrics.fontCaption,
            ),
          ),
        ],
      ),
    );
    final doc = document;
    return Tooltip(
      message: option.description.isEmpty
          ? option.label
          : '${option.label} — ${option.description}\nClick to add, or drag '
                'onto the screen.',
      waitDuration: EditorMetrics.tooltipWait,
      child: Draggable<UiPaletteDrag>(
        data: UiPaletteDrag(option.id),
        feedback: Opacity(
          opacity: 0.85,
          child: Material(color: Colors.transparent, child: tile),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tile),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
            onTap: doc == null
                ? null
                : () {
                    doc.history.breakMerge();
                    UiCreate.create(doc, option.id);
                  },
            child: tile,
          ),
        ),
      ),
    );
  }
}
