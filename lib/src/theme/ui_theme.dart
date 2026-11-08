/// One look for a game's UI, saved as `.uitheme.json`.
///
/// A widget names a *role* — "title", "primary" — rather than a colour, so
/// restyling a game is one file rather than every entity in every scene.
/// The Flutter layer turns this into a real `ThemeData`; the canvas
/// painters read it directly.
library;

import 'dart:convert';
import 'package:flutter/material.dart';

import '../text/text.dart';

/// The colours a theme names.
///
/// These are roles, not shades: `primary` is "the colour this game acts
/// with", whatever that turns out to be.
class UiPalette {
  const UiPalette({
    this.primary = const Color(0xFF4E8CFF),
    this.onPrimary = const Color(0xFFFFFFFF),
    this.surface = const Color(0xCC101820),
    this.onSurface = const Color(0xFFF2F5F8),
    this.accent = const Color(0xFFFFC53D),
    this.danger = const Color(0xFFE5484D),
    this.success = const Color(0xFF3DD68C),
    this.muted = const Color(0xFF8A94A6),
    this.outline = const Color(0x33FFFFFF),
  });

  final Color primary;
  final Color onPrimary;
  final Color surface;
  final Color onSurface;
  final Color accent;
  final Color danger;
  final Color success;
  final Color muted;
  final Color outline;

  /// The colour a role names, or null when the name means nothing here.
  Color? byName(String role) => switch (role) {
    'primary' => primary,
    'onPrimary' => onPrimary,
    'surface' => surface,
    'onSurface' => onSurface,
    'accent' => accent,
    'danger' => danger,
    'success' => success,
    'muted' => muted,
    'outline' => outline,
    _ => null,
  };

  static const List<String> roles = [
    'primary',
    'onPrimary',
    'surface',
    'onSurface',
    'accent',
    'danger',
    'success',
    'muted',
    'outline',
  ];

  UiPalette copyWith({
    Color? primary,
    Color? onPrimary,
    Color? surface,
    Color? onSurface,
    Color? accent,
    Color? danger,
    Color? success,
    Color? muted,
    Color? outline,
  }) => UiPalette(
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    surface: surface ?? this.surface,
    onSurface: onSurface ?? this.onSurface,
    accent: accent ?? this.accent,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    muted: muted ?? this.muted,
    outline: outline ?? this.outline,
  );

  Map<String, dynamic> toJson() => {
    for (final role in roles) role: byName(role)!.toARGB32(),
  };

  factory UiPalette.fromJson(Map<String, dynamic> json) {
    Color read(String key, Color fallback) =>
        json[key] is num ? Color((json[key] as num).toInt()) : fallback;
    const base = UiPalette();
    return UiPalette(
      primary: read('primary', base.primary),
      onPrimary: read('onPrimary', base.onPrimary),
      surface: read('surface', base.surface),
      onSurface: read('onSurface', base.onSurface),
      accent: read('accent', base.accent),
      danger: read('danger', base.danger),
      success: read('success', base.success),
      muted: read('muted', base.muted),
      outline: read('outline', base.outline),
    );
  }
}

/// Sounds the UI makes.
class UiSounds {
  const UiSounds({this.hover = '', this.press = '', this.toggle = ''});

  final String hover;
  final String press;
  final String toggle;

  Map<String, dynamic> toJson() => {
    if (hover.isNotEmpty) 'hover': hover,
    if (press.isNotEmpty) 'press': press,
    if (toggle.isNotEmpty) 'toggle': toggle,
  };

  factory UiSounds.fromJson(Map<String, dynamic> json) => UiSounds(
    hover: json['hover'] as String? ?? '',
    press: json['press'] as String? ?? '',
    toggle: json['toggle'] as String? ?? '',
  );
}

/// One look for an interface: a palette of colour roles, text styles by
/// role, the default radius and spacing, and the sounds it makes. Saved
/// as `.uitheme.json`; never changes once made (see [copyWith]).
class UiTheme {
  const UiTheme({
    this.name = '',
    this.palette = const UiPalette(),
    this.textStyles = const {},
    this.radius = 8,
    this.spacing = 8,
    this.sounds = const UiSounds(),
  });

  /// What a game gets before it says otherwise.
  static const UiTheme fallback = UiTheme(name: 'default');

  static const int formatVersion = 1;
  static const String fileExtension = 'uitheme.json';

  final String name;
  final UiPalette palette;

  /// Named text styles — `body`, `title`, `button`, `caption`, and whatever
  /// else a game names. A text component asks for one by role.
  final Map<String, UiTextStyle> textStyles;

  /// How round a panel or a button is by default.
  final double radius;

  /// The gap a container leaves between children by default.
  final double spacing;

  final UiSounds sounds;

  /// The roles every theme is expected to carry, so an editor can offer
  /// them even in a theme that has not named them yet.
  static const List<String> textRoles = [
    'body',
    'title',
    'heading',
    'button',
    'caption',
    'value',
  ];

  /// The style a role names, over what that role looks like by default,
  /// over the game's font.
  ///
  /// Only the *font* carries across from `body`: a theme that sets body to
  /// 14pt Inter should give a title Inter at a title's size, not a title at
  /// body size. Everything else a role wants, it says.
  ///
  /// Worked out once per role and kept with this theme (which never
  /// changes): world text asks every frame.
  UiTextStyle textStyle(String role) {
    final known = (_roleStyles[this] ??= {});
    return known[role] ??= () {
      final font = UiTextStyle(family: textStyles['body']?.family);
      final own = textStyles[role] ?? const UiTextStyle();
      return own.over(_roleDefault(role)).over(font);
    }();
  }

  /// Each theme's [textStyle]s, by role, as worked out so far.
  static final Expando<Map<String, UiTextStyle>> _roleStyles = Expando(
    'uiThemeRoleStyles',
  );

  /// What a role looks like when a theme says nothing about it: sizes and
  /// weights that read as a title, a caption, a button.
  UiTextStyle _roleDefault(String role) => switch (role) {
    'title' => UiTextStyle(
      size: 32,
      weight: FontWeight.w700,
      color: palette.onSurface,
    ),
    'heading' => UiTextStyle(
      size: 22,
      weight: FontWeight.w600,
      color: palette.onSurface,
    ),
    'button' => UiTextStyle(
      size: 16,
      weight: FontWeight.w600,
      color: palette.onPrimary,
    ),
    'caption' => UiTextStyle(size: 12, color: palette.muted),
    'value' => UiTextStyle(
      size: 18,
      weight: FontWeight.w700,
      color: palette.accent,
    ),
    _ => UiTextStyle(size: 16, color: palette.onSurface),
  };

  /// A colour by role, or [fallbackColor] when the name means nothing.
  Color color(String role, {Color fallbackColor = const Color(0xFFFFFFFF)}) =>
      palette.byName(role) ?? fallbackColor;

  /// What the Flutter layer themes its widgets with, so stock widgets and
  /// a game's own both follow the theme.
  ///
  /// Made once per theme: a `ThemeData` is costly to build, and a canvas
  /// asks for one every time it is built.
  ThemeData toThemeData() => _themeData[this] ??= _makeThemeData();

  static final Expando<ThemeData> _themeData = Expando('uiThemeData');

  ThemeData _makeThemeData() {
    final scheme = ColorScheme.dark(
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      secondary: palette.accent,
      onSecondary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.onSurface,
      error: palette.danger,
    );
    final body = textStyle('body').toTextStyle();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: textStyle('body').family,
      textTheme: TextTheme(
        displayLarge: textStyle('title').toTextStyle(),
        headlineMedium: textStyle('heading').toTextStyle(),
        bodyMedium: body,
        labelLarge: textStyle('button').toTextStyle(),
        bodySmall: textStyle('caption').toTextStyle(),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.primary,
        inactiveTrackColor: palette.outline,
        thumbColor: palette.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
          textStyle: textStyle('button').toTextStyle(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: palette.outline),
        ),
      ),
    );
  }

  UiTheme copyWith({
    String? name,
    UiPalette? palette,
    Map<String, UiTextStyle>? textStyles,
    double? radius,
    double? spacing,
    UiSounds? sounds,
  }) => UiTheme(
    name: name ?? this.name,
    palette: palette ?? this.palette,
    textStyles: textStyles ?? this.textStyles,
    radius: radius ?? this.radius,
    spacing: spacing ?? this.spacing,
    sounds: sounds ?? this.sounds,
  );

  Map<String, dynamic> toJson() => {
    'formatVersion': formatVersion,
    if (name.isNotEmpty) 'name': name,
    'palette': palette.toJson(),
    'textStyles': {
      for (final entry in textStyles.entries) entry.key: entry.value.toJson(),
    },
    'radius': radius,
    'spacing': spacing,
    if (sounds.toJson().isNotEmpty) 'sounds': sounds.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory UiTheme.fromJson(Map<String, dynamic> json) => UiTheme(
    name: json['name'] as String? ?? '',
    palette: json['palette'] is Map
        ? UiPalette.fromJson((json['palette'] as Map).cast<String, dynamic>())
        : const UiPalette(),
    textStyles: {
      if (json['textStyles'] is Map)
        for (final entry in (json['textStyles'] as Map).entries)
          if (entry.value is Map)
            '${entry.key}': UiTextStyle.fromJson(
              (entry.value as Map).cast<String, dynamic>(),
            ),
    },
    radius: (json['radius'] as num?)?.toDouble() ?? 8,
    spacing: (json['spacing'] as num?)?.toDouble() ?? 8,
    sounds: json['sounds'] is Map
        ? UiSounds.fromJson((json['sounds'] as Map).cast<String, dynamic>())
        : const UiSounds(),
  );

  static UiTheme parse(String source) =>
      UiTheme.fromJson((jsonDecode(source) as Map).cast());
}
