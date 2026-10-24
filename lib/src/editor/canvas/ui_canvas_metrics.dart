/// Where things are on the canvas — read back from where Flutter put them.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../runtime/components/screen/ui_elements.dart';
import '../../runtime/components/screen/ui_slot_component.dart';
import '../../runtime/layer/ui_layer.dart';
import '../document/ui_screen_document.dart';

/// Turns between the editor's view (what is on the monitor) and a screen's
/// design pixels, and says where each element landed.
///
/// Read back from the real layout — each element's widget is marked in
/// [nodes] — so what is outlined, grabbed and snapped to is exactly what the screen
/// draws, whatever row, column or scale put it there. Design pixels are the
/// canvas's own: `(0, 0)` its top-left, its design size its bottom-right.
class UiCanvasMetrics {
  UiCanvasMetrics({
    required this.view,
    required this.document,
    required this.nodes,
    this.ids,
  });

  /// The box the editor draws its handles in.
  final RenderBox view;

  final UiScreenDocument document;
  final UiNodeBoxes nodes;

  /// Where [nodes] are of another world than [document]'s — Preview shows
  /// a copy of the screen — the copy's id for each of the document's
  /// entities. An entity it does not name is not on screen.
  final Map<EntityId, EntityId>? ids;

  RenderBox? _boxOf(Entity entity) {
    final map = ids;
    if (map == null) return nodes[entity.id];
    final id = map[entity.id];
    return id == null ? null : nodes[id];
  }

  /// Where [entity] is on the view, or null when it is not drawn.
  Rect? viewRectOf(Entity entity) {
    final box = _boxOf(entity);
    if (box == null) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(view),
      Offset.zero & box.size,
    );
  }

  /// The canvas on the view.
  Rect? get canvasView => viewRectOf(document.canvas);

  /// View pixels per design pixel.
  double get scale {
    final box = _boxOf(document.canvas);
    final rect = canvasView;
    if (box == null || rect == null || box.size.width == 0) return 1;
    return rect.width / box.size.width;
  }

  /// The canvas's design size.
  Size get designSize => _boxOf(document.canvas)?.size ?? Size.zero;

  Offset toDesign(Offset viewPoint) {
    final origin = canvasView?.topLeft ?? Offset.zero;
    return (viewPoint - origin) / scale;
  }

  Offset toView(Offset designPoint) {
    final origin = canvasView?.topLeft ?? Offset.zero;
    return origin + designPoint * scale;
  }

  Rect designToView(Rect rect) =>
      Rect.fromPoints(toView(rect.topLeft), toView(rect.bottomRight));

  Rect viewToDesign(Rect rect) =>
      Rect.fromPoints(toDesign(rect.topLeft), toDesign(rect.bottomRight));

  /// Where [entity] is, in design pixels.
  Rect? designRectOf(Entity entity) {
    final rect = viewRectOf(entity);
    return rect == null ? null : viewToDesign(rect);
  }

  /// The box [parent]'s children are laid out in, in design pixels: the
  /// canvas's whole area, or a container's inside its padding.
  Rect? contentRectOf(Entity parent) {
    final rect = designRectOf(parent);
    if (rect == null) return null;
    final padding = parent.getComponent<UiLayoutComponent>()?.padding;
    return padding == null ? rect : padding.deflateRect(rect);
  }

  /// The element a click at [viewPoint] means: the smallest one there, and
  /// of two the same size the one drawn on top — the deeper, or the later
  /// of siblings. Topmost alone let a layer stretched over the whole screen
  /// (a HUD's touch controls) take every click and hide what is under it.
  /// Hidden elements have no box and are never found; the canvas is found
  /// only when nothing else is.
  Entity? pick(Offset viewPoint) {
    Entity? found;
    var smallest = double.infinity;
    for (final entity in document.entities.skip(1)) {
      final slot = entity.getComponent<UiSlotComponent>();
      if (slot != null && !slot.visible) continue;
      if (!entity.isActive) continue;
      final rect = viewRectOf(entity);
      if (rect == null || !rect.contains(viewPoint)) continue;
      final area = rect.width * rect.height;
      if (area <= smallest) {
        found = entity;
        smallest = area;
      }
    }
    if (found != null) return found;
    final canvas = canvasView;
    return canvas != null && canvas.contains(viewPoint)
        ? document.canvas
        : null;
  }

  /// Everything whose box lies entirely inside [viewRect] — for a marquee.
  List<Entity> inside(Rect viewRect) => [
    for (final entity in document.entities.skip(1))
      if (viewRectOf(entity) case final rect?
          when viewRect.contains(rect.topLeft) &&
              viewRect.contains(rect.bottomRight))
        entity,
  ];
}
