// What each kind of element becomes: containers, controls, panels,
// text, buttons, pictures and bars.
part of 'ui_layer.dart';

/// The builders [UiLayerState] makes each entity's own widget with.
extension _UiElementBuilders on UiLayerState {
  /// The entity's own element, before its slot and its panel.
  Widget _content(Entity entity, UiTheme theme) {
    final children = _childrenOf(entity);
    final layout = entity.getComponent<UiLayoutComponent>();
    // A stack places its own; for the rest, a child's flex means something
    // only in a row or a column.
    final built = layout?.kind == UiLayoutKind.stack
        ? const <Widget>[]
        : [
            for (final child in children)
              _flow(child, theme, inFlex: layout?.kind.isFlex ?? false),
          ];

    final custom = entity.getComponent<UiCustomComponent>();
    if (custom != null) {
      return UiWidgets.of(widget.world.context).build(
            UiBuildContext(
              entity: entity,
              world: widget.world,
              theme: theme,
              children: built,
              localize: widget.localize,
              gameWorld: widget.gameWorld,
              host: _host,
            ),
          ) ??
          const SizedBox.shrink();
    }

    if (layout != null) return _layout(layout, theme, built, entity);

    final text = entity.getComponent<UiTextComponent>();
    if (text != null) return _text(entity, text, theme);

    final button = entity.getComponent<UiButtonComponent>();
    if (button != null) return _button(entity, button, theme, built);

    final image = entity.getComponent<UiImageComponent>();
    if (image != null) return _image(image);

    final progress = entity.getComponent<UiProgressComponent>();
    if (progress != null) return _progress(entity, progress, theme);

    final toggle = entity.getComponent<UiToggleComponent>();
    if (toggle != null) return _toggle(entity, toggle, theme);

    final slider = entity.getComponent<UiSliderComponent>();
    if (slider != null) return _slider(entity, slider, theme);

    final field = entity.getComponent<UiTextFieldComponent>();
    if (field != null) return _textField(entity, field, theme);

    final dropdown = entity.getComponent<UiDropdownComponent>();
    if (dropdown != null) return _dropdown(entity, dropdown, theme);

    final spacer = entity.getComponent<UiSpacerComponent>();
    if (spacer != null) {
      // Taking what is left only means something in a row or a column.
      return spacer.expand && _inFlex(entity)
          ? const Spacer()
          : SizedBox(width: spacer.size, height: spacer.size);
    }

    // A bare entity with children is a plain box holding them.
    if (built.isEmpty) return const SizedBox.shrink();
    return built.length == 1 ? built.first : Stack(children: built);
  }

  /// Whether [entity] sits in a row or a column.
  bool _inFlex(Entity entity) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : widget.world.getEntity(parentId);
    return parent?.getComponent<UiLayoutComponent>()?.kind.isFlex ?? false;
  }

  /// A child inside a row, a column or another container — with its flex
  /// (in a row or a column; anywhere else its slot's size) and alignment
  /// applied.
  Widget _flow(Entity entity, UiTheme theme, {required bool inFlex}) {
    final slot = entity.getComponent<UiSlotComponent>();
    final built = buildEntity(entity, theme);
    if (slot == null) return built;
    if (slot.mode == UiSlotMode.anchored) {
      // An anchored child of a flow container keeps the size its slot asks
      // for; the stack case is handled by the container itself.
      return SizedBox(
        width: slot.size.width,
        height: slot.size.height,
        child: built,
      );
    }
    if (slot.flex > 0 && inFlex) {
      return Expanded(flex: slot.flex, child: built);
    }
    // The size the slot says — which the inspector shows and the handles
    // drag — and not whatever the content happens to want. A parent that
    // stretches its children, or `alignSelf: stretch`, still wins across.
    return SizedBox(
      width: slot.size.width,
      height: slot.size.height,
      child: built,
    );
  }

  Widget _layout(
    UiLayoutComponent layout,
    UiTheme theme,
    List<Widget> children,
    Entity entity,
  ) {
    if (layout.kind == UiLayoutKind.row || layout.kind == UiLayoutKind.column) {
      children = _alignedSelf(
        children,
        _childrenOf(entity),
        across: layout.kind == UiLayoutKind.row
            ? Axis.vertical
            : Axis.horizontal,
      );
    }
    final spaced = _spaced(children, layout);
    Widget result;
    switch (layout.kind) {
      case UiLayoutKind.row:
        result = Row(
          mainAxisAlignment: layout.mainAxis.main,
          crossAxisAlignment: layout.crossAxis.cross,
          mainAxisSize: layout.tight ? MainAxisSize.min : MainAxisSize.max,
          children: spaced,
        );
      case UiLayoutKind.column:
        result = Column(
          mainAxisAlignment: layout.mainAxis.main,
          crossAxisAlignment: layout.crossAxis.cross,
          mainAxisSize: layout.tight ? MainAxisSize.min : MainAxisSize.max,
          children: spaced,
        );
      case UiLayoutKind.stack:
        result = Stack(
          children: [
            for (final child in _childrenOf(entity)) _stacked(child, theme),
          ],
        );
      case UiLayoutKind.wrap:
        result = Wrap(
          spacing: layout.spacing,
          runSpacing: layout.spacing,
          children: children,
        );
      case UiLayoutKind.grid:
        result = GridView.count(
          crossAxisCount: layout.columns < 1 ? 1 : layout.columns,
          mainAxisSpacing: layout.spacing,
          crossAxisSpacing: layout.spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      case UiLayoutKind.scroll:
        result = SingleChildScrollView(
          child: Column(
            crossAxisAlignment: layout.crossAxis.cross,
            mainAxisSize: MainAxisSize.min,
            children: spaced,
          ),
        );
      case UiLayoutKind.safeArea:
        result = SafeArea(
          child: children.isEmpty
              ? const SizedBox.shrink()
              : children.length == 1
              ? children.first
              : Column(mainAxisSize: MainAxisSize.min, children: spaced),
        );
    }
    if (layout.padding != EdgeInsets.zero) {
      result = Padding(padding: layout.padding, child: result);
    }
    return result;
  }

  /// A child of a stack container, placed by its anchors — by the same
  /// rule as a child of the canvas, pivot and all.
  ///
  /// It used to align on the anchor's corner and ignore the pivot, so the
  /// same slot put a button in two different places depending on whether
  /// it sat in the canvas or in a stack inside it.
  Widget _stacked(Entity entity, UiTheme theme) {
    final slot = entity.getComponent<UiSlotComponent>();
    if (slot != null && !slot.visible) return UiLayerState._nowhere;
    final built = buildEntity(entity, theme);
    if (slot == null || slot.mode != UiSlotMode.anchored) return built;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned.fromRect(rect: slot.rectIn(box.biggest), child: built),
          ],
        ),
      ),
    );
  }

  /// [built] with each child's own `alignSelf` applied across the parent's
  /// direction — the one place a child may sit differently from its
  /// siblings.
  List<Widget> _alignedSelf(
    List<Widget> built,
    List<Entity> entities, {
    required Axis across,
  }) {
    if (built.length != entities.length) return built;
    return [
      for (var i = 0; i < built.length; i++)
        switch (entities[i].getComponent<UiSlotComponent>()?.crossAlignment) {
          null || CrossAxisAlignment.baseline => built[i],
          CrossAxisAlignment.stretch =>
            across == Axis.horizontal
                ? SizedBox(width: double.infinity, child: built[i])
                : SizedBox(height: double.infinity, child: built[i]),
          final align => Align(
            alignment: _alignmentAcross(align, across),
            child: built[i],
          ),
        },
    ];
  }

  static Alignment _alignmentAcross(CrossAxisAlignment align, Axis across) {
    final t = switch (align) {
      CrossAxisAlignment.start => -1.0,
      CrossAxisAlignment.end => 1.0,
      _ => 0.0,
    };
    return across == Axis.horizontal ? Alignment(t, 0) : Alignment(0, t);
  }

  /// [children] with the container's gap between them.
  List<Widget> _spaced(List<Widget> children, UiLayoutComponent layout) {
    if (layout.spacing <= 0 || children.length < 2) return children;
    final gap = layout.kind == UiLayoutKind.row
        ? SizedBox(width: layout.spacing)
        : SizedBox(height: layout.spacing);
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) gap,
        children[i],
      ],
    ];
  }

  // ── Controls ────────────────────────────────────────────────────────────

  /// Runs what an element was told to do, with [value] as what changed.
  void _run(Entity entity, UiActionList actions, {Object? value}) {
    if (actions.isEmpty) return;
    actions.run(_context(entity, value: value));
    markDirty();
  }

  void _sound(String path) {
    if (path.isNotEmpty) widget.onSound?.call(path);
  }

  /// Whether [entity] is the one its screen wants focused when it opens.
  ///
  /// Walked up rather than handed down, because a node is built by its own
  /// listener long after its canvas was.
  bool _takesInitialFocus(Entity entity) {
    final name = entity.name;
    if (name == null || name.isEmpty) return false;
    var current = entity;
    // A UI tree deeper than this is a mistake, not a use case.
    for (var step = 0; step < 32; step++) {
      final parentId = current.getComponent<ParentComponent>()?.parentId;
      if (parentId == null) return false;
      final parent = widget.world.getEntity(parentId);
      if (parent == null) return false;
      final canvas = parent.getComponent<UiCanvasComponent>();
      if (canvas != null) return canvas.initialFocus == name;
      current = parent;
    }
    return false;
  }

  /// Rings [child] while it has the focus, in the theme's `primary` — the
  /// colour the game acts with — and plays the theme's hover sound as the
  /// focus arrives: walking a menu with a pad or the keyboard is seen from
  /// across a room, and sounds like moving a pointer over it. The ring
  /// follows corners [radius] round, the theme's radius when null.
  Widget _focusRing(UiTheme theme, Widget child, {double? radius}) =>
      _UiFocusRing(
        color: theme.palette.primary,
        radius: radius ?? theme.radius,
        onFocused: () => _sound(theme.sounds.hover),
        child: child,
      );

  Widget _toggle(Entity entity, UiToggleComponent toggle, UiTheme theme) {
    final value = toggle.binding.isEmpty
        ? toggle.value
        : (_bindings.readNumber(toggle.binding, self: entity) ?? 0) != 0;
    final control = Switch(
      value: value,
      autofocus: _takesInitialFocus(entity),
      onChanged: (next) {
        toggle.value = next;
        _sound(theme.sounds.toggle);
        _run(entity, toggle.onChanged, value: next);
        _refresh(entity);
      },
    );
    if (toggle.label.isEmpty) return _focusRing(theme, control);
    return _focusRing(
      theme,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _words(toggle.label, entity),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          control,
        ],
      ),
    );
  }

  Widget _slider(Entity entity, UiSliderComponent slider, UiTheme theme) {
    // A range saved the wrong way round is read the right way round; one
    // that is not a range at all is 0–1, and one with no width is shown
    // but cannot be slid.
    var low = slider.min, high = slider.max;
    if (!low.isFinite || !high.isFinite) (low, high) = (0.0, 1.0);
    if (low > high) (low, high) = (high, low);
    final read = slider.binding.isEmpty
        ? slider.value
        : (_bindings.readNumber(slider.binding, self: entity) ?? slider.value);
    final value = read.isNaN ? low : read.clamp(low, high).toDouble();
    final label = _words(slider.label, entity);
    final slides = high > low;
    return _focusRing(
      theme,
      Slider(
        value: value,
        min: low,
        max: high,
        divisions: slider.steps > 0 && slides ? slider.steps : null,
        autofocus: _takesInitialFocus(entity),
        label: label.isEmpty ? null : label,
        onChanged: slides
            ? (next) {
                slider.value = next;
                _run(entity, slider.onChanged, value: next);
                _refresh(entity);
              }
            : null,
      ),
    );
  }

  Widget _textField(Entity entity, UiTextFieldComponent field, UiTheme theme) {
    // The controller outlives the widget, so a rebuild half-way through a
    // word does not swallow what has been typed or move the caret.
    final controller = _fields.putIfAbsent(
      entity.id,
      () => TextEditingController(text: field.value),
    );
    if (controller.text != field.value) {
      controller.value = TextEditingValue(
        text: field.value,
        selection: TextSelection.collapsed(offset: field.value.length),
      );
    }
    return _focusRing(
      theme,
      TextField(
        controller: controller,
        autofocus: _takesInitialFocus(entity),
        obscureText: field.obscure,
        maxLength: field.maxLength > 0 ? field.maxLength : null,
        decoration: InputDecoration(
          hintText: field.hint.isEmpty ? null : _words(field.hint, entity),
          counterText: '',
        ),
        onChanged: (next) {
          field.value = next;
          _run(entity, field.onChanged, value: next);
        },
        onSubmitted: (next) {
          field.value = next;
          _run(entity, field.onSubmitted, value: next);
        },
      ),
    );
  }

  Widget _dropdown(Entity entity, UiDropdownComponent dropdown, UiTheme theme) {
    // One of each: a menu shows a choice once, and Flutter refuses two.
    final options = {...dropdown.options}.toList();
    if (options.isEmpty) options.add(dropdown.value);
    final value = options.contains(dropdown.value)
        ? dropdown.value
        : options.first;
    return _focusRing(
      theme,
      DropdownButton<String>(
        value: value,
        isExpanded: true,
        autofocus: _takesInitialFocus(entity),
        hint: dropdown.label.isEmpty
            ? null
            : Text(_words(dropdown.label, entity)),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (next) {
          if (next == null) return;
          dropdown.value = next;
          _sound(theme.sounds.press);
          _run(entity, dropdown.onChanged, value: next);
          _refresh(entity);
        },
      ),
    );
  }

  /// A panel, bottom up: its shadow, its fill — a colour, a gradient or a
  /// picture — then its edge, then what it holds.
  Widget _panel(UiPanelComponent panel, UiTheme theme, Widget child) {
    final radius = BorderRadius.circular(panel.radius);
    final colors = panel.gradient;
    final swept = colors != null && colors.length > 1;
    final pictured = panel.image.isNotEmpty;
    final border = panel.borderWidth > 0
        ? Border.all(
            color: panel.borderColorUnder(theme),
            width: panel.borderWidth,
          )
        : null;
    if (pictured && border != null) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(borderRadius: radius, border: border),
        child: child,
      );
    }
    if (pictured) {
      child = _UiPanelImage(
        path: panel.image,
        nineSlice: panel.nineSlice,
        radius: panel.radius,
        child: child,
      );
    }
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: swept || pictured ? null : panel.colorUnder(theme),
        gradient: swept ? LinearGradient(colors: colors) : null,
        borderRadius: radius,
        border: pictured ? null : border,
        boxShadow: panel.shadowBlur > 0
            ? [
                BoxShadow(
                  color: const Color(0x66000000),
                  blurRadius: panel.shadowBlur,
                  offset: Offset(0, panel.shadowBlur / 3),
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (panel.blur > 0) {
      result = ClipRRect(
        borderRadius: BorderRadius.circular(panel.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: panel.blur, sigmaY: panel.blur),
          child: result,
        ),
      );
    }
    return result;
  }

  /// A text: Flutter's own `Text` where it can — icons as widgets, links
  /// tappable — and the canvas painter where only the painter can: moving
  /// and colour-cycling letters, an outline, a gradient, or shrinking to
  /// fit. A painted text's links cannot be tapped.
  Widget _text(Entity entity, UiTextComponent text, UiTheme theme) {
    final resolved = text.resolve(
      _bindings,
      self: entity,
      localize: widget.localize,
    );
    final shown = text.revealSpeed > 0
        ? resolved.take(text.revealed.floor())
        : resolved;
    final style = text.styleUnder(theme);
    final alignment = switch (text.align) {
      UiTextAlign.left => Alignment.centerLeft,
      UiTextAlign.right => Alignment.centerRight,
      _ => Alignment.center,
    };
    final look = style.over(UiTextStyle.fallback);
    final painted =
        shown.needsPainter ||
        (look.gradient?.length ?? 0) > 1 ||
        (look.outline?.isVisible ?? false) ||
        text.overflow == UiTextOverflow.shrink;
    if (painted) {
      Widget drawn = _UiPaintedText(
        text: shown,
        icons: _icons,
        style: style,
        align: text.align,
        overflow: text.overflow,
        maxLines: text.maxLines,
        minSize: text.minFontSize,
      );
      if (text.overflow == UiTextOverflow.clip) drawn = ClipRect(child: drawn);
      return Align(alignment: alignment, child: drawn);
    }
    return Align(
      alignment: alignment,
      child: Text.rich(
        shown.toTextSpan(
          style,
          icons: _icons,
          widgets: true,
          recognizerFor: _linksFor(entity),
        ),
        textAlign: text.align.flutter,
        maxLines: text.maxLines,
        overflow: text.overflow.flutter,
      ),
    );
  }

  /// Makes what [entity]'s `[link=…]` runs are tapped with, letting go of
  /// the ones its last build made.
  GestureRecognizer? Function(UiTextSpan span) _linksFor(Entity entity) {
    for (final old in _links.remove(entity.id) ?? const []) {
      old.dispose();
    }
    return (span) {
      final link = span.link;
      if (link == null || link.isEmpty) return null;
      final recognizer = TapGestureRecognizer()
        ..onTap = () =>
            _run(entity, UiActionList([UiActions.linkAction(link)]));
      (_links[entity.id] ??= []).add(recognizer);
      return recognizer;
    };
  }

  Widget _button(
    Entity entity,
    UiButtonComponent button,
    UiTheme theme,
    List<Widget> children,
  ) {
    final label = UiRichText.parse(_words(button.label, entity));
    return _focusRing(
      theme,
      FilledButton(
        autofocus: _takesInitialFocus(entity),
        onPressed: button.isInteractive
            ? () {
                _sound(theme.sounds.press);
                button.press(_context(entity));
                markDirty();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor:
              button.color ??
              theme.color(
                button.colorRole,
                fallbackColor: theme.palette.primary,
              ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(button.borderRadius),
            side: button.borderColor == null
                ? BorderSide.none
                : BorderSide(color: button.borderColor!),
          ),
        ),
        child: children.isNotEmpty
            ? (children.length == 1 ? children.first : Row(children: children))
            : Text.rich(
                label.toTextSpan(
                  button.labelStyleUnder(theme),
                  icons: _icons,
                  widgets: true,
                ),
              ),
      ),
      radius: button.borderRadius,
    );
  }

  Widget _image(UiImageComponent image) {
    if (image.path.isEmpty) return const SizedBox.shrink();
    Widget result = image.atlasRegion.isNotEmpty
        // One region of an atlas, trimmed and turned frames put back.
        ? _UiAtlasImage(
            sprites: widget.world.context.sprites,
            path: image.path,
            region: image.atlasRegion,
            fit: image.fit,
            tint: image.tint,
          )
        : Image.asset(
            image.path,
            fit: image.fit,
            color: image.tint,
            colorBlendMode: image.tint == null ? null : BlendMode.modulate,
            // A picture that is not there must not take the interface down.
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          );
    if (image.opacity < 1) {
      result = Opacity(opacity: image.opacity.clamp(0.0, 1.0), child: result);
    }
    return result;
  }

  Widget _progress(Entity entity, UiProgressComponent bar, UiTheme theme) {
    final value = UiLayerState._progressValue(_bindings, entity, bar);
    final color = bar.colorUnder(theme);
    final track = bar.trackColorUnder(theme);
    if (bar.radial) {
      return CircularProgressIndicator(
        value: value.toDouble(),
        color: color,
        backgroundColor: track,
        strokeWidth: bar.thickness,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(bar.radius),
      child: LinearProgressIndicator(
        value: value.toDouble(),
        color: color,
        backgroundColor: track,
        minHeight: bar.thickness,
      ),
    );
  }
}
