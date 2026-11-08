/// Text in the world, drawn on the game's canvas.
library;

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:meta/meta.dart';

import '../bindings/bindings.dart';
import '../text/text.dart';
import '../theme/theme.dart';
import 'ui_element_component.dart';

/// A piece of text at an entity's transform: a sign, a name over a head, a
/// number that floats up and fades.
///
/// What it says may be written out, read from the game (`"Coins: {coins}"`),
/// or looked up in the current language (`"@hud.coins"`) — and it may carry
/// tags: `"Press [b]Space[/b]"`.
class UiTextComponent extends UiElementComponent {
  UiTextComponent({
    required this._text,
    this._style = const UiTextStyle(),
    this.styleRole = 'body',
    this.align = UiTextAlign.center,
    this.overflow = UiTextOverflow.visible,
    this.wrap = false,
    this.maxLines,
    this.minFontSize = 8,
    this.revealSpeed = 0,
    super.size = const Size(200, 40),
    super.visible,
    super.enabled = false,
    super.layer,
  });

  String _text;
  UiTextStyle _style;

  /// What is written in the scene, tags and all.
  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _resolvedFrom = null;
    markDirty();
  }

  /// How it looks. Anything left unset comes from [styleRole] in the theme.
  UiTextStyle get style => _style;
  set style(UiTextStyle value) {
    if (value == _style) return;
    _style = value;
    markDirty();
  }

  /// The theme role underneath [style] — `body`, `title`, `caption`.
  String styleRole;

  UiTextAlign align;
  UiTextOverflow overflow;

  /// Whether text wraps at the component's width. Without it, text runs on
  /// as far as it likes and [size] is only what the editor draws.
  bool wrap;

  int? maxLines;

  /// How small [UiTextOverflow.shrink] may go.
  double minFontSize;

  /// Characters a second, for text that types itself out. Zero shows it all
  /// at once.
  double revealSpeed;

  // ── Runtime ──────────────────────────────────────────────────────────────

  /// How much of it has been revealed, in characters.
  double revealed = 0;

  /// Seconds this text has been on screen, for the moving effects.
  double elapsed = 0;

  /// The text with its bindings filled in and its tags parsed. Kept until
  /// something it was made from changes — laying text out is the expensive
  /// part of drawing it.
  UiRichText? _parsed;
  String? _resolvedFrom;
  int _revision = 0;

  /// Bumped whenever something that changes how this looks is set. The
  /// screen-side UI watches this to know when to rebuild one node.
  int get revision => _revision;

  /// Marks it changed: the screens rebuild its node, and it is parsed and
  /// styled again.
  void markDirty() {
    _revision++;
    _parsed = null;
    _under = null;
  }

  /// What [resolve] last made, or null when something it is made from has
  /// changed since. A system that resolves every text each frame
  /// (`UiTextSystem`) leaves this current for whoever draws it next, as of
  /// [resolvedIn].
  UiRichText? get resolved => _parsed;

  /// The world update ([World.updateCount]) in which a `UiTextSystem` last
  /// resolved it; -1 before one has. [resolved] is the game as of then: a
  /// binding that reads something new since shows only once the text is
  /// resolved again. Run time only, never saved.
  int resolvedIn = -1;

  /// Everything resolved: bindings filled in through [bindings] (the
  /// engine's, `UiBindings.of`), language applied, tags read.
  ///
  /// [self] is the entity it belongs to, for `{self.health}`. [localize]
  /// turns `@a.key` into words; without it the key shows, which is what an
  /// editor wants to see.
  UiRichText resolve(
    UiBindings bindings, {
    Entity? self,
    String Function(String key)? localize,
  }) {
    final source = bindings.resolveText(_text, self: self, localize: localize);
    if (_parsed != null && _resolvedFrom == source) return _parsed!;
    _resolvedFrom = source;
    return _parsed = UiRichText.parse(source);
  }

  /// Whether this text is still typing itself out.
  bool get isRevealing =>
      revealSpeed > 0 && _parsed != null && revealed < _parsed!.length;

  /// Shows the whole of it at once.
  void revealAll() => revealed = double.maxFinite;

  /// Types it again from the start.
  void restartReveal() => revealed = 0;

  /// How this text is laid out, for a painter.
  UiTextLayout layoutFor() => UiTextLayout(
    align: align,
    overflow: overflow,
    maxWidth: wrap ? size.width : null,
    maxHeight: size.height,
    maxLines: maxLines,
    minSize: minFontSize,
  );

  /// The style to draw with, under [theme].
  ///
  /// Kept until the theme, the role or the style changes: world text asks
  /// every frame.
  UiTextStyle styleUnder(UiTheme theme) {
    final kept = _under;
    if (kept != null &&
        identical(_underTheme, theme) &&
        _underRole == styleRole) {
      return kept;
    }
    _underTheme = theme;
    _underRole = styleRole;
    return _under = _style.over(theme.textStyle(styleRole));
  }

  UiTextStyle? _under;
  UiTheme? _underTheme;
  String? _underRole;

  /// What draws it on the game's canvas: made by the world's painter the
  /// first time it is drawn, and let go of when the component leaves its
  /// entity (destroyed, or its world disposed).
  @internal
  UiTextPainter? painter;

  @override
  void onDetach(EntityId entityId) {
    painter?.dispose();
    painter = null;
    super.onDetach(entityId);
  }

  @override
  String toString() => 'Text("$_text")';
}
