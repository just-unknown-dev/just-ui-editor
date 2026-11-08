/// A small caption over a panel.
library;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:meta/meta.dart';

/// A small caption over a panel, with buttons at its right.
@internal
class UiPanelHeader extends StatelessWidget {
  const UiPanelHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.height = 28,
  });

  final String title;
  final List<Widget> actions;

  /// 28 for a section; the column's first header matches the toolbar's
  /// height instead ([UiCanvasToolbar.height]), so the three columns start
  /// on one line.
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.only(left: 10, right: 2),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: EditorMetrics.fontLabel,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...actions,
      ],
    ),
  );
}
