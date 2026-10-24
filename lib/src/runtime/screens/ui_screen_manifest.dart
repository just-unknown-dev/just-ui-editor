/// A game's list of screens.
library;

import 'dart:convert';

/// Every screen a game has, in `assets/ui/screens.json`:
///
/// ```json
/// {
///   "format": 1,
///   "theme": "assets/ui/default.uitheme.json",
///   "screens": [
///     {"path": "assets/ui/hud.ui.json", "startOpen": true},
///     {"path": "assets/ui/pause.ui.json"}
///   ]
/// }
/// ```
///
/// All of them load once, when the game starts, and stay across levels —
/// a pause menu is the game's, not a level's. A screen that starts open
/// (a HUD) shows from the first frame; the rest wait to be opened by name.
///
/// What else the file holds — a key a newer tool writes, a note of the
/// game's own — is kept as it was ([extra]) and written back with it.
class UiScreenManifest {
  UiScreenManifest({
    this.theme,
    List<UiScreenEntry> screens = const [],
    Map<String, dynamic> extra = const {},
  }) : screens = List.unmodifiable(screens),
       extra = Map.unmodifiable(extra);

  /// Where a game keeps its list, unless it says otherwise.
  static const String defaultPath = 'assets/ui/screens.json';

  static const int currentFormat = 1;

  /// The theme a screen that names none is drawn with, if any.
  final String? theme;

  final List<UiScreenEntry> screens;

  /// The keys of the file this list does not read, as they were.
  final Map<String, dynamic> extra;

  static const Set<String> _known = {'format', 'theme', 'screens'};

  /// Reads a screen list. A newer format, or a value of the wrong kind,
  /// is a [FormatException] that says which.
  factory UiScreenManifest.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format'];
    if (rawFormat != null && rawFormat is! num) {
      throw FormatException(
        'The screen list\'s "format" is $rawFormat, not a number.',
      );
    }
    final format = (rawFormat as num?)?.toInt() ?? currentFormat;
    if (format > currentFormat) {
      throw FormatException(
        'This screen list was saved by a newer version (format $format).',
      );
    }
    final theme = json['theme'];
    if (theme != null && theme is! String) {
      throw FormatException(
        'The screen list\'s "theme" is $theme, not a path.',
      );
    }
    final screens = json['screens'];
    if (screens != null && screens is! List) {
      throw const FormatException(
        'The screen list\'s "screens" is not a list.',
      );
    }
    return UiScreenManifest(
      theme: theme == null || (theme as String).isEmpty ? null : theme,
      screens: [
        for (final s in (screens as List?) ?? const [])
          if (s is Map && s['path'] is String)
            UiScreenEntry(
              path: s['path'] as String,
              startOpen: s['startOpen'] == true,
              extra: {
                for (final e in s.entries)
                  if (!UiScreenEntry._known.contains(e.key))
                    '${e.key}': e.value,
              },
            ),
      ],
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  /// Reads a screen list from its text, as [fromJson] does.
  factory UiScreenManifest.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map) {
      throw const FormatException('A screen list is a JSON object.');
    }
    return UiScreenManifest.fromJson(json.cast<String, dynamic>());
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'format': currentFormat,
    if (theme != null) 'theme': theme,
    'screens': [for (final s in screens) s.toJson()],
  };

  /// The entry for [path], or null.
  UiScreenEntry? entryFor(String path) {
    for (final entry in screens) {
      if (entry.path == path) return entry;
    }
    return null;
  }

  /// A copy with [screens] instead.
  UiScreenManifest withScreens(List<UiScreenEntry> screens) =>
      UiScreenManifest(theme: theme, screens: screens, extra: extra);

  /// A copy with [theme] instead; an empty one clears it.
  UiScreenManifest withTheme(String? theme) => UiScreenManifest(
    theme: theme == null || theme.isEmpty ? null : theme,
    screens: screens,
    extra: extra,
  );
}

/// One screen in the list.
class UiScreenEntry {
  const UiScreenEntry({
    required this.path,
    this.startOpen = false,
    this.extra = const {},
  });

  /// Its `.ui.json` asset.
  final String path;

  /// Whether it shows from the first frame — a HUD — rather than waiting to
  /// be opened.
  final bool startOpen;

  /// The keys of the entry this list does not read, as they were — kept,
  /// and written back.
  final Map<String, dynamic> extra;

  static const Set<String> _known = {'path', 'startOpen'};

  UiScreenEntry copyWith({String? path, bool? startOpen}) => UiScreenEntry(
    path: path ?? this.path,
    startOpen: startOpen ?? this.startOpen,
    extra: extra,
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'path': path,
    if (startOpen) 'startOpen': true,
  };

  @override
  bool operator ==(Object other) =>
      other is UiScreenEntry &&
      other.path == path &&
      other.startOpen == startOpen &&
      jsonEncode(other.extra) == jsonEncode(extra);

  @override
  int get hashCode => Object.hash(path, startOpen, extra.length);
}
