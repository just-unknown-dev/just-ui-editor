/// One screen, as its `.ui.json` file holds it.
library;

import 'package:just_game_engine/just_game_engine.dart';

import '../components/screen/ui_canvas_component.dart';
import '../serialization/ui_definitions.dart';

/// A screen saved on its own: a canvas and everything under it.
///
/// ```json
/// {
///   "format": 1,
///   "name": "Pause",
///   "entities": [
///     {"name": "Pause", "parentName": null, "components": [...]},
///     {"name": "PauseCard", "parentName": "Pause", "components": [...]}
///   ],
///   "editor": {"guides": [], "samples": {}}
/// }
/// ```
///
/// The first entity is the canvas, the root of everything else; the order
/// of the rest is the order of siblings. Parents are named, never numbered:
/// entity ids are handed out afresh every time a file is read, so a file
/// that saved them would describe a tree that no longer exists. The
/// `editor` section is the editor's alone — guides, sample values — and a
/// game never reads it.
///
/// Whether the screen starts open is not in here: that is a game's choice,
/// made in its screen list ([UiScreenManifest]), not the screen's.
class UiDocument {
  UiDocument({
    required this.name,
    required List<Map<String, dynamic>> entities,
    Map<String, dynamic>? editor,
  }) : entities = List.unmodifiable(entities),
       editor = Map.unmodifiable(editor ?? const {});

  /// The file ending a screen is saved under.
  static const String extension = 'ui.json';

  /// The newest file format this reads and writes.
  static const int currentFormat = 1;

  /// Brings an older file forward, one step per format. Empty while there
  /// is only one.
  static final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)>
  migrations = {};

  /// The screen's name — its canvas's, and what a game opens it by.
  final String name;

  /// Every entity, canvas first, each as `{name, parentName, components}`.
  final List<Map<String, dynamic>> entities;

  /// What only the editor keeps.
  final Map<String, dynamic> editor;

  /// Reads a document, migrating an older format. A newer one than this
  /// code knows is refused rather than half-read.
  factory UiDocument.fromJson(Map<String, dynamic> json) {
    var data = json;
    var format = (data['format'] as num?)?.toInt() ?? currentFormat;
    if (format > currentFormat) {
      throw FormatException(
        'This screen was saved by a newer version (format $format; this '
        'reads up to $currentFormat).',
      );
    }
    while (format < currentFormat) {
      final step = migrations[format];
      if (step == null) {
        throw FormatException('No way to bring format $format forward.');
      }
      data = step(data);
      format++;
    }
    final entities = [
      for (final e in (data['entities'] as List? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    if (entities.isEmpty) {
      throw const FormatException('A screen needs at least its canvas.');
    }
    final editor = data['editor'];
    return UiDocument(
      name: data['name'] as String? ?? entities.first['name'] as String? ?? '',
      entities: entities,
      editor: editor is Map ? editor.cast<String, dynamic>() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': currentFormat,
    'name': name,
    'entities': entities,
    if (editor.isNotEmpty) 'editor': editor,
  };

  /// A copy with other [editor] data.
  UiDocument withEditor(Map<String, dynamic> editor) =>
      UiDocument(name: name, entities: entities, editor: editor);

  /// A copy whose canvas — and so the screen — is called [newName]; what
  /// hung under the old name hangs under the new one.
  UiDocument renamed(String newName) => UiDocument(
    name: newName,
    entities: [
      for (final e in entities)
        {
          ...e,
          if (e['name'] == name) 'name': newName,
          if (e['parentName'] == name) 'parentName': newName,
        },
    ],
    editor: editor,
  );

  /// Builds the screen in [world] and returns its canvas.
  ///
  /// [decode] turns one entity's saved components into components. The
  /// default goes through [world]'s definitions (`world.context`) and stops
  /// on a component nothing registered can read, naming it — a game must
  /// not run half a screen.
  /// The editor passes a decoder that keeps such components instead.
  ///
  /// A name another screen in [world] already uses is fine: everything a
  /// screen looks up by name, it looks up below its own canvas.
  Entity instantiate(
    World world, {
    List<Component> Function(List<dynamic> components)? decode,
  }) {
    final made = <Entity>[];
    final byName = <String, Entity>{};
    final definitions = world.context.definitions;
    for (final record in entities) {
      final name = record['name'] as String?;
      final saved = record['components'] as List? ?? const [];
      final components = [
        for (final c
            in decode?.call(saved) ?? _decodeStrictly(saved, name, definitions))
          // Links are rebuilt from names below, never read from ids.
          if (c is! ParentComponent && c is! ChildrenComponent) c,
      ];
      final entity = world.createEntityWithComponents(components, name: name);
      if (record['enabled'] == false) entity.isActive = false;
      made.add(entity);
      if (name != null) byName.putIfAbsent(name, () => entity);
    }
    for (var i = 1; i < made.length; i++) {
      final parentName = entities[i]['parentName'] as String?;
      final parent = parentName == null ? made.first : byName[parentName];
      link(made[i], parent ?? made.first);
    }
    return made.first;
  }

  /// Hangs [child] under [parent], both ends of the link.
  static void link(Entity child, Entity parent) {
    final existing = child.getComponent<ParentComponent>();
    if (existing != null) {
      existing.parentId = parent.id;
    } else {
      child.addComponent(ParentComponent(parentId: parent.id));
    }
    if (!parent.hasComponent<ChildrenComponent>()) {
      parent.addComponent(ChildrenComponent());
    }
    parent.getComponent<ChildrenComponent>()!.addChild(child.id);
  }

  /// The screen under [canvas] in [world], as a document.
  ///
  /// Parents first and siblings in their parent's order, which is the
  /// order a file must hold them in. [encode] turns an entity's components
  /// into their saved form (the editor keeps what it could not read); the
  /// default goes through [world]'s definitions. The canvas's `visible` is
  /// left
  /// out: whether a screen is open is play, not authoring.
  static UiDocument capture(
    Entity canvas,
    World world, {
    List<Map<String, dynamic>> Function(Iterable<Component> components)? encode,
    Map<String, dynamic>? editor,
  }) {
    final definitions = world.context.definitions;
    final write =
        encode ??
        (Iterable<Component> components) => [
          for (final c in components) ?definitions.encode(c),
        ];
    final records = <Map<String, dynamic>>[];
    void walk(Entity entity, String? parentName) {
      records.add({
        'name': entity.name,
        if (!entity.isActive) 'enabled': false,
        'parentName': parentName,
        'components': [
          for (final json in write(entity.components))
            if (json['type'] != 'ParentComponent' &&
                json['type'] != 'ChildrenComponent')
              identical(entity, canvas) ? _withoutVisible(json) : json,
        ],
      });
      final children = entity.getComponent<ChildrenComponent>()?.childIds;
      for (final id in children ?? const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null) walk(child, entity.name);
      }
    }

    walk(canvas, null);
    return UiDocument(
      name: canvas.name ?? '',
      entities: records,
      editor: editor,
    );
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

  static List<Component> _decodeStrictly(
    List<dynamic> json,
    String? name,
    ComponentDefinitionRegistry registry,
  ) {
    return [
      for (final item in json)
        if (item is Map)
          registry.decode(item.cast<String, dynamic>()) ??
              (throw UnknownComponentTypeException(
                item['type'] as String? ?? '(no type)',
                entityName: name,
              )),
    ];
  }

  /// The canvas component of the screen's root record, decoded — for
  /// reading its settings (design size, theme) without building anything.
  UiCanvasComponent? get canvasSettings {
    for (final c in (entities.first['components'] as List? ?? const [])) {
      if (c is Map && c['type'] == 'UiCanvasComponent') {
        // Through the canvas's own definition: this reads settings, and
        // needs no engine to do it.
        return UiDefinitions.canvas.decode(c.cast<String, dynamic>());
      }
    }
    return null;
  }
}
