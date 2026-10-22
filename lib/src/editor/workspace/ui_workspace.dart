/// The interface editor: screens on the left, the screen in the middle, the
/// inspector and the theme on the right.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/screens/ui_document.dart';
import '../canvas/ui_canvas_bars.dart';
import '../canvas/ui_canvas_view.dart';
import '../document/ui_screen_document.dart';
import '../panels/hierarchy_panel.dart';
import '../panels/screens_panel.dart';
import '../panels/ui_inspector_panel.dart';
import '../panels/widget_palette.dart';
import '../project/ui_project.dart';
import '../session/ui_edit_ops.dart';
import '../session/ui_editor_session.dart';
import '../theme/theme_panel.dart';

/// The interface editor, opened on [path] — a screen, or a theme — or on the
/// game's first screen.
class UiEditorWorkspace extends StatefulWidget {
  const UiEditorWorkspace({
    super.key,
    required this.scope,
    required this.project,
    this.path,
    this.onClose,
    this.onSaved,
    this.fullScreen,
    this.onToggleFullScreen,
    this.setCloseGuard,
  });

  final EditorScope scope;
  final UiProject project;
  final String? path;

  /// Leaves the editor. Asked about unsaved work first, here.
  final VoidCallback? onClose;

  /// A file was written: whatever shows it — the running game — reads it
  /// again.
  final void Function(String path)? onSaved;

  final ValueListenable<bool>? fullScreen;
  final VoidCallback? onToggleFullScreen;

  /// Where to register "ask before closing", so the editor asks too when
  /// something opens another workspace over this one.
  final void Function(Future<bool> Function()? guard)? setCloseGuard;

  @override
  State<UiEditorWorkspace> createState() => UiEditorWorkspaceState();
}

class UiEditorWorkspaceState extends State<UiEditorWorkspace> {
  late final UiEditorSession session;
  final GlobalKey<UiCanvasViewState> _canvas = GlobalKey<UiCanvasViewState>();
  final GlobalKey<UiHierarchyPanelState> _hierarchy =
      GlobalKey<UiHierarchyPanelState>();

  /// The right column: 0 the inspector, 1 the theme.
  final Signal<int> tab = Signal(0, debugLabel: 'uiRightTab');

  @override
  void initState() {
    super.initState();
    session = UiEditorSession(
      project: widget.project,
      codec: widget.scope.codec,
      context: widget.scope.context,
    );
    _openFirst();
    // The Theme tab starts on the open screen's own theme. Here, before
    // anything listens: the tab is built with the rest of the workspace,
    // and opening it from there changed the header in mid-build.
    if (session.theme.value == null) {
      final theme = session.themePathFor(session.document.value);
      if (theme != null) session.openTheme(theme);
    }
    widget.setCloseGuard?.call(_mayLeave);
  }

  void _openFirst() {
    final path = widget.path;
    if (path != null && path.endsWith('.uitheme.json')) {
      session.openTheme(path);
      tab.value = 1;
    } else if (path != null && path.endsWith('.${UiDocument.extension}')) {
      if (session.open(path)) return;
    }
    if (session.document.value != null) return;
    final listed = session.manifest.value.screens;
    for (final entry in listed) {
      if (session.open(entry.path)) return;
    }
    final files = session.files.value;
    if (files.isNotEmpty) session.open(files.first);
  }

  @override
  void dispose() {
    widget.setCloseGuard?.call(null);
    session.dispose();
    tab.dispose();
    super.dispose();
  }

  // ── Saving and leaving ─────────────────────────────────────────────────

  Future<bool> _mayLeave() => mayLeaveUnsaved(
    context,
    dirty: session.hasUnsavedWork,
    title: 'Save the interface?',
    message: _unsavedMessage(),
    save: () async => save(),
  );

  String _unsavedMessage() {
    final doc = session.document.value;
    final theme = session.theme.value;
    final what = [
      if (doc != null && doc.dirty.value) doc.name,
      if (theme != null && theme.dirty.value) theme.path.split('/').last,
    ];
    final verb = what.length > 1 ? 'have' : 'has';
    return '${what.join(' and ')} $verb changes that are not saved.';
  }

  /// Saves what is unsaved, and tells the editor which files changed.
  bool save() {
    final doc = session.document.value;
    final theme = session.theme.value;
    final docDirty = doc?.dirty.value ?? false;
    final themeDirty = theme?.dirty.value ?? false;
    final ok = session.saveAll();
    if (docDirty && doc != null) widget.onSaved?.call(doc.path);
    if (themeDirty && theme != null) widget.onSaved?.call(theme.path);
    return ok;
  }

  Future<void> close() async {
    if (await _mayLeave()) widget.onClose?.call();
  }

  Future<void> openScreen(String path) async {
    final doc = session.document.value;
    if (doc?.path == path) return;
    final go = await mayLeaveUnsaved(
      context,
      dirty: doc?.dirty.value ?? false,
      title: 'Save ${doc?.name}?',
      message: '${doc?.name} has changes that are not saved.',
      save: () async => session.save(),
    );
    if (go) session.open(path);
  }

  Future<void> _newScreen({required bool isScreen}) async {
    final name = await promptForName(
      context,
      isScreen ? 'New screen' : 'New layer',
      session.freeScreenName(isScreen ? 'Screen' : 'Layer'),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final doc = session.document.value;
    final go = await mayLeaveUnsaved(
      context,
      dirty: doc?.dirty.value ?? false,
      title: 'Save ${doc?.name}?',
      save: () async => session.save(),
    );
    if (!go) return;
    final made = session.createScreen(
      session.freeScreenName(name),
      isScreen: isScreen,
      startOpen: !isScreen,
    );
    widget.onSaved?.call(made.path);
    widget.onSaved?.call('assets/ui/screens.json');
  }

  // ── History ────────────────────────────────────────────────────────────

  /// The history the keys and the header act on: the theme's while its tab
  /// is showing, the screen's otherwise.
  EditorHistory? get _history => tab.value == 1
      ? session.theme.value?.history
      : session.document.value?.history;

  // ── Keys ───────────────────────────────────────────────────────────────

  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final ctrl = EditorKeys.primaryPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final doc = session.document.value;

    if (ctrl) {
      switch (key) {
        case LogicalKeyboardKey.keyS:
          save();
        case LogicalKeyboardKey.keyZ:
          shift ? _history?.redo() : _history?.undo();
        case LogicalKeyboardKey.keyY:
          _history?.redo();
        case LogicalKeyboardKey.keyD:
          session.duplicateSelection();
        case LogicalKeyboardKey.keyC:
          session.copySelection();
        case LogicalKeyboardKey.keyX:
          session.cutSelection();
        case LogicalKeyboardKey.keyV:
          session.paste();
        case LogicalKeyboardKey.keyA:
          _selectAll(doc);
        case LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0:
          session.zoomToFit();
        case LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1:
          session.zoom.value = 1;
        case LogicalKeyboardKey.equal || LogicalKeyboardKey.numpadAdd:
          session.zoomStep(1);
        case LogicalKeyboardKey.minus || LogicalKeyboardKey.numpadSubtract:
          session.zoomStep(-1);
        case LogicalKeyboardKey.keyP:
          session.mode.value = session.previewing
              ? UiEditMode.edit
              : UiEditMode.preview;
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    // The modifier no shortcut is made with (Ctrl on a Mac): none of the
    // plain keys either.
    if (EditorKeys.otherPressed) return KeyEventResult.ignored;

    switch (key) {
      case LogicalKeyboardKey.escape:
        // One step back at a time: a drag, then the selection, then out.
        if (_canvas.currentState?.cancelDrag() ?? false) break;
        if (session.previewing) {
          session.mode.value = UiEditMode.edit;
          break;
        }
        if (doc != null && doc.sceneState.hasAnySelection) {
          doc.sceneState.clearSelection();
          break;
        }
        close();
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        session.deleteSelection();
      case LogicalKeyboardKey.f2:
        _hierarchy.currentState?.renameSelected();
      case LogicalKeyboardKey.arrowLeft:
        _nudge(const Offset(-1, 0), shift);
      case LogicalKeyboardKey.arrowRight:
        _nudge(const Offset(1, 0), shift);
      case LogicalKeyboardKey.arrowUp:
        _nudge(const Offset(0, -1), shift);
      case LogicalKeyboardKey.arrowDown:
        _nudge(const Offset(0, 1), shift);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _nudge(Offset direction, bool big) {
    if (session.previewing) return;
    final step = big
        ? 10.0
        : (session.grid.value ? session.gridStep.value : 1.0);
    session.nudge(direction * step);
  }

  void _selectAll(UiScreenDocument? doc) {
    if (doc == null) return;
    final all = doc.entities.skip(1).toList();
    if (all.isEmpty) return;
    doc.sceneState.selectEntity(all.first);
    for (final e in all.skip(1)) {
      doc.sceneState.toggleMultiSelect(e);
    }
  }

  // ── Building ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WorkspaceKeyScope(
      onKey: _onKey,
      child: UiSamplesScope(
        session: session,
        child: ColoredBox(
          color: EditorTheme.surfaceDarker,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 248, child: _left()),
                    VerticalDivider(width: 1, color: EditorTheme.border),
                    Expanded(child: _middle()),
                    VerticalDivider(width: 1, color: EditorTheme.border),
                    SizedBox(width: 320, child: _right()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return SignalConsumer(
      signals: [session.document, session.theme, tab],
      builder: (context, _) {
        final doc = session.document.value;
        final theme = session.theme.value;
        final watched = [
          ?doc?.history.revision,
          ?theme?.history.revision,
          ?doc?.sceneState.revision,
        ];
        return SignalConsumer(
          signals: watched.isEmpty ? [tab] : watched,
          builder: (context, _) {
            final history = _history;
            return WorkspaceHeader(
              icon: Icons.web_asset_rounded,
              title: 'Interface',
              file: tab.value == 1 ? theme?.path : doc?.path,
              dirty: session.hasUnsavedWork,
              onSave: save,
              onUndo: (history?.canUndo.value ?? false) ? history!.undo : null,
              onRedo: (history?.canRedo.value ?? false) ? history!.redo : null,
              undoLabel: history?.nextUndoLabel.value,
              redoLabel: history?.nextRedoLabel.value,
              fullScreen: widget.fullScreen,
              onToggleFullScreen: widget.onToggleFullScreen,
              onClose: widget.onClose == null ? null : close,
              closeTooltip: 'Close the interface editor',
            );
          },
        );
      },
    );
  }

  /// Screens as tall as its list — a few rows, not a third of the column
  /// of empty space — up to a share of it; the hierarchy and the widgets
  /// share the rest.
  Widget _left() => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: box.maxHeight * 0.35),
          child: UiScreensPanel(
            session: session,
            onOpen: openScreen,
            onNew: _newScreen,
          ),
        ),
        Divider(height: 1, color: EditorTheme.border),
        const UiPanelHeader(title: 'HIERARCHY'),
        Expanded(
          flex: 5,
          child: UiHierarchyPanel(key: _hierarchy, session: session),
        ),
        Divider(height: 1, color: EditorTheme.border),
        Expanded(flex: 4, child: UiWidgetPalette(session: session)),
      ],
    ),
  );

  Widget _middle() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      UiCanvasToolbar(session: session),
      Expanded(
        child: UiCanvasView(key: _canvas, session: session),
      ),
      UiPreviewStrip(session: session),
    ],
  );

  Widget _right() => SignalBuilder<int>(
    signal: tab,
    builder: (context, index, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // As tall as the toolbar beside it, so the line under both is one.
        Container(
          height: UiCanvasToolbar.height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EditorTheme.panelBg,
            border: Border(bottom: BorderSide(color: EditorTheme.border)),
          ),
          child: EditorSegmented<int>(
            value: index,
            options: const [(0, 'Inspector'), (1, 'Theme')],
            onChanged: (i) => tab.value = i,
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: index,
            children: [
              UiInspectorPanel(session: session, scope: widget.scope),
              UiThemePanel(session: session),
            ],
          ),
        ),
      ],
    ),
  );
}
