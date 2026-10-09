/// The Theme tab: one file for a whole game's look — colours, text, shape
/// and the sounds a menu makes.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/text/ui_fonts.dart';
import '../../runtime/text/ui_text_style.dart';
import '../../runtime/theme/ui_theme.dart';
import '../inspector/ui_field_editors.dart';
import '../session/ui_editor_session.dart';
import 'ui_theme_document.dart';

/// Edits the theme the open screen is drawn with — or any other in the
/// project. Every edit shows on the canvas at once; nothing is written
/// until Save.
class UiThemePanel extends StatefulWidget {
  const UiThemePanel({super.key, required this.session});

  final UiEditorSession session;

  @override
  State<UiThemePanel> createState() => _UiThemePanelState();
}

class _UiThemePanelState extends State<UiThemePanel> {
  UiEditorSession get session => widget.session;

  Future<void> _switchTo(String path) async {
    final open = session.theme.value;
    if (open != null && open.path == path) return;
    final go = await mayLeaveUnsaved(
      context,
      dirty: open?.dirty.value ?? false,
      title: 'Save the theme first?',
      message: '${open?.path} has changes that are not saved.',
      save: () async => session.saveTheme(),
    );
    if (go) session.openTheme(path);
  }

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [session.theme, session.document],
      builder: (context, _) {
        final doc = session.theme.value;
        if (doc == null) {
          final themes = session.themeFiles;
          return EditorEmptyState(
            icon: Icons.palette_outlined,
            title: themes.isEmpty ? 'No theme yet' : 'No theme open',
            hint: themes.isEmpty
                ? 'A theme is one file for a whole game’s look: colours, '
                      'text, corners and the sounds a menu makes.'
                : 'Open one of the project’s themes.',
            actionLabel: themes.isEmpty ? 'Make one' : 'Open ${themes.first}',
            actionIcon: themes.isEmpty ? Icons.add : Icons.folder_open,
            onAction: () => themes.isEmpty
                ? session.createTheme()
                : session.openTheme(themes.first),
          );
        }
        final screen = session.document.value;
        return SignalConsumer(
          // The screen's edits too: which theme it is drawn with is one.
          signals: [doc.theme, doc.history.revision, ?screen?.history.revision],
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(doc),
              Expanded(child: _tokens(doc)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(UiThemeDocument doc) {
    final screen = session.document.value;
    final uses = session.themePathFor(screen);
    final themes = session.themeFiles;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownEditorRow(
                  label: 'Theme',
                  value: doc.path,
                  options: {...themes, doc.path}.toList(),
                  onChanged: _switchTo,
                ),
              ),
              if (doc.dirty.value)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message: 'Not saved',
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: EditorTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              EditorIconButton(
                icon: Icons.undo_rounded,
                tooltip: doc.history.nextUndoLabel.value == null
                    ? 'Undo'
                    : 'Undo ${doc.history.nextUndoLabel.value}',
                onTap: doc.history.canUndo.value ? doc.history.undo : null,
              ),
              EditorIconButton(
                icon: Icons.redo_rounded,
                tooltip: 'Redo',
                onTap: doc.history.canRedo.value ? doc.history.redo : null,
              ),
              EditorIconButton(
                icon: Icons.save_outlined,
                tooltip: 'Save the theme',
                isActive: doc.dirty.value,
                onTap: doc.dirty.value ? session.saveTheme : null,
              ),
            ],
          ),
          if (screen != null && uses != doc.path) ...[
            const SizedBox(height: 6),
            Text(
              '${screen.name} is drawn with ${uses ?? 'the built-in theme'}.',
              style: TextStyle(
                color: EditorTheme.textMuted,
                fontSize: EditorMetrics.fontLabel,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: EditorButton(
                label: 'Draw ${screen.name} with this theme',
                kind: EditorButtonKind.secondary,
                onPressed: () => _useFor(screen.canvas, doc.path),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _useFor(jge.Entity canvas, String path) {
    final screen = session.document.value;
    final settings = screen?.settings;
    if (screen == null || settings == null) return;
    screen.history.breakMerge();
    screen.history.push(
      ComponentFieldCommand(
        label: 'Use ${path.split('/').last}',
        component: settings,
        write: (c, v) => (c as UiCanvasComponent).theme = v as String,
        before: settings.theme,
        after: path,
        sceneState: screen.sceneState,
      ),
    );
  }

  Widget _tokens(UiThemeDocument doc) {
    final theme = doc.theme.value;
    void set(UiTheme next, String label) => doc.change(next, label);
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _Group(
          title: 'Colours',
          children: [
            for (final role in UiPalette.roles) ...[
              ColorEditorRow(
                label: role,
                paintStyle: jge.ShapePaintStyle(
                  color: theme.palette.byName(role) ?? const Color(0xFF000000),
                ),
                onChanged: (style) => set(
                  theme.copyWith(
                    palette: _withRole(theme.palette, role, style.color),
                  ),
                  'Colour $role',
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
        _Group(
          title: 'Text',
          children: [
            for (final role in const [
              'title',
              'body',
              'caption',
              'button',
            ]) ...[
              UiTextStyleEditorRow(
                label: role,
                style: theme.textStyles[role] ?? const UiTextStyle(),
                fontFamilies: UiFonts.families,
                // What the role looks like when this theme says nothing about
                // it: the built-in default for that role, in these colours.
                inherited: UiTheme(palette: theme.palette).textStyle(role),
                inheritedFrom: 'the default',
                onChanged: (style) => set(
                  theme.copyWith(
                    textStyles: {...theme.textStyles, role: style},
                  ),
                  'Text $role',
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
        _Group(
          title: 'Shape',
          children: [
            ScrubFieldRow(
              label: 'Corner',
              value: theme.radius,
              scrubConfig: const NumberScrubConfig(fractionDigits: 0),
              onChanged: (v) => set(theme.copyWith(radius: v), 'Corner'),
            ),
            const SizedBox(height: 6),
            ScrubFieldRow(
              label: 'Spacing',
              value: theme.spacing,
              scrubConfig: const NumberScrubConfig(fractionDigits: 0),
              onChanged: (v) => set(theme.copyWith(spacing: v), 'Spacing'),
            ),
          ],
        ),
        _Group(
          title: 'Sounds',
          children: [
            for (final (label, read, write)
                in <(String, String, UiSounds Function(String))>[
                  (
                    'Hover',
                    theme.sounds.hover,
                    (p) => UiSounds(
                      hover: p,
                      press: theme.sounds.press,
                      toggle: theme.sounds.toggle,
                    ),
                  ),
                  (
                    'Press',
                    theme.sounds.press,
                    (p) => UiSounds(
                      hover: theme.sounds.hover,
                      press: p,
                      toggle: theme.sounds.toggle,
                    ),
                  ),
                  (
                    'Toggle',
                    theme.sounds.toggle,
                    (p) => UiSounds(
                      hover: theme.sounds.hover,
                      press: theme.sounds.press,
                      toggle: p,
                    ),
                  ),
                ]) ...[
              AssetRefEditorRow(
                label: label,
                value: read,
                extensions: const ['wav', 'mp3', 'ogg'],
                onChanged: (path) =>
                    set(theme.copyWith(sounds: write(path)), 'Sound $label'),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
        _Sample(theme: theme),
      ],
    );
  }

  static UiPalette _withRole(UiPalette palette, String role, Color color) =>
      switch (role) {
        'primary' => palette.copyWith(primary: color),
        'onPrimary' => palette.copyWith(onPrimary: color),
        'surface' => palette.copyWith(surface: color),
        'onSurface' => palette.copyWith(onSurface: color),
        'accent' => palette.copyWith(accent: color),
        'danger' => palette.copyWith(danger: color),
        'success' => palette.copyWith(success: color),
        'muted' => palette.copyWith(muted: color),
        'outline' => palette.copyWith(outline: color),
        _ => palette,
      };
}

/// A small card in the theme, built from the widgets a screen is — for a
/// look at a role no screen on the canvas uses.
class _Sample extends StatelessWidget {
  const _Sample({required this.theme});

  final UiTheme theme;

  @override
  Widget build(BuildContext context) => Theme(
    data: theme.toThemeData(),
    child: Container(
      padding: EdgeInsets.all(theme.spacing),
      decoration: BoxDecoration(
        color: theme.palette.surface,
        border: Border.all(color: theme.palette.outline),
        borderRadius: BorderRadius.circular(theme.radius),
      ),
      child: DefaultTextStyle(
        style: theme.textStyle('body').toTextStyle(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title', style: theme.textStyle('title').toTextStyle()),
            const SizedBox(height: 4),
            const Text('Body text, as a line would read.'),
            Text('A caption.', style: theme.textStyle('caption').toTextStyle()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Play')),
                FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.palette.danger,
                  ),
                  child: const Text('Quit'),
                ),
                const FilledButton(onPressed: null, child: Text('Locked')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A block of the theme, drawn as the inspector's component cards are —
/// the same fill, edge and inset — so its rows sit on the same columns as
/// the Inspector tab's and switching tabs does not shift them.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(13, 8, 10, 4),
    decoration: BoxDecoration(
      color: EditorTheme.dialogBg,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
      border: Border.all(
        color: EditorTheme.borderStrong.withValues(alpha: 0.5),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: InspectorField.labelStyle.copyWith(
              color: EditorTheme.primaryBright,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...children,
      ],
    ),
  );
}
