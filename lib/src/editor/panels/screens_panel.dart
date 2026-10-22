/// The game's screens: which there are, which one is open, which show from
/// the start.
library;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../canvas/ui_canvas_bars.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import '../document/ui_screen_document.dart';
import '../session/ui_editor_session.dart';

/// One row per screen file. The game's list (`screens.json`) decides what
/// the game loads: a file not on it is shown faded, with a way to add it.
class UiScreensPanel extends StatelessWidget {
  const UiScreensPanel({
    super.key,
    required this.session,
    required this.onOpen,
    required this.onNew,
  });

  final UiEditorSession session;

  /// Opens a screen — asking about unsaved work first.
  final void Function(String path) onOpen;

  /// Makes a new screen: a menu (`isScreen`) or a layer that stays (a HUD).
  final void Function({required bool isScreen}) onNew;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [session.files, session.manifest, session.document],
      builder: (context, _) {
        final files = session.files.value;
        final list = session.manifest.value;
        final open = session.document.value;
        // As tall as its rows, up to what the column allows.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiPanelHeader(
              title: 'SCREENS',
              height: UiCanvasToolbar.height,
              actions: [
                Builder(
                  builder: (context) => EditorIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'New screen',
                    onTap: () => _newMenu(context),
                  ),
                ),
              ],
            ),
            Flexible(
              child: files.isEmpty
                  ? EditorEmptyState(
                      icon: Icons.web_asset_outlined,
                      title: 'No screens yet',
                      hint: 'A HUD, a pause menu: each screen is a file.',
                      actionLabel: 'New screen',
                      actionIcon: Icons.add,
                      onAction: () => onNew(isScreen: true),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final path in files)
                          _ScreenRow(
                            path: path,
                            entry: list.entryFor(path),
                            open: open?.path == path ? open : null,
                            session: session,
                            onOpen: () => onOpen(path),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _newMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final chosen = await showEditorMenu<bool>(context, at, [
      editorMenuItem(
        true,
        'Screen — opened and closed',
        icon: Icons.web_asset_outlined,
      ),
      editorMenuItem(
        false,
        'Layer — always there, like a HUD',
        icon: Icons.web_asset,
      ),
    ]);
    if (chosen != null) onNew(isScreen: chosen);
  }
}

class _ScreenRow extends StatelessWidget {
  const _ScreenRow({
    required this.path,
    required this.entry,
    required this.open,
    required this.session,
    required this.onOpen,
  });

  final String path;
  final UiScreenEntry? entry;
  final UiScreenDocument? open;
  final UiEditorSession session;
  final VoidCallback onOpen;

  String get _label => path.split('/').last.replaceAll('.ui.json', '');

  @override
  Widget build(BuildContext context) {
    final listed = entry != null;
    final isOpen = open != null;
    final row = InkWell(
      onTap: onOpen,
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: Container(
        height: 26,
        color: isOpen ? EditorTheme.selectionBg : null,
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: Row(
          children: [
            Icon(
              Icons.web_asset_outlined,
              size: EditorMetrics.iconMd,
              color: listed ? EditorTheme.primaryMuted : EditorTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                open?.name ?? session.nameOf(path) ?? _label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: listed
                      ? EditorTheme.textPrimary
                      : EditorTheme.textMuted,
                  fontSize: EditorMetrics.fontBody,
                  fontWeight: isOpen ? FontWeight.w600 : FontWeight.normal,
                  fontStyle: listed ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
            if (open case final doc?)
              SignalBuilder<bool>(
                signal: doc.dirty,
                builder: (context, dirty, _) => dirty
                    ? Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: EditorTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            if (listed)
              EditorIconButton(
                icon: entry!.startOpen
                    ? Icons.play_circle_fill_rounded
                    : Icons.play_circle_outline_rounded,
                tooltip: entry!.startOpen
                    ? 'Shows from the first frame — click to wait until opened'
                    : 'Waits to be opened — click to show from the first frame',
                isActive: entry!.startOpen,
                iconSize: 13,
                onTap: () => session.setStartOpen(path, !entry!.startOpen),
              )
            else
              EditorIconButton(
                icon: Icons.playlist_add_rounded,
                tooltip: 'Not in the game — add it to the list',
                iconSize: 13,
                onTap: () => session.setListed(path, true),
              ),
          ],
        ),
      ),
    );
    return Tooltip(
      message: listed ? path : '$path — not in the game\'s list',
      waitDuration: EditorMetrics.tooltipWait,
      child: row,
    );
  }

  Future<void> _menu(BuildContext context, Offset at) async {
    final listed = entry != null;
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('open', 'Open', icon: Icons.open_in_new),
      editorMenuItem('rename', 'Rename…', icon: Icons.edit_outlined),
      editorMenuItem(
        'duplicate',
        'Duplicate',
        icon: Icons.control_point_duplicate,
      ),
      editorMenuDivider(),
      editorMenuItem(
        'list',
        listed ? 'Take off the game\'s list' : 'Add to the game\'s list',
        icon: listed ? Icons.playlist_remove : Icons.playlist_add,
      ),
      editorMenuItem(
        'delete',
        'Delete…',
        icon: Icons.delete_outline,
        color: EditorTheme.error,
      ),
    ]);
    if (chosen == null || !context.mounted) return;
    switch (chosen) {
      case 'open':
        onOpen();
      case 'rename':
        final name = await promptForName(
          context,
          'Rename screen',
          open?.name ?? session.nameOf(path) ?? _label,
        );
        if (name == null || !context.mounted) break;
        if (!session.renameScreen(path, name)) {
          await showDialog<void>(
            context: context,
            builder: (context) => EditorAlert(
              title: 'That name is taken',
              message: 'Another screen is already called $name.',
              actions: [
                EditorButton(
                  label: 'OK',
                  kind: EditorButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        }
      case 'duplicate':
        session.duplicateScreen(path);
      case 'list':
        session.setListed(path, !listed);
      case 'delete':
        final sure = await showEditorConfirm(
          context,
          title: 'Delete $_label?',
          message: 'Its file is deleted and it leaves the game\'s list.',
          confirmLabel: 'Delete',
        );
        if (sure == true) session.deleteScreen(path);
    }
  }
}

/// Asks for a name, [initial] filled in. Null when cancelled.
Future<String?> promptForName(
  BuildContext context,
  String title,
  String initial,
) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => EditorAlert(
      title: title,
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
        decoration: editorFieldDecoration(hint: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        EditorButton(
          label: 'Cancel',
          kind: EditorButtonKind.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        EditorButton(
          label: 'OK',
          kind: EditorButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// A small caption over a panel, with buttons at its right.
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
