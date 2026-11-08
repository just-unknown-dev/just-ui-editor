/// The pieces a screen is built from: containers, panels, pictures and
/// controls.
///
/// Each maps onto a Flutter widget, so what the editor shows and what the
/// game runs are the same thing.
library;

import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A container, by what it does with its children.
enum UiLayoutKind {
  /// Left to right — Flutter's `Row`.
  row,

  /// Top to bottom — `Column`.
  column,

  /// Piled up, each placed by its own anchors — `Stack`.
  stack,

  /// In a line that wraps — `Wrap`.
  wrap,

  /// A grid of equal cells — `GridView`.
  grid,

  /// Scrolls when there is more than fits — `SingleChildScrollView`.
  scroll,

  /// Keeps clear of notches — `SafeArea`.
  safeArea;

  bool get isFlex => this == row || this == column;
  Axis get axis => this == row ? Axis.horizontal : Axis.vertical;
}

/// How children line up along and across a container.
enum UiFlexAlign {
  start,
  center,
  end,
  spaceBetween,
  spaceAround,
  spaceEvenly,
  stretch;

  MainAxisAlignment get main => switch (this) {
    start => MainAxisAlignment.start,
    center => MainAxisAlignment.center,
    end => MainAxisAlignment.end,
    spaceBetween => MainAxisAlignment.spaceBetween,
    spaceAround => MainAxisAlignment.spaceAround,
    spaceEvenly => MainAxisAlignment.spaceEvenly,
    stretch => MainAxisAlignment.start,
  };

  CrossAxisAlignment get cross => switch (this) {
    start => CrossAxisAlignment.start,
    center => CrossAxisAlignment.center,
    end => CrossAxisAlignment.end,
    stretch => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.center,
  };
}

/// A container: what it does with the entities under it.
class UiLayoutComponent extends Component {
  UiLayoutComponent({
    this.kind = UiLayoutKind.column,
    this.mainAxis = UiFlexAlign.start,
    this.crossAxis = UiFlexAlign.center,
    this.spacing = 0,
    this.padding = EdgeInsets.zero,
    this.columns = 3,
    this.tight = false,
  });

  UiLayoutKind kind;

  /// Along the container's direction.
  UiFlexAlign mainAxis;

  /// Across it.
  UiFlexAlign crossAxis;

  /// The gap between children.
  double spacing;

  EdgeInsets padding;

  /// For [UiLayoutKind.grid]: how many cells across.
  int columns;

  /// Whether the container takes only the room its children need.
  bool tight;

  @override
  String toString() => 'UiLayout(${kind.name})';
}
