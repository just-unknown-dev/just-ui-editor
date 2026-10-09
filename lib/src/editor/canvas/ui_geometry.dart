/// The arithmetic of editing a screen: handles, resizing, snapping, and
/// turning a rectangle back into what a slot saves.
///
/// Pure: everything here is in design pixels and knows nothing of widgets,
/// so it is tested directly.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart'
    show SmartSnap, SnapGuide;

import '../../runtime/components/screen/ui_slot_component.dart';

/// What a drag on a selected element grabbed.
enum UiHandle {
  move,
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesRight =>
      this == topRight || this == right || this == bottomRight;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get movesBottom =>
      this == bottomLeft || this == bottom || this == bottomRight;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  /// Where on [rect] this handle is drawn.
  Offset on(Rect rect) => switch (this) {
    move => rect.center,
    topLeft => rect.topLeft,
    top => rect.topCenter,
    topRight => rect.topRight,
    right => rect.centerRight,
    bottomRight => rect.bottomRight,
    bottom => rect.bottomCenter,
    bottomLeft => rect.bottomLeft,
    left => rect.centerLeft,
  };

  /// The eight that resize.
  static const List<UiHandle> resizing = [
    topLeft,
    top,
    topRight,
    right,
    bottomRight,
    bottom,
    bottomLeft,
    left,
  ];
}

abstract final class UiGeometry {
  /// The smallest an element is let shrink to by a drag.
  static const double minSize = 4;

  /// [start] with the edges [handle] grabbed moved by [delta].
  ///
  /// The grabbed edge follows the pointer exactly, and the opposite edge
  /// stays put — unless [fromCentre], when both move and the centre stays.
  /// [keepAspect] keeps the width-to-height ratio from a corner.
  static Rect resize(
    Rect start,
    UiHandle handle,
    Offset delta, {
    bool keepAspect = false,
    bool fromCentre = false,
  }) {
    if (handle == UiHandle.move) return start.shift(delta);
    var left = start.left;
    var right = start.right;
    var top = start.top;
    var bottom = start.bottom;
    if (handle.movesLeft) left += delta.dx;
    if (handle.movesRight) right += delta.dx;
    if (handle.movesTop) top += delta.dy;
    if (handle.movesBottom) bottom += delta.dy;
    if (fromCentre) {
      if (handle.movesLeft) right -= delta.dx;
      if (handle.movesRight) left -= delta.dx;
      if (handle.movesTop) bottom -= delta.dy;
      if (handle.movesBottom) top -= delta.dy;
    }
    var width = math.max(minSize, right - left);
    var height = math.max(minSize, bottom - top);
    if (keepAspect && handle.isCorner && start.height > 0 && start.width > 0) {
      final ratio = start.width / start.height;
      // The larger change wins, the other follows it.
      if ((width / start.width - 1).abs() >=
          (height / start.height - 1).abs()) {
        height = math.max(minSize, width / ratio);
      } else {
        width = math.max(minSize, height * ratio);
      }
    }
    if (fromCentre) {
      return Rect.fromCenter(
        center: start.center,
        width: width,
        height: height,
      );
    }
    // Pinned to the edge that did not move.
    final x = handle.movesLeft ? start.right - width : start.left;
    final y = handle.movesTop ? start.bottom - height : start.top;
    return Rect.fromLTWH(x, y, width, height);
  }

  /// What [slot] would save to put its element at [rect] inside a parent
  /// of [parent] — the inverse of [UiSlotComponent.rectIn].
  ///
  /// Along an axis the anchor stretches, the margins take the rectangle's
  /// edges; along one it does not, the offset takes where its pivot lands
  /// and the size is kept as drawn.
  static ({Offset offset, Size size, EdgeInsets margin}) fit(
    UiSlotComponent slot,
    Rect rect,
    Size parent, {
    UiAnchor? anchor,
    Offset? pivot,
  }) {
    final a = anchor ?? slot.anchor;
    final p = pivot ?? slot.pivot;
    final left = a.min.dx * parent.width;
    final right = a.max.dx * parent.width;
    final top = a.min.dy * parent.height;
    final bottom = a.max.dy * parent.height;
    var offset = slot.offset;
    var size = slot.size;
    var margin = slot.margin;
    if (a.stretchesX) {
      margin = margin.copyWith(
        left: rect.left - left,
        right: right - rect.right,
      );
    } else {
      offset = Offset(rect.left + rect.width * p.dx - left, offset.dy);
      size = Size(rect.width, size.height);
    }
    if (a.stretchesY) {
      margin = margin.copyWith(
        top: rect.top - top,
        bottom: bottom - rect.bottom,
      );
    } else {
      offset = Offset(offset.dx, rect.top + rect.height * p.dy - top);
      size = Size(size.width, rect.height);
    }
    return (offset: offset, size: size, margin: margin);
  }

  /// Snaps [value] to the nearest of [lines] within [threshold], or leaves
  /// it.
  static double snapTo(double value, Iterable<double> lines, double threshold) {
    var best = value;
    var bestGap = threshold;
    for (final line in lines) {
      final gap = (line - value).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        best = line;
      }
    }
    return best;
  }

  /// [value] on the nearest multiple of [step].
  static double onGrid(double value, double step) =>
      step <= 0 ? value : (value / step).roundToDouble() * step;
}

/// Where a moving or resizing element may snap to, all in one parent's
/// design pixels.
class UiSnapTargets {
  const UiSnapTargets({
    this.rects = const [],
    this.xLines = const [],
    this.yLines = const [],
    this.grid = 0,
  });

  /// Its siblings, its parent and the canvas: edges and centres attract.
  final List<Rect> rects;

  /// Guides: infinite lines that attract edges and centres alike.
  final List<double> xLines;
  final List<double> yLines;

  /// The grid step, or 0 for none.
  final double grid;

  static const UiSnapTargets none = UiSnapTargets();

  List<double> get _xs => [
    ...xLines,
    for (final r in rects) ...[r.left, r.center.dx, r.right],
  ];

  List<double> get _ys => [
    ...yLines,
    for (final r in rects) ...[r.top, r.center.dy, r.bottom],
  ];

  /// [moving], shifted to line up — and the lines it now lines up with.
  (Rect, List<SnapGuide>) move(Rect moving, double threshold) {
    final snap = SmartSnap.snap(
      moving,
      rects,
      threshold: threshold,
      xLines: xLines,
      yLines: yLines,
    );
    var result = moving.shift(snap.adjustment);
    if (grid > 0) {
      if (snap.dx == null) {
        result = result.translate(
          UiGeometry.onGrid(result.left, grid) - result.left,
          0,
        );
      }
      if (snap.dy == null) {
        result = result.translate(
          0,
          UiGeometry.onGrid(result.top, grid) - result.top,
        );
      }
    }
    return (result, _guides(result));
  }

  /// [resized] with only the edges [handle] moves pulled onto whatever is
  /// near — the others stay where the drag left them.
  (Rect, List<SnapGuide>) resize(
    Rect resized,
    UiHandle handle,
    double threshold,
  ) {
    double edge(double value, List<double> lines) {
      final snapped = UiGeometry.snapTo(value, lines, threshold);
      if (snapped != value || grid <= 0) return snapped;
      return UiGeometry.onGrid(value, grid);
    }

    var left = resized.left;
    var right = resized.right;
    var top = resized.top;
    var bottom = resized.bottom;
    if (handle.movesLeft) left = edge(left, _xs);
    if (handle.movesRight) right = edge(right, _xs);
    if (handle.movesTop) top = edge(top, _ys);
    if (handle.movesBottom) bottom = edge(bottom, _ys);
    final result = Rect.fromLTRB(
      left,
      top,
      math.max(left + UiGeometry.minSize, right),
      math.max(top + UiGeometry.minSize, bottom),
    );
    return (result, _guides(result));
  }

  List<SnapGuide> _guides(Rect rect) => [
    ...SmartSnap.guides(rect, rects),
    for (final x in xLines)
      if ([
        rect.left,
        rect.center.dx,
        rect.right,
      ].any((v) => (v - x).abs() < 1e-3))
        SnapGuide(
          vertical: true,
          position: x,
          start: rect.top,
          end: rect.bottom,
        ),
    for (final y in yLines)
      if ([
        rect.top,
        rect.center.dy,
        rect.bottom,
      ].any((v) => (v - y).abs() < 1e-3))
        SnapGuide(
          vertical: false,
          position: y,
          start: rect.left,
          end: rect.right,
        ),
  ];
}
