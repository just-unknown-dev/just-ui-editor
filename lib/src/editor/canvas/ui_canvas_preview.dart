// What the canvas shows besides the document: the copy Preview plays
// with, and the other screens drawn behind it.
part of 'ui_canvas_view.dart';

/// The worlds [UiCanvasViewState] builds to show more than the open
/// screen.
extension _UiCanvasPreview on UiCanvasViewState {
  /// Buttons shown in the state the preview strip asks for — every button,
  /// or the selected ones when there are any — in [world], the one shown.
  void _applyForcedState(World world, {required bool previewing}) {
    final forced = session.forcedState.value;
    final selected = {
      for (final e in session.selection)
        ?(previewing ? _previewIds[e.id] : e.id),
    };
    for (final e in world.query([UiButtonComponent])) {
      final button = e.getComponent<UiButtonComponent>()!;
      final applies =
          forced != null && (selected.isEmpty || selected.contains(e.id));
      final want = applies ? forced : UiInteractionState.normal;
      if (!previewing || applies) {
        if (button.state != want) button.state = want;
      }
    }
  }

  // ── Building ───────────────────────────────────────────────────────────

  void _syncBehind(UiScreenDocument doc) {
    final names = [
      for (final n in session.behind.value)
        if (n != doc.name) n,
    ];
    if (listEquals(names, _behindNames)) return;
    _behindNames = names;
    UiCanvasViewState._disposeLater(_behind);
    _behind = null;
    if (names.isEmpty) return;
    final world = World(context: doc.world.context)..initialize();
    session.showSamplesIn(world);
    for (final name in names) {
      final path = session.screensByName[name];
      if (path == null) continue;
      try {
        final canvas = session.project
            .readScreen(path, hooks: world.context.migrations)
            .instantiate(world, decode: doc.codec.decodeAll);
        canvas.getComponent<UiCanvasComponent>()?.visible = true;
      } on Object {
        continue;
      }
    }
    _behind = world;
  }

  /// Builds the copy Preview shows, or lets it go outside Preview.
  void _syncPreview(UiScreenDocument? doc) {
    if (doc == null || !session.previewing) {
      if (_preview == null) return;
      UiCanvasViewState._disposeLater(_preview);
      _preview = null;
      _previewFor = null;
      _previewIds = const {};
      session.previewCanvas = null;
      return;
    }
    final revision = doc.history.revision.value;
    if (_preview != null &&
        identical(_previewFor, doc) &&
        _previewRevision == revision) {
      return;
    }
    UiCanvasViewState._disposeLater(_preview);
    final world = World(context: doc.world.context)
      ..initialize()
      // Text that types itself out, bindings re-read — as in the document.
      ..addSystem(UiTextSystem());
    session.showSamplesIn(world);
    final canvas = doc.capture().instantiate(
      world,
      decode: doc.codec.decodeAll,
    );
    canvas.getComponent<UiCanvasComponent>()?.visible = true;
    // A file lists parents first and siblings in order, and is built in
    // that order: walked the same way, the copy's entities line up with the
    // document's one for one.
    final copies = <Entity>[];
    void walk(Entity e) {
      copies.add(e);
      for (final id
          in e.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[]) {
        if (world.getEntity(id) case final child?) walk(child);
      }
    }

    walk(canvas);
    final originals = doc.entities;
    _previewIds = {
      for (var i = 0; i < originals.length && i < copies.length; i++)
        originals[i].id: copies[i].id,
    };
    _preview = world;
    _previewFor = doc;
    _previewRevision = revision;
    _previewNodes = UiNodeBoxes();
    session.previewCanvas = canvas;
  }

  /// Where the preview's buttons go: nowhere near the game. What they would
  /// do is said in the strip instead.
  UiActionHost _previewHost() {
    void said(String what) => session.lastAction.value = what;
    return UiActionHost(
      loadScene: (scene) => said('Opens the level $scene'),
      pause: () => said('Pauses the game'),
      resume: () => said('Resumes the game'),
      quit: () => said('Quits'),
      playSound: (path) => said('Plays $path'),
      pushScreen: (name) => name == _doc?.name
          ? said('Opens $name — this screen')
          : said('Opens $name'),
      back: () => said('Goes back — closes this screen'),
      showUi: (name, visible) => said(
        visible == false
            ? 'Hides $name'
            : (visible == true ? 'Shows $name' : 'Flips $name'),
      ),
    );
  }
}
