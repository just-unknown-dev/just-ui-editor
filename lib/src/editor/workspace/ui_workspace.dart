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
      // Every file the editor writes, moves or deletes: the running game
      // and the Assets dock read it again.
      onFilesChanged: (paths) {
        for (final path in paths) {
          widget.onSaved?.call(path);
        }
      },
    );
    final refused = _openFirst();
    if (refused != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tell('That screen does not open', refused);
      });
    }
    // The Theme tab starts on the open screen's own theme. Here, before
    // anything listens: the tab is built with the rest of the workspace,
    // and opening it from there changed the header in mid-build.
    if (session.theme.value == null) {
      final theme = session.themePathFor(session.document.value);
      if (theme != null) session.openTheme(theme);
    }
    widget.setCloseGuard?.call(_mayLeave);
  }

  /// Opens what the editor was asked for, or else the game's first screen
  /// that reads. Why what was asked for did not open, or null.
  String? _openFirst() {
    final path = widget.path;
    String? refused;
    if (path != null && path.endsWith('.uitheme.json')) {
      if (!session.openTheme(path)) refused = session.lastError;
      tab.value = 1;
    } else if (path != null && path.endsWith('.${UiDocument.extension}')) {
      if (session.open(path)) return null;
      refused = session.lastError;
    }
    if (session.document.value != null) return refused;
    final listed = session.manifest.value.screens;
    for (final entry in listed) {
      if (session.open(entry.path)) return refused;
    }
    final files = session.files.value;
    if (files.isNotEmpty) session.open(files.first);
    return refused;
  }

  /// Says [message] in a box with an OK button.
  Future<void> _tell(String title, String? message) => showDialog<void>(
    context: context,
    builder: (context) => EditorAlert(
      title: title,
      message: message ?? 'Something went wrong.',
      actions: [
        EditorButton(
          label: 'OK',
          kind: EditorButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

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

  /// Saves what is unsaved. False — and says why — when something was not
  /// written; it stays unsaved then. (The session tells the editor which
  /// files changed.)
  bool save() {
    session.lastError = null;
    final ok = session.saveAll();
    if (!ok) _tell('Not saved', session.lastError);
    return ok;
  }

  /// Saves the open screen alone — before another is opened in its place.
  bool _saveScreen() {
    final ok = session.save();
    if (!ok) _tell('Not saved', session.lastError);
    return ok;
  }

  Future<void> close() async {
    if (await _mayLeave()) widget.onClose?.call();
  }

  /// Opens the screen at [path] — asking about the open one's unsaved work
  /// first — and says so when it does not read.
  Future<void> openScreen(String path) async {
    final doc = session.document.value;
    if (doc?.path == path) return;
    final go = await mayLeaveUnsaved(
      context,
      dirty: doc?.dirty.value ?? false,
      title: 'Save ${doc?.name}?',
      message: '${doc?.name} has changes that are not saved.',
      save: () async => _saveScreen(),
    );
    if (!go || !mounted) return;
    if (!session.open(path)) {
      await _tell('That screen does not open', session.lastError);
    }
  }

  /// Copies the screen at [path] and opens the copy — asking about the
  /// open screen's unsaved work first, as any other opening does.
  Future<void> duplicateScreen(String path) async {
    final copy = session.duplicateScreen(path);
    if (copy == null) {
      await _tell('Not copied', session.lastError);
      return;
    }
    await openScreen(copy);
  }

  Future<void> _newScreen({required bool isScreen}) async {
    var suggestion = session.freeScreenName(isScreen ? 'Screen' : 'Layer');
    String? name;
    while (true) {
      name = await promptForName(
        context,
        isScreen ? 'New screen' : 'New layer',
        suggestion,
      );
      if (name == null || name.isEmpty || !mounted) return;
      final free = session.freeScreenName(name);
      if (free == name) break;
      // Taken — by another screen, or by a file the name would go to: say
      // so, and offer a free one, rather than quietly making another.
      await _tell(
        'That name is taken',
        'Another screen is already called $name, or its file '
            '(${session.pathFor(name)}) is there already.',
      );
      if (!mounted) return;
      suggestion = free;
    }
    final doc = session.document.value;
    final go = await mayLeaveUnsaved(
      context,
      dirty: doc?.dirty.value ?? false,
      title: 'Save ${doc?.name}?',
      save: () async => _saveScreen(),
    );
    if (!go || !mounted) return;
    try {
      session.createScreen(name, isScreen: isScreen, startOpen: !isScreen);
    } on Object catch (error) {
      await _tell('Not made', switch (error) {
        FormatException(:final message) => message,
        _ => '$error',
      });
    }
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

    // Delete everywhere, and Backspace on a Mac, whose keyboard calls it
    // delete — the editor's rule for what deletes.
    if (EditorKeys.isDeleteKey(key)) {
      session.deleteSelection();
      return KeyEventResult.handled;
    }
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
            onDuplicate: duplicateScreen,
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
      UiPreviewStrip(session: session, onOpen: openScreen),
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
