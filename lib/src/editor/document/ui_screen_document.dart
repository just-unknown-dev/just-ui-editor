/// One screen open in the interface editor.
library;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../../runtime/components/screen/ui_canvas_component.dart';
import '../../runtime/just_game_ui.dart';
import '../../runtime/screens/ui_document.dart';
import '../../runtime/systems/ui_system.dart';

/// A `.ui.json` being edited: built into a world of its own, with its own
/// selection and its own history.
///
/// Its own world because a screen is not in the level — and so an undo in
/// here never reaches the level, nor one there reach this. Its own
/// [EditorSceneState] because everything the editor's commands and panels
/// do goes through one: selection, the refresh after an edit, the tree's
/// order.
class UiScreenDocument {
  UiScreenDocument._({
    required this.path,
    required this.world,
    required this.canvas,
    required this.codec,
    required Map<String, dynamic> editorData,
  }) : editorData = Signal(editorData, debugLabel: 'uiEditorData') {
    sceneState.openScene(
      EditorScene(name: canvas.name ?? 'Screen'),
      rootOrder: [canvas.id],
    );
    history.markSaved();
  }

  /// [document] from [path], built. What nothing registered can read is
  /// kept, not dropped, and saved back as it came.
  ///
  /// Built in a world on [context] — the edited engine's, so the game's own
  /// components read — or a context of its own when null. [codec] defaults
  /// to one over that context's definitions.
  factory UiScreenDocument.open(
    String path,
    UiDocument document, {
    SceneCodec? codec,
    EngineContext? context,
  }) {
    final world = _world(context);
    final using = codec ?? SceneCodec(world.context.definitions);
    final canvas = document.instantiate(world, decode: using.decodeAll);
    // Shown while it is being edited, whatever the game opens it as.
    canvas.getComponent<UiCanvasComponent>()?.visible = true;
    return UiScreenDocument._(
      path: path,
      world: world,
      canvas: canvas,
      codec: using,
      editorData: {...document.editor},
    );
  }

  /// A new screen called [name], to be saved at [path].
  factory UiScreenDocument.blank(
    String path,
    String name, {
    bool isScreen = true,
    SceneCodec? codec,
    EngineContext? context,
  }) {
    final world = _world(context);
    final canvas = world.createEntityWithComponents([
      UiCanvasComponent(isScreen: isScreen, modal: isScreen),
      ChildrenComponent(),
    ], name: name);
    return UiScreenDocument._(
      path: path,
      world: world,
      canvas: canvas,
      codec: codec ?? SceneCodec(world.context.definitions),
      editorData: const {},
    );
  }

  /// A preview world on [context] (its own when null), with the interface's
  /// components installed.
  static World _world(EngineContext? context) => World(context: context)
    ..context.install(JustGameUi.extension)
    ..initialize()
    // Text that types itself out, bindings re-read — in the preview.
    ..addSystem(UiSystem());

  /// Where it is saved.
  String path;

  /// Where it is built.
  final World world;

  /// Its root.
  final Entity canvas;

  /// How its components are written and read.
  final SceneCodec codec;

  /// Selection, refresh and the tree's order, for this screen alone.
  final EditorSceneState sceneState = EditorSceneState();

  /// Undo for this screen alone.
  final EditorHistory history = EditorHistory();

  /// What only the editor keeps with the screen: guides, sample values,
  /// the device last shown. Changed through [setEditorData], which records
  /// an undo step.
  final Signal<Map<String, dynamic>> editorData;

  /// Its name — the canvas's, which is what a game opens it by.
  String get name => canvas.name ?? '';

  /// Whether there are changes not yet saved.
  Signal<bool> get dirty => history.dirty;

  UiCanvasComponent? get settings => canvas.getComponent<UiCanvasComponent>();

  /// Changes one entry of [editorData] as an undoable step.
  void setEditorData(String key, Object? value, {String? label}) {
    final before = editorData.value[key];
    history.push(
      _EditorDataCommand(
        document: this,
        key: key,
        before: before,
        after: value,
        label: label ?? 'Change $key',
      ),
    );
  }

  /// The screen as its file will hold it.
  UiDocument capture() => UiDocument.capture(
    canvas,
    world,
    encode: codec.encodeAll,
    editor: editorData.value,
  );

  /// Records that what is on screen is what was just written.
  void markSaved() {
    history.markSaved();
    sceneState.markClean();
  }

  /// Every entity of the screen, canvas first.
  List<Entity> get entities {
    final out = <Entity>[];
    void walk(Entity e) {
      out.add(e);
      for (final id
          in e.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        final child = world.getEntity(id);
        if (child != null) walk(child);
      }
    }

    walk(canvas);
    return out;
  }

  /// A name no entity of the screen has, from [base]: `Button`, `Button2`.
  String uniqueName(String base) {
    final taken = {for (final e in world.entities) e.name};
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base$n')) {
      n++;
    }
    return '$base$n';
  }

  void dispose() {
    history.dispose();
    sceneState.dispose();
    editorData.dispose();
    world.dispose();
  }
}

/// One entry of a document's editor data, changed.
class _EditorDataCommand extends EditorCommand {
  _EditorDataCommand({
    required this.document,
    required this.key,
    required this.before,
    required this.after,
    required this.label,
  });

  final UiScreenDocument document;
  final String key;
  final Object? before;
  Object? after;

  @override
  final String label;

  void _set(Object? value) {
    final next = {...document.editorData.value};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    document.editorData.value = next;
  }

  @override
  void redo() => _set(after);

  @override
  void undo() => _set(before);

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! _EditorDataCommand ||
        next.key != key ||
        next.label != label ||
        !identical(next.document, document)) {
      return false;
    }
    after = next.after;
    return true;
  }
}
