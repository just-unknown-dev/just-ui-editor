/// What `[icon=name]` draws.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'ui_text_style.dart';

/// Draws one icon in a line of text, for a screen: an image, a widget of
/// the game's own. [size] is the font size of the text around it.
typedef UiIconWidgetBuilder = Widget Function(double size);

/// What `[icon=name]` draws.
///
/// A glyph from an icon font ([register]) works everywhere text does — in
/// a screen and on the game's canvas — since it is just another letter. A
/// widget ([registerWidget]) can be anything, a coin's sprite included,
/// but only a screen can show one: in world text it draws nothing.
///
/// ```dart
/// final icons = UiIcons.of(engine.context);
/// icons.register('heart', Icons.favorite);
/// icons.registerWidget('coin', (size) => Image.asset('assets/coin.png',
///     width: size, height: size));
/// ```
///
/// A name nobody registered draws nothing, and the editor's Problems dock
/// is where that shows. Kept on the engine's [EngineContext] ([of]), not in
/// a static, so two engines never draw each other's icons.
final class UiIcons {
  UiIcons._();

  static final Object _key = Object();

  /// [context]'s icons, made the first time they are asked for.
  static UiIcons of(EngineContext context) => context.slot(_key, UiIcons._);

  final Map<String, IconData> _glyphs = {};
  final Map<String, UiIconWidgetBuilder> _widgets = {};

  /// Makes `[icon=name]` draw [icon], in the colour and size of the text
  /// around it.
  void register(String name, IconData icon) {
    _widgets.remove(name);
    _glyphs[name] = icon;
  }

  /// Makes `[icon=name]` draw what [build] makes, in a screen.
  void registerWidget(String name, UiIconWidgetBuilder build) {
    _glyphs.remove(name);
    _widgets[name] = build;
  }

  /// Forgets [name].
  void unregister(String name) {
    _glyphs.remove(name);
    _widgets.remove(name);
  }

  /// Whether [name] draws something.
  bool has(String name) =>
      _glyphs.containsKey(name) || _widgets.containsKey(name);

  /// Every name registered, for an editor to offer.
  List<String> get names => [..._glyphs.keys, ..._widgets.keys]..sort();

  /// Forgets every icon.
  void clear() {
    _glyphs.clear();
    _widgets.clear();
  }

  /// The run [name] draws as, in [style]; null when nothing can be drawn
  /// here — no such icon, or a widget where [widgets] is false.
  InlineSpan? spanFor(
    String name,
    UiTextStyle style, {
    bool widgets = true,
    Paint? foreground,
  }) {
    final glyph = _glyphs[name];
    if (glyph != null) {
      final look = style.toTextStyle().copyWith(
        fontFamily: glyph.fontFamily,
        package: glyph.fontPackage,
        fontFamilyFallback: glyph.fontFamilyFallback,
      );
      return TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: foreground == null
            ? look
            : look.copyWith(foreground: foreground, shadows: const []),
      );
    }
    final build = _widgets[name];
    if (build == null || !widgets) return null;
    final size = style.over(UiTextStyle.fallback).effectiveSize;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox.square(dimension: size, child: build(size)),
    );
  }
}
