// Where each entity's node landed on screen, for an editor.
part of 'ui_layer.dart';

/// Where each entity's node is on screen, as a [UiLayer] built it.
///
/// Not a `GlobalKey` per entity: a key can be in one place at a time, and
/// one entity can be built in two — a screen opened again while it is
/// still closing has a leaving route and an arriving one. The arriving one
/// tore the canvas out of the leaving one in mid-layout, and Flutter
/// reported a duplicate key, a mutated render box and a broken semantics
/// tree. Here both are kept, and the newer one is the answer.
class UiNodeBoxes {
  final Map<int, List<BuildContext>> _built = {};

  /// Where [id]'s node is laid out, or null when it is not on screen.
  RenderBox? operator [](int id) {
    final built = _built[id];
    if (built == null) return null;
    for (final context in built.reversed) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) return box;
    }
    return null;
  }

  void _add(int id, BuildContext context) =>
      (_built[id] ??= <BuildContext>[]).add(context);

  void _remove(int id, BuildContext context) {
    final built = _built[id];
    if (built == null) return;
    built.remove(context);
    if (built.isEmpty) _built.remove(id);
  }
}

/// Puts [child] in [nodes] under [id] for as long as it is in the tree.
///
/// Only while it is active: an element taken out of the tree in this frame
/// has no render object to ask about.
class _UiNodeMark extends StatefulWidget {
  const _UiNodeMark({
    required this.id,
    required this.nodes,
    required this.child,
  });

  final int id;
  final UiNodeBoxes nodes;
  final Widget child;

  @override
  State<_UiNodeMark> createState() => _UiNodeMarkState();
}

class _UiNodeMarkState extends State<_UiNodeMark> {
  @override
  void initState() {
    super.initState();
    widget.nodes._add(widget.id, context);
  }

  @override
  void didUpdateWidget(_UiNodeMark old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id && identical(old.nodes, widget.nodes)) return;
    old.nodes._remove(old.id, context);
    widget.nodes._add(widget.id, context);
  }

  @override
  void deactivate() {
    widget.nodes._remove(widget.id, context);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.nodes._add(widget.id, context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
