/// A game's list of screens.
library;

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
class UiScreenManifest {
  UiScreenManifest({this.theme, List<UiScreenEntry> screens = const []})
    : screens = List.unmodifiable(screens);

  /// Where a game keeps its list, unless it says otherwise.
  static const String defaultPath = 'assets/ui/screens.json';

  static const int currentFormat = 1;

  /// The theme a screen that names none is drawn with, if any.
  final String? theme;

  final List<UiScreenEntry> screens;

  factory UiScreenManifest.fromJson(Map<String, dynamic> json) {
    final format = (json['format'] as num?)?.toInt() ?? currentFormat;
    if (format > currentFormat) {
      throw FormatException(
        'This screen list was saved by a newer version (format $format).',
      );
    }
    final theme = json['theme'] as String?;
    return UiScreenManifest(
      theme: theme == null || theme.isEmpty ? null : theme,
      screens: [
        for (final s in (json['screens'] as List? ?? const []))
          if (s is Map && s['path'] is String)
            UiScreenEntry(
              path: s['path'] as String,
              startOpen: s['startOpen'] == true,
            ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
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
      UiScreenManifest(theme: theme, screens: screens);

  /// A copy with [theme] instead; an empty one clears it.
  UiScreenManifest withTheme(String? theme) => UiScreenManifest(
    theme: theme == null || theme.isEmpty ? null : theme,
    screens: screens,
  );
}

/// One screen in the list.
class UiScreenEntry {
  const UiScreenEntry({required this.path, this.startOpen = false});

  /// Its `.ui.json` asset.
  final String path;

  /// Whether it shows from the first frame — a HUD — rather than waiting to
  /// be opened.
  final bool startOpen;

  UiScreenEntry copyWith({String? path, bool? startOpen}) => UiScreenEntry(
    path: path ?? this.path,
    startOpen: startOpen ?? this.startOpen,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    if (startOpen) 'startOpen': true,
  };

  @override
  bool operator ==(Object other) =>
      other is UiScreenEntry &&
      other.path == path &&
      other.startOpen == startOpen;

  @override
  int get hashCode => Object.hash(path, startOpen);
}
