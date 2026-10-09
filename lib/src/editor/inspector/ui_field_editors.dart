/// Inspector rows for the UI field types: how text looks, what a button
/// does, and space around something.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_ui_editor/just_ui_editor.dart' as ui;

/// A text style on one row that opens into the rest of it.
///
/// Size and colour are what a person changes most, so those are always on
/// screen; weight, font, outline and shadow are a click away.
class UiTextStyleEditorRow extends StatefulWidget {
  const UiTextStyleEditorRow({
    super.key,
    required this.label,
    required this.style,
    required this.onChanged,
    this.fontFamilies = const [],
    this.inherited,
    this.inheritedFrom = '',
  });

  final String label;
  final ui.UiTextStyle style;
  final ValueChanged<ui.UiTextStyle> onChanged;

  /// What the project has in `assets/fonts/`, offered by name.
  final List<String> fontFamilies;

  /// What this style falls back to where it says nothing — the theme's
  /// style for the element's role. Null uses the engine's own defaults.
  final ui.UiTextStyle? inherited;

  /// What to call that, for the note under the row: `body`, `title`.
  final String inheritedFrom;

  @override
  State<UiTextStyleEditorRow> createState() => _UiTextStyleEditorRowState();
}

class _UiTextStyleEditorRowState extends State<UiTextStyleEditorRow> {
  bool _open = false;

  ui.UiTextStyle get _style => widget.style;

  /// What this text looks like where it says nothing for itself.
  ui.UiTextStyle get _under => (widget.inherited ?? const ui.UiTextStyle())
      .over(ui.UiTextStyle.fallback);

  void _set(ui.UiTextStyle next) => widget.onChanged(next);

  /// The size it is drawn at, which is the role's when it says nothing.
  double get _size => _style.size ?? _under.size!;

  /// Whether this style says anything at all for itself.
  bool get _saysAnything => _style.toJson().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final color = _style.color ?? _under.color ?? const Color(0xFFFFFFFF);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: InspectorField.labelWidth,
              // The label where every other row's is, the fold after it:
              // an arrow in front pushed this one label out of line.
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: InspectorField.labelStyle,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            // Bare controls: a whole row carries a second label column with
            // it, which overflows the one this row already has.
            SizedBox(
              width: 58,
              child: MiniNumberField(
                value: _size,
                fractionDigits: 0,
                inherited: _style.size == null,
                onSubmitted: (v) => _set(_style.copyWith(size: v)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: MiniColorField(
                color: color,
                inherited: _style.color == null,
                onChanged: (c) => _set(_style.copyWith(color: c)),
              ),
            ),
            // Only where there is something to undo: a row that always
            // offers to clear reads as though something is always set.
            if (_saysAnything)
              Tooltip(
                message: widget.inheritedFrom.isEmpty
                    ? 'Back to the theme'
                    : 'Back to ${widget.inheritedFrom}',
                child: IconButton(
                  onPressed: () => _set(const ui.UiTextStyle()),
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  iconSize: 14,
                  color: EditorTheme.textMuted,
                  splashRadius: 12,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                ),
              ),
          ],
        ),
        if (!_saysAnything && widget.inheritedFrom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: InspectorField.labelWidth,
              top: 3,
            ),
            child: Text(
              'all from the ${widget.inheritedFrom} role',
              style: InspectorField.labelStyle,
            ),
          ),
        if (_open) ...[
          const SizedBox(height: 6),
          DropdownEditorRow(
            label: 'Font',
            value: _style.family ?? '',
            // The empty option is "whatever the role says", which is how a
            // font is put back rather than picked again.
            options: ['', ...widget.fontFamilies],
            onChanged: (family) => _set(
              family.isEmpty
                  ? _style.without('family')
                  : _style.copyWith(family: family),
            ),
          ),
          const SizedBox(height: 6),
          DropdownEditorRow(
            label: 'Weight',
            value:
                '${(_style.weight ?? _under.weight ?? FontWeight.w400).value}',
            options: const ['300', '400', '500', '600', '700', '800', '900'],
            onChanged: (value) => _set(
              _style.copyWith(
                weight: FontWeight.values.firstWhere(
                  (w) => '${w.value}' == value,
                  orElse: () => FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          BoolEditorRow(
            label: 'Italic',
            value: _style.italic ?? _under.italic ?? false,
            onChanged: (v) => _set(_style.copyWith(italic: v)),
          ),
          const SizedBox(height: 6),
          ScrubFieldRow(
            label: 'Outline',
            value: _style.outline?.width ?? 0,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1),
            onChanged: (width) => _set(
              _style.copyWith(
                outline: (_style.outline ?? const ui.UiTextOutline()).copyWith(
                  width: width,
                ),
              ),
            ),
          ),
          if ((_style.outline?.width ?? 0) > 0) ...[
            const SizedBox(height: 6),
            ColorEditorRow(
              label: 'Outline colour',
              paintStyle: jge.ShapePaintStyle(
                color: _style.outline?.color ?? const Color(0xFF000000),
              ),
              onChanged: (s) => _set(
                _style.copyWith(
                  outline: (_style.outline ?? const ui.UiTextOutline())
                      .copyWith(color: s.color),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          ScrubFieldRow(
            label: 'Shadow',
            value: _style.shadow?.blur ?? 0,
            scrubConfig: const NumberScrubConfig(step: 0.5, fractionDigits: 1),
            onChanged: (blur) => _set(
              _style.copyWith(
                shadow: (_style.shadow ?? const ui.UiTextShadow()).copyWith(
                  blur: blur,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// What a UI element does: a list of actions, each a kind and an argument.
class UiActionsEditorRow extends StatelessWidget {
  const UiActionsEditorRow({
    super.key,
    required this.label,
    required this.actions,
    required this.onChanged,
    this.customNames = const [],
  });

  final String label;
  final ui.UiActionList actions;
  final ValueChanged<ui.UiActionList> onChanged;

  /// What the game has registered, offered beside the built-ins.
  final List<String> customNames;

  List<String> get _kinds => [
    ...ui.UiActions.builtIns.keys,
    for (final name in customNames) 'custom:$name',
  ];

  void _replace(int index, ui.UiAction action) => onChanged(
    ui.UiActionList([
      for (var i = 0; i < actions.actions.length; i++)
        i == index ? action : actions.actions[i],
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final list = actions.actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: InspectorField.labelWidth,
              child: Text(label, style: InspectorField.labelStyle),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EditorIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Add an action',
                  onTap: () => onChanged(
                    ui.UiActionList([...list, const ui.UiAction('none')]),
                  ),
                ),
              ),
            ),
          ],
        ),
        for (var i = 0; i < list.length; i++) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: EditorDropdown<String>(
                  value: list[i].kind,
                  options: [
                    for (final kind in _kinds)
                      EditorDropdownOption(value: kind, label: kind),
                  ],
                  onChanged: (kind) =>
                      _replace(i, list[i].copyWith(kind: kind)),
                ),
              ),
              const SizedBox(width: 6),
              // A kind that takes nothing shows nothing to fill in.
              if (_takesArgument(list[i].kind))
                Expanded(
                  flex: 4,
                  child: MiniTextField(
                    value: list[i].argument,
                    hint: ui.UiActions.builtIns[list[i].kind] ?? '',
                    onSubmitted: (v) =>
                        _replace(i, list[i].copyWith(argument: v)),
                  ),
                )
              else
                const Spacer(flex: 4),
              EditorIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Remove',
                onTap: () => onChanged(
                  ui.UiActionList([
                    for (var k = 0; k < list.length; k++)
                      if (k != i) list[k],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static bool _takesArgument(String kind) =>
      kind.startsWith('custom:') ||
      (ui.UiActions.builtIns[kind]?.isNotEmpty ?? false);
}

/// Space around something, as four numbers on one row.
class EdgeInsetsEditorRow extends StatelessWidget {
  const EdgeInsetsEditorRow({
    super.key,
    required this.label,
    required this.insets,
    required this.onChanged,
  });

  final String label;
  final EdgeInsets insets;
  final ValueChanged<EdgeInsets> onChanged;

  @override
  Widget build(BuildContext context) => AxesFieldRow(
    label: label,
    axes: const ['L', 'T', 'R', 'B'],
    values: [insets.left, insets.top, insets.right, insets.bottom],
    scrubConfig: const NumberScrubConfig(step: 1, fractionDigits: 0),
    onChanged: (next) =>
        onChanged(EdgeInsets.fromLTRB(next[0], next[1], next[2], next[3])),
  );
}

/// Where a child is pinned in its parent, chosen from a grid.
///
/// The grid is the fast way — nine corners and edges, plus the stretches —
/// and the four numbers underneath are there for everything else.
class UiAnchorEditorRow extends StatefulWidget {
  const UiAnchorEditorRow({
    super.key,
    required this.label,
    required this.anchor,
    required this.onChanged,
  });

  final String label;
  final ui.UiAnchor anchor;
  final ValueChanged<ui.UiAnchor> onChanged;

  @override
  State<UiAnchorEditorRow> createState() => _UiAnchorEditorRowState();
}

class _UiAnchorEditorRowState extends State<UiAnchorEditorRow> {
  bool _open = false;

  /// The nine points, in the order a grid reads them.
  static const List<String> _points = [
    'topLeft',
    'topCenter',
    'topRight',
    'centerLeft',
    'center',
    'centerRight',
    'bottomLeft',
    'bottomCenter',
    'bottomRight',
  ];

  static const List<String> _stretches = [
    'stretchTop',
    'stretchBottom',
    'stretchLeft',
    'stretchRight',
    'stretch',
  ];

  static const Map<String, String> _stretchLabels = {
    'stretchTop': 'Across the top',
    'stretchBottom': 'Across the bottom',
    'stretchLeft': 'Down the left',
    'stretchRight': 'Down the right',
    'stretch': 'The whole parent',
  };

  ui.UiAnchor get _anchor => widget.anchor;

  @override
  Widget build(BuildContext context) {
    final preset = _anchor.presetName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Laid out as a dropdown row is — the label, then the value in the
        // same box with a chevron at its end — so it lines up with the rows
        // around it; the box opens the grid below.
        Row(
          children: [
            SizedBox(
              width: InspectorField.labelWidth,
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: InspectorField.labelStyle,
              ),
            ),
            Expanded(
              child: Material(
                color: InspectorField.fill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(InspectorField.radius),
                  side: BorderSide(color: EditorTheme.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  hoverColor: EditorTheme.hoverBg,
                  child: SizedBox(
                    height: InspectorField.height,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              preset ?? 'Custom',
                              overflow: TextOverflow.ellipsis,
                              style: InspectorField.valueStyle,
                            ),
                          ),
                          Icon(
                            _open
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: InspectorField.fontSize + 2,
                            color: EditorTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: InspectorField.labelWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < 3; row++)
                  Row(
                    children: [
                      for (var column = 0; column < 3; column++)
                        _PresetCell(
                          name: _points[row * 3 + column],
                          selected: preset == _points[row * 3 + column],
                          onTap: _pick,
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
                for (final name in _stretches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      onTap: () => _pick(name),
                      child: Row(
                        children: [
                          Icon(
                            preset == name
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 12,
                            color: preset == name
                                ? EditorTheme.primary
                                : EditorTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _stretchLabels[name]!,
                            style: InspectorField.labelStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AxesFieldRow(
            label: 'From',
            axes: const ['X', 'Y'],
            values: [_anchor.min.dx, _anchor.min.dy],
            scrubConfig: const NumberScrubConfig(
              step: 0.05,
              fractionDigits: 2,
              min: 0,
              max: 1,
            ),
            onChanged: (next) => widget.onChanged(
              ui.UiAnchor(Offset(next[0], next[1]), _anchor.max),
            ),
          ),
          const SizedBox(height: 6),
          AxesFieldRow(
            label: 'To',
            axes: const ['X', 'Y'],
            values: [_anchor.max.dx, _anchor.max.dy],
            scrubConfig: const NumberScrubConfig(
              step: 0.05,
              fractionDigits: 2,
              min: 0,
              max: 1,
            ),
            onChanged: (next) => widget.onChanged(
              ui.UiAnchor(_anchor.min, Offset(next[0], next[1])),
            ),
          ),
        ],
      ],
    );
  }

  void _pick(String name) {
    final preset = ui.UiAnchor.presets[name];
    if (preset != null) widget.onChanged(preset);
  }
}

/// One cell of the anchor grid: a box with the corner it means drawn in it.
class _PresetCell extends StatelessWidget {
  const _PresetCell({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final anchor = ui.UiAnchor.presets[name]!;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: () => onTap(name),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: selected
                ? EditorTheme.primary.withValues(alpha: 0.18)
                : null,
            border: Border.all(
              color: selected ? EditorTheme.primary : EditorTheme.border,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: CustomPaint(painter: _AnchorDotPainter(anchor, selected)),
        ),
      ),
    );
  }
}

/// A dot where the anchor pins, so the grid can be read at a glance.
class _AnchorDotPainter extends CustomPainter {
  const _AnchorDotPainter(this.anchor, this.selected);

  final ui.UiAnchor anchor;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = Rect.fromLTWH(0, 0, size.width, size.height).deflate(5);
    canvas.drawCircle(
      Offset(
        inset.left + anchor.min.dx * inset.width,
        inset.top + anchor.min.dy * inset.height,
      ),
      2.5,
      Paint()..color = selected ? EditorTheme.primary : EditorTheme.textMuted,
    );
  }

  @override
  bool shouldRepaint(_AnchorDotPainter old) =>
      old.anchor != anchor || old.selected != selected;
}

/// Text a player will read.
///
/// Three things happen in here that a plain text box cannot do: the tag
/// buttons write the markup so nobody has to remember it, `{` offers what
/// the game has to read, and `@` says the text is a key into the current
/// language.
class UiTextEditorRow extends StatefulWidget {
  const UiTextEditorRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.bindings = const [],
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  /// What the game has registered, offered after a `{`.
  final List<String> bindings;

  @override
  State<UiTextEditorRow> createState() => _UiTextEditorRowState();
}

class _UiTextEditorRowState extends State<UiTextEditorRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  bool _open = false;

  /// The tags worth a button; the rest are typed.
  static const List<(String, String)> _tags = [
    ('B', 'b'),
    ('I', 'i'),
    ('Wave', 'wave'),
    ('Shake', 'shake'),
    ('Rainbow', 'rainbow'),
  ];

  @override
  void didUpdateWidget(UiTextEditorRow old) {
    super.didUpdateWidget(old);
    // Someone else changed it — an undo, a timeline. What is being typed
    // here is not thrown away for a value that has not moved.
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isKey => _controller.text.startsWith('@');

  /// Wraps what is selected in [tag], or drops an empty pair at the caret.
  void _wrap(String tag) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final inner = text.substring(start, end);
    final next =
        '${text.substring(0, start)}[$tag]$inner[/$tag]'
        '${text.substring(end)}';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + tag.length + 2),
    );
    widget.onChanged(next);
  }

  void _insert(String snippet) {
    final selection = _controller.selection;
    final text = _controller.text;
    final at = selection.isValid ? selection.start : text.length;
    final next = text.substring(0, at) + snippet + text.substring(at);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + snippet.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final asked = ui.UiBindings.namesIn(_controller.text);
    final unknown = [
      for (final name in asked)
        if (widget.bindings.isNotEmpty && !widget.bindings.contains(name)) name,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: InspectorField.labelWidth,
              // The label where every other row's is, the fold after it:
              // an arrow in front pushed this one label out of line.
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: InspectorField.labelStyle,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                style: InspectorField.valueStyle,
                decoration: InspectorField.decoration(),
                onChanged: (text) {
                  widget.onChanged(text);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: InspectorField.labelWidth),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final (label, tag) in _tags)
                  _TagButton(label: label, onTap: () => _wrap(tag)),
                _TagButton(
                  label: 'Colour',
                  onTap: () => _wrap('color=#ffcc00'),
                ),
                _TagButton(label: '↵', onTap: () => _insert('[br]')),
              ],
            ),
          ),
          if (widget.bindings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: InspectorField.labelWidth),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final name in widget.bindings)
                    _TagButton(
                      label: '{$name}',
                      onTap: () => _insert('{$name}'),
                    ),
                ],
              ),
            ),
          ],
        ],
        if (_isKey)
          _Note(
            'A key: the game looks "${_controller.text.substring(1)}" up in '
            'the current language.',
          ),
        for (final name in unknown)
          _Note('Nothing in the game reads {$name}.', warn: true),
      ],
    );
  }
}

/// A small button that writes a tag into the text.
class _TagButton extends StatelessWidget {
  const _TagButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: EditorTheme.inputBg,
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(InspectorField.radius),
      ),
      child: Text(label, style: InspectorField.labelStyle),
    ),
  );
}

/// A line under a field saying something about what was typed.
class _Note extends StatelessWidget {
  const _Note(this.message, {this.warn = false});

  final String message;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: InspectorField.labelWidth, top: 4),
    child: Text(
      message,
      style: InspectorField.labelStyle.copyWith(
        color: warn ? EditorTheme.warning : EditorTheme.textMuted,
      ),
    ),
  );
}
