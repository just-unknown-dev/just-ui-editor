/// The bars above and below the canvas: how it is looked at, and how it is
/// tried out.
library;

import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_signals/just_signals.dart';

import '../../runtime/components/button_component.dart';
import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/text_component.dart';
import '../../runtime/logic/ui_bindings.dart';
import '../document/ui_screen_document.dart';
import '../panels/screens_panel.dart';
import '../session/ui_device.dart';
import '../session/ui_editor_session.dart';

/// Every binding the open screen reads, by name.
List<String> bindingsOf(UiScreenDocument doc) {
  final names = <String>{};
  for (final e in doc.world.entities) {
    if (e.getComponent<TextComponent>() case final t?) {
      names.addAll(UiBindings.namesIn(t.text));
    }
    if (e.getComponent<ButtonComponent>() case final b?) {
      names.addAll(UiBindings.namesIn(b.label));
    }
    for (final plain in [
      e.getComponent<UiToggleComponent>()?.binding,
      e.getComponent<UiSliderComponent>()?.binding,
      e.getComponent<UiProgressComponent>()?.binding,
      e.getComponent<UiProgressComponent>()?.maxBinding,
    ]) {
      if (plain != null && plain.isNotEmpty) names.add(plain);
    }
    if (e.getComponent<UiCustomComponent>() case final c?) {
      for (final value in c.props.values) {
        names.addAll(UiBindings.namesIn(value));
      }
    }
  }
  return names.where((n) => !n.startsWith('self.')).toList()..sort();
}

/// Above the canvas: the device, the zoom, what is drawn over the screen,
/// and Edit or Preview.
class UiCanvasToolbar extends StatelessWidget {
  const UiCanvasToolbar({super.key, required this.session});

  final UiEditorSession session;

  /// How tall the bars along the top of the three columns are — this one,
  /// the Screens header and the Inspector/Theme tabs — so their lines meet.
  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        session.device,
        session.landscape,
        session.zoom,
        session.shownZoom,
        session.grid,
        session.gridStep,
        session.snap,
        session.rulers,
        session.showGuides,
        session.boxes,
        session.mode,
      ],
      builder: (context, _) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: EditorTheme.panelBg,
          border: Border(bottom: BorderSide(color: EditorTheme.border)),
        ),
        child: Row(
          children: [
            _DeviceButton(session: session),
            const SizedBox(width: 2),
            EditorIconButton(
              icon: Icons.screen_rotation_alt_rounded,
              tooltip: session.landscape.value ? 'Upright' : 'On its side',
              isActive: session.landscape.value,
              onTap: () => session.landscape.value = !session.landscape.value,
            ),
            const _Gap(),
            EditorIconButton(
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              shortcut: EditorKeys.withPrimary('-'),
              onTap: () => session.zoomStep(-1),
            ),
            _ZoomButton(session: session),
            EditorIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Zoom in',
              shortcut: EditorKeys.withPrimary('='),
              onTap: () => session.zoomStep(1),
            ),
            const SizedBox(width: 2),
            EditorIconButton(
              icon: Icons.fit_screen_rounded,
              tooltip: 'Fit',
              shortcut: EditorKeys.withPrimary('0'),
              isActive: session.zoom.value == 0,
              onTap: session.zoomToFit,
            ),
            const _Gap(),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  // Apart, so two lit side by side still read as two.
                  spacing: 2,
                  children: [
                    EditorIconButton(
                      icon: Icons.near_me_rounded,
                      tooltip:
                          'Snap to edges, centres and guides — hold '
                          '${EditorKeys.primaryLabel} '
                          'while dragging to place freely',
                      isActive: session.snap.value,
                      onTap: () => session.snap.value = !session.snap.value,
                    ),
                    GestureDetector(
                      onSecondaryTapUp: (d) =>
                          _gridMenu(context, d.globalPosition),
                      child: EditorIconButton(
                        icon: session.grid.value
                            ? Icons.grid_on_rounded
                            : Icons.grid_off_rounded,
                        tooltip:
                            'Grid, every ${session.gridStep.value.toInt()} px — '
                            'right-click for another step',
                        isActive: session.grid.value,
                        onTap: () => session.grid.value = !session.grid.value,
                      ),
                    ),
                    EditorIconButton(
                      icon: Icons.straighten_rounded,
                      tooltip: 'Rulers — drag out of one for a guide',
                      isActive: session.rulers.value,
                      onTap: () => session.rulers.value = !session.rulers.value,
                    ),
                    EditorIconButton(
                      icon: Icons.border_vertical_rounded,
                      tooltip: 'Guides',
                      isActive: session.showGuides.value,
                      onTap: () =>
                          session.showGuides.value = !session.showGuides.value,
                    ),
                    EditorIconButton(
                      icon: Icons.select_all_rounded,
                      tooltip: 'Outline every element',
                      isActive: session.boxes.value,
                      onTap: () => session.boxes.value = !session.boxes.value,
                    ),
                  ],
                ),
              ),
            ),
            EditorSegmented<UiEditMode>(
              value: session.mode.value,
              options: const [
                (UiEditMode.edit, 'Edit'),
                (UiEditMode.preview, 'Preview'),
              ],
              onChanged: (mode) {
                session.mode.value = mode;
                session.lastAction.value = null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _gridMenu(BuildContext context, Offset at) async {
    final step = await showEditorMenu<double>(context, at, [
      editorMenuHeading('Grid step'),
      for (final s in const [4.0, 8.0, 10.0, 16.0, 20.0, 32.0, 50.0, 64.0])
        editorMenuItem(
          s,
          '${s.toInt()} px',
          icon: session.gridStep.value == s ? Icons.check : null,
          iconSlot: true,
        ),
    ]);
    if (step == null) return;
    session.gridStep.value = step;
    session.grid.value = true;
  }
}

class _DeviceButton extends StatelessWidget {
  const _DeviceButton({required this.session});

  final UiEditorSession session;

  @override
  Widget build(BuildContext context) {
    final device = session.device.value;
    final size = device.sizeFor(landscape: session.landscape.value);
    return Builder(
      builder: (context) => TextButton.icon(
        onPressed: () => _menu(context),
        icon: Icon(
          Icons.devices_rounded,
          size: 14,
          color: EditorTheme.textSecondary,
        ),
        label: Text(
          '${device.name}  ${size.width.toInt()}×${size.height.toInt()}',
          style: TextStyle(
            color: EditorTheme.textPrimary,
            fontSize: EditorMetrics.fontBody,
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final chosen = await showEditorMenu<UiDevice?>(context, at, [
      for (final d in UiDevices.all)
        editorMenuItem<UiDevice?>(
          d,
          '${d.name} — ${d.width.toInt()}×${d.height.toInt()}',
          icon: d == session.device.value ? Icons.check : null,
          iconSlot: true,
        ),
      editorMenuDivider(),
      editorMenuItem<UiDevice?>(
        null,
        'A size of my own…',
        icon: Icons.aspect_ratio,
      ),
    ]);
    if (!context.mounted) return;
    if (chosen != null) {
      session.setDevice(chosen);
      return;
    }
    if (box == null) return;
    final typed = await promptForName(
      context,
      'Screen size, width × height',
      '${session.device.value.width.toInt()}x${session.device.value.height.toInt()}',
    );
    if (typed == null) return;
    final parts = typed.toLowerCase().split(RegExp(r'[x×, ]+'));
    final w = parts.isNotEmpty ? double.tryParse(parts.first) : null;
    final h = parts.length > 1 ? double.tryParse(parts[1]) : null;
    if (w != null && h != null && w > 16 && h > 16) {
      session.setDevice(UiDevice.custom(w, h));
    }
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.session});

  final UiEditorSession session;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => InkWell(
      onTap: () async {
        final box = context.findRenderObject() as RenderBox?;
        final at = box == null
            ? Offset.zero
            : box.localToGlobal(box.size.bottomLeft(Offset.zero));
        final chosen = await showEditorMenu<double>(context, at, [
          editorMenuItem(0, 'Fit', shortcut: EditorKeys.withPrimary('0')),
          for (final z in const [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0])
            editorMenuItem(
              z,
              '${(z * 100).round()}%',
              shortcut: z == 1 ? EditorKeys.withPrimary('1') : null,
            ),
        ]);
        if (chosen == null) return;
        // Fit also puts the frame back in the middle; a size keeps it where
        // it is.
        chosen == 0 ? session.zoomToFit() : session.zoom.value = chosen;
      },
      child: SizedBox(
        width: 46,
        child: Center(
          child: Text(
            '${(session.shownZoom.value * 100).round()}%',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: EditorMetrics.fontBody,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: EditorTheme.border,
  );
}

/// Below the canvas: what to try the screen with — other screens under it,
/// its buttons in another state, made-up values for what it reads, bigger
/// text — and what the last button pressed in Preview would have done.
class UiPreviewStrip extends StatefulWidget {
  const UiPreviewStrip({super.key, required this.session, this.onOpen});

  final UiEditorSession session;

  /// Opens a screen — asking about the open one's unsaved work first: what
  /// "Open it" does. Without one, "Open it" is not offered.
  final void Function(String path)? onOpen;

  @override
  State<UiPreviewStrip> createState() => _UiPreviewStripState();
}

class _UiPreviewStripState extends State<UiPreviewStrip> {
  bool _samplesOpen = false;

  UiEditorSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        session.document,
        session.behind,
        session.forcedState,
        session.textScale,
        session.lastAction,
        session.mode,
        session.files,
      ],
      builder: (context, _) {
        final doc = session.document.value;
        if (doc == null) return const SizedBox.shrink();
        return SignalBuilder<Map<String, dynamic>>(
          signal: doc.editorData,
          builder: (context, _, _) => Container(
            decoration: BoxDecoration(
              color: EditorTheme.panelBg,
              border: Border(top: BorderSide(color: EditorTheme.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: UiCanvasToolbar.height, child: _controls(doc)),
                if (_samplesOpen) _samples(doc),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controls(UiScreenDocument doc) {
    final others = [
      for (final name in session.screensByName.keys)
        if (name != doc.name) name,
    ]..sort();
    final behind = session.behind.value;
    final message = session.lastAction.value;
    return Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (others.isNotEmpty) ...[
                  _Label('Under it'),
                  for (final name in others)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: EditorChip(
                        label: name,
                        selected: behind.contains(name),
                        onTap: () =>
                            session.behind.value = behind.contains(name)
                            ? [
                                for (final n in behind)
                                  if (n != name) n,
                              ]
                            : [...behind, name],
                      ),
                    ),
                  const _Gap(),
                ],
                _Label('Buttons'),
                EditorSegmented<UiInteractionState?>(
                  value: session.forcedState.value,
                  options: const [
                    (null, 'As they are'),
                    (UiInteractionState.hovered, 'Hover'),
                    (UiInteractionState.pressed, 'Pressed'),
                    (UiInteractionState.disabled, 'Off'),
                  ],
                  onChanged: (s) => session.forcedState.value = s,
                ),
                const _Gap(),
                _Label('Text'),
                EditorSegmented<double>(
                  value: session.textScale.value,
                  options: const [(1.0, '100%'), (1.3, '130%'), (1.6, '160%')],
                  onChanged: (s) => session.textScale.value = s,
                ),
                const _Gap(),
                EditorChip(
                  label: 'Sample values',
                  count: session.samples.length,
                  selected: _samplesOpen,
                  onTap: () => setState(() => _samplesOpen = !_samplesOpen),
                ),
                if (doc.settings?.isScreen ?? false) ...[
                  const SizedBox(width: 4),
                  EditorIconButton(
                    icon: Icons.play_arrow_rounded,
                    tooltip: 'Play how it opens',
                    onTap: () => _replayOpening(doc),
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        if (message != null) ...[
          // Set apart from the controls, which scroll away under it.
          const _Gap(),
          Icon(Icons.info_outline, size: 12, color: EditorTheme.info),
          const SizedBox(width: 4),
          // The controls keep their room; a long message is cut short.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: EditorMetrics.fontLabel,
              ),
            ),
          ),
          if ((widget.onOpen, _openTarget(message)) case (
            final open?,
            final path?,
          ))
            TextButton(
              onPressed: () => open(path),
              // The editor's accent, not the Material default's purple.
              style: TextButton.styleFrom(
                foregroundColor: EditorTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Open it',
                style: TextStyle(fontSize: EditorMetrics.fontLabel),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  /// The screen a preview button would have opened, if it is one.
  String? _openTarget(String message) {
    const prefix = 'Opens ';
    if (!message.startsWith(prefix)) return null;
    final name = message.substring(prefix.length).split(' ').first;
    if (name == session.document.value?.name) return null;
    return session.screensByName[name];
  }

  /// Closes the screen and opens it again, so its transition plays — the
  /// copy Preview shows while previewing, never the document's own canvas.
  void _replayOpening(UiScreenDocument doc) {
    final settings =
        session.previewCanvas?.getComponent<UiCanvasComponent>() ??
        doc.settings;

    if (settings == null) return;
    settings
      ..visible = false
      ..markDirty();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      settings
        ..visible = true
        ..markDirty();
    });
  }

  Widget _samples(UiScreenDocument doc) {
    final names = bindingsOf(doc);
    final samples = session.samples;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: names.isEmpty
          ? Text(
              'Nothing on this screen reads the game. Texts that do — '
              '"Coins: {coins}" — show made-up values here.',
              style: TextStyle(
                color: EditorTheme.textMuted,
                fontSize: EditorMetrics.fontLabel,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in names)
                  SizedBox(
                    width: 180,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            '{$name}',
                            overflow: TextOverflow.ellipsis,
                            style: InspectorField.labelStyle.copyWith(
                              color: UiBindings.has(name)
                                  ? null
                                  : EditorTheme.warning,
                            ),
                          ),
                        ),
                        Expanded(
                          child: CommitTextField(
                            key: ValueKey('sample:$name:${samples[name]}'),
                            value: samples[name] ?? '',
                            onCommit: (v) => session.setSample(name, v),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: EditorMetrics.fontLabel,
      ),
    ),
  );
}
