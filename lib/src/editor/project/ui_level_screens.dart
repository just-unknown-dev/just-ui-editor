/// Screens left inside a level from before screens were files of their own.
library;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/screens/ui_document.dart';
import '../../runtime/screens/ui_scene_extractor.dart';
import '../../runtime/screens/ui_screen_manifest.dart';
import 'ui_project.dart';

/// One screen moved out of a level.
class UiMovedScreen {
  const UiMovedScreen({required this.name, required this.path, this.was});

  /// What the screen is called now — what the game opens it by.
  final String name;

  /// The file it went to.
  final String path;

  /// Its name in the level, when that was already another screen's and it
  /// had to take a new one.
  final String? was;
}

/// Finds the screens a level still holds and moves them out, into
/// `.ui.json` files on the game's list — where the interface editor edits
/// them and every level shares them.
abstract final class UiLevelScreens {
  /// Every canvas in [world] that is not inside another: one per screen.
  static List<Entity> of(World world) => [
    for (final e in world.entities)
      if (e.isAlive &&
          e.hasComponent<UiCanvasComponent>() &&
          !_insideCanvas(world, e))
        e,
  ];

  static bool _insideCanvas(World world, Entity e) {
    var parent = e.getComponent<ParentComponent>()?.parentId;
    final seen = <EntityId>{};
    while (parent != null && seen.add(parent)) {
      final p = world.getEntity(parent);
      if (p == null) return false;
      if (p.hasComponent<UiCanvasComponent>()) return true;
      parent = p.getComponent<ParentComponent>()?.parentId;
    }
    return false;
  }

  /// Writes each screen in [world] to a file of its own, lists it — one
  /// that was showing opens by itself, as it did — and takes it out of the
  /// level in one step [history] can undo. The files stay either way: they
  /// are the project's now, and undo only puts the level back as it was.
  ///
  /// A screen whose name another screen already has takes a free one, and
  /// says so in [UiMovedScreen.was]. Empty when there was nothing to move.
  /// Throws a [FormatException], having written nothing, while the game's
  /// screen list does not read.
  static List<UiMovedScreen> moveOut({
    required World world,
    required EditorSceneState sceneState,
    required EditorHistory history,
    required SceneCodec codec,
    required UiProject project,
    String folder = 'assets/ui',
  }) {
    final canvases = of(world);
    if (canvases.isEmpty) return const [];
    // Before anything is written: a list that does not read cannot take
    // the screens, and written over it would lose every one it names.
    if (project.manifestProblem() case final problem?) {
      throw FormatException(
        '${UiScreenManifest.defaultPath} does not read ($problem). Mend '
        'it by hand first.',
      );
    }

    final subtree = <Entity>[];
    void collect(Entity e) {
      subtree.add(e);
      for (final id
          in e.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null) collect(child);
      }
    }

    canvases.forEach(collect);
    final extraction = UiSceneExtractor.extract({
      'entities': codec.encodeEntities(subtree),
    }, folder: folder);

    var manifest = project.readManifest();
    final taken = {
      for (final path in project.screenFiles()) _key(project, path),
    };
    final moved = <UiMovedScreen>[];
    final entries = [...manifest.screens];
    String pathOf(String name) =>
        '$folder/${UiSceneExtractor.fileNameFor(name)}';
    for (var i = 0; i < extraction.documents.length; i++) {
      var document = extraction.documents[i];
      final was = document.name;
      var name = was;
      for (
        var n = 2;
        taken.contains(name.toLowerCase()) || project.exists(pathOf(name));
        n++
      ) {
        name = '$was$n';
      }
      if (name != was) document = document.renamed(name);
      taken.add(name.toLowerCase());
      final path = pathOf(name);
      project.writeScreen(path, document);
      entries.add(
        UiScreenEntry(path: path, startOpen: extraction.entries[i].startOpen),
      );
      moved.add(
        UiMovedScreen(name: name, path: path, was: name == was ? null : was),
      );
    }
    manifest = manifest.withScreens(entries);
    project.writeManifest(manifest);

    history.push(
      DeleteEntitiesCommand(
        label: moved.length == 1
            ? 'Move ${moved.single.name} out of the level'
            : 'Move ${moved.length} screens out of the level',
        world: world,
        sceneState: sceneState,
        entities: canvases,
        codec: codec,
      ),
    );
    return moved;
  }

  /// What a screen is called, read from its file where it can be — the
  /// name, not the file name, is what two screens must not share.
  static String _key(UiProject project, String path) {
    try {
      return project.readScreen(path).name.toLowerCase();
    } on Object {
      return path
          .split('/')
          .last
          .replaceAll('.${UiDocument.extension}', '')
          .replaceAll('_', '')
          .toLowerCase();
    }
  }
}
