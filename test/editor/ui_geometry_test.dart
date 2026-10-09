// The arithmetic behind dragging and sizing on a screen: the edge grabbed
// follows the pointer, a rectangle turns back into what a slot saves, and
// snapping pulls only what is moving.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/just_ui_editor.dart';
import 'package:just_ui_editor/src/editor/canvas/ui_geometry.dart';

void main() {
  const start = Rect.fromLTWH(100, 100, 200, 80);

  group('resizing', () {
    test('every handle moves its own edges and no others', () {
      const d = Offset(10, 20);
      expect(
        UiGeometry.resize(start, UiHandle.right, d),
        const Rect.fromLTRB(100, 100, 310, 180),
      );
      expect(
        UiGeometry.resize(start, UiHandle.left, d),
        const Rect.fromLTRB(110, 100, 300, 180),
      );
      expect(
        UiGeometry.resize(start, UiHandle.top, d),
        const Rect.fromLTRB(100, 120, 300, 180),
      );
      expect(
        UiGeometry.resize(start, UiHandle.bottom, d),
        const Rect.fromLTRB(100, 100, 300, 200),
      );
      expect(
        UiGeometry.resize(start, UiHandle.topLeft, d),
        const Rect.fromLTRB(110, 120, 300, 180),
      );
      expect(
        UiGeometry.resize(start, UiHandle.bottomRight, d),
        const Rect.fromLTRB(100, 100, 310, 200),
      );
    });

    test('dragging the top-left corner outward makes it bigger', () {
      final r = UiGeometry.resize(
        start,
        UiHandle.topLeft,
        const Offset(-30, -30),
      );
      expect(r.size, const Size(230, 110));
      expect(r.bottomRight, start.bottomRight, reason: 'the far corner stays');
    });

    test('it never turns inside out', () {
      final r = UiGeometry.resize(start, UiHandle.right, const Offset(-500, 0));
      expect(r.width, UiGeometry.minSize);
      expect(r.left, start.left);
    });

    test('from the centre, both sides move', () {
      final r = UiGeometry.resize(
        start,
        UiHandle.right,
        const Offset(10, 0),
        fromCentre: true,
      );
      expect(r, const Rect.fromLTRB(90, 100, 310, 180));
    });

    test('a corner can keep the shape', () {
      final r = UiGeometry.resize(
        start,
        UiHandle.bottomRight,
        const Offset(100, 0),
        keepAspect: true,
      );
      expect(r.width / r.height, closeTo(start.width / start.height, 1e-9));
    });
  });

  group('a rectangle back into a slot', () {
    const parent = Size(1000, 500);

    test('pinned to a point: the pivot lands at the offset', () {
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.center,
        pivot: const Offset(0.5, 0.5),
      );
      const rect = Rect.fromLTWH(400, 200, 100, 50);

      final fitted = UiGeometry.fit(slot, rect, parent);
      slot
        ..offset = fitted.offset
        ..size = fitted.size;

      expect(fitted.size, const Size(100, 50));
      expect(slot.rectIn(parent), rect, reason: 'round trip');
    });

    test('stretched: the margins take the edges', () {
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.stretch,
      );
      const rect = Rect.fromLTRB(20, 30, 960, 470);

      final fitted = UiGeometry.fit(slot, rect, parent);
      slot.margin = fitted.margin;

      expect(fitted.margin, const EdgeInsets.fromLTRB(20, 30, 40, 30));
      expect(slot.rectIn(parent), rect);
    });

    test('another anchor, the same place', () {
      final slot = UiSlotComponent(
        mode: UiSlotMode.anchored,
        anchor: UiAnchor.topLeft,
        offset: const Offset(150, 120),
        size: const Size(100, 40),
      );
      final before = slot.rectIn(parent);

      final fitted = UiGeometry.fit(
        slot,
        before,
        parent,
        anchor: UiAnchor.bottomRight,
      );
      slot
        ..anchor = UiAnchor.bottomRight
        ..offset = fitted.offset
        ..size = fitted.size;

      expect(slot.rectIn(parent), before);
    });
  });

  group('snapping', () {
    test('a moving box lines up with a neighbour and says where', () {
      const targets = UiSnapTargets(rects: [Rect.fromLTWH(0, 0, 100, 40)]);
      final (moved, lines) = targets.move(
        const Rect.fromLTWH(103, 200, 50, 20),
        6,
      );
      expect(moved.left, 100);
      expect(lines.any((l) => l.vertical && l.position == 100), isTrue);
    });

    test('a guide attracts edges and centres', () {
      const targets = UiSnapTargets(yLines: [300]);
      final (moved, _) = targets.move(const Rect.fromLTWH(0, 285, 40, 30), 6);
      expect(moved.center.dy, 300);
    });

    test('with nothing near, the grid steps it', () {
      const targets = UiSnapTargets(grid: 10);
      final (moved, _) = targets.move(const Rect.fromLTWH(23, 47, 40, 30), 2);
      expect(moved.topLeft, const Offset(20, 50));
    });

    test('resizing snaps only the edge being dragged', () {
      const targets = UiSnapTargets(xLines: [305, 95]);
      final (sized, _) = targets.resize(
        const Rect.fromLTRB(100, 100, 302, 180),
        UiHandle.right,
        6,
      );
      expect(sized.right, 305);
      expect(sized.left, 100, reason: 'the other edge was not dragged');
    });
  });
}
