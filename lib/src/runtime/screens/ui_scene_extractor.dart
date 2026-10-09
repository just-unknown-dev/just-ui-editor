/// Taking screens out of a scene that still holds them.
library;

import 'ui_document.dart';
import 'ui_screen_manifest.dart';

/// What [UiSceneExtractor.extract] found.
class UiSceneExtraction {
  const UiSceneExtraction({
    required this.scene,
    required this.documents,
    required this.entries,
  });

  /// The scene with every screen taken out.
  final Map<String, dynamic> scene;

  /// One per canvas the scene held, in the order it held them.
  final List<UiDocument> documents;

  /// Where each would go in the screen list, beside [documents]: open from
  /// the start if the scene had it showing.
  final List<UiScreenEntry> entries;

  bool get isEmpty => documents.isEmpty;
}

/// Turns the canvases a scene holds into screens of their own.
///
/// Screens used to live inside a level's scene, so a second level needed
/// its own copy of every menu. Each canvas — and everything under it — comes
/// out as a [UiDocument]; everything else in the scene is left exactly as
/// it was, world-space text and buttons included.
abstract final class UiSceneExtractor {
  /// Splits [scene] (a scene file's JSON) into the scene without its
  /// screens and the screens, to be saved under [folder].
  static UiSceneExtraction extract(
    Map<String, dynamic> scene, {
    String folder = 'assets/ui',
  }) {
    final entities = [
      for (final e in (scene['entities'] as List? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    final canvases = [
      for (final e in entities)
        if (_components(e).any((c) => c['type'] == 'UiCanvasComponent')) e,
    ];
    if (canvases.isEmpty) {
      return UiSceneExtraction(
        scene: scene,
        documents: const [],
        entries: const [],
      );
    }

    // Children by parent name, in the order the file holds them — which is
    // the order of siblings.
    final childrenOf = <String, List<Map<String, dynamic>>>{};
    for (final e in entities) {
      final parent = e['parentName'] as String?;
      if (parent != null) (childrenOf[parent] ??= []).add(e);
    }
    final taken = <Map<String, dynamic>>{};
    final documents = <UiDocument>[];
    final entries = <UiScreenEntry>[];

    for (final canvas in canvases) {
      if (taken.contains(canvas)) continue; // a canvas inside another
      final records = <Map<String, dynamic>>[];
      void walk(Map<String, dynamic> entity, String? parentName) {
        if (!taken.add(entity)) return;
        records.add({
          'name': entity['name'],
          if (entity['enabled'] == false) 'enabled': false,
          'parentName': parentName,
          'components': [
            for (final c in _components(entity))
              if (c['type'] != 'ParentComponent' &&
                  c['type'] != 'ChildrenComponent')
                identical(entity, canvas) ? _withoutVisible(c) : c,
          ],
        });
        final name = entity['name'] as String?;
        for (final child in childrenOf[name] ?? const []) {
          walk(child, name);
        }
      }

      walk(canvas, null);
      final name = canvas['name'] as String? ?? 'Screen';
      documents.add(UiDocument(name: name, entities: records));
      entries.add(
        UiScreenEntry(
          path: '$folder/${fileNameFor(name)}',
          startOpen: _wasShowing(canvas),
        ),
      );
    }

    final names = {for (final e in taken) e['name']};
    final left = {
      ...scene,
      'entities': [
        for (final e in entities)
          if (!taken.contains(e)) e,
      ],
    };
    // The scene's node graph lists what has a transform; a screen had none,
    // but an old file may still name one there.
    final root = scene['root'];
    if (root is Map && root['children'] is List) {
      left['root'] = {
        ...root.cast<String, dynamic>(),
        'children': [
          for (final c in root['children'] as List)
            if (c is! Map || !names.contains(c['name'])) c,
        ],
      };
    }
    return UiSceneExtraction(
      scene: left,
      documents: documents,
      entries: entries,
    );
  }

  /// `DeviceLost` → `device_lost.ui.json`.
  static String fileNameFor(String screenName) {
    final snake = screenName
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])([A-Z])'),
          (m) => '_${m.group(1)}',
        )
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
        .toLowerCase();
    return '${snake.isEmpty ? 'screen' : snake}.${UiDocument.extension}';
  }

  static List<Map<String, dynamic>> _components(Map<String, dynamic> e) => [
    for (final c in (e['components'] as List? ?? const []))
      if (c is Map) c.cast<String, dynamic>(),
  ];

  static bool _wasShowing(Map<String, dynamic> canvas) {
    for (final c in _components(canvas)) {
      if (c['type'] != 'UiCanvasComponent') continue;
      final fields = c['fields'];
      return fields is Map && fields['visible'] != false;
    }
    return false;
  }

  static Map<String, dynamic> _withoutVisible(Map<String, dynamic> json) {
    if (json['type'] != 'UiCanvasComponent') return json;
    final fields = json['fields'];
    if (fields is! Map || !fields.containsKey('visible')) return json;
    return {
      ...json,
      'fields': {...fields.cast<String, dynamic>()}..remove('visible'),
    };
  }
}
