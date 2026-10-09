/// The screens a piece of interface is checked against.
library;

import 'package:flutter/painting.dart';

/// One screen to preview a canvas on.
class UiDevice {
  const UiDevice(
    this.name,
    this.width,
    this.height, {
    this.top = 0,
    this.bottom = 0,
  });

  /// A size of the author's own.
  factory UiDevice.custom(double width, double height) =>
      UiDevice('Custom', width, height);

  final String name;

  /// Its size in logical pixels, upright.
  final double width;
  final double height;

  /// What a notch or a status bar takes at the top, upright.
  final double top;

  /// What a home indicator takes at the bottom, upright.
  final double bottom;

  bool get isCustom => name == 'Custom';

  /// Its size, turned on its side when [landscape].
  Size sizeFor({required bool landscape}) =>
      landscape ? Size(height, width) : Size(width, height);

  /// The part a canvas keeps clear of when it asks for the safe area: the
  /// notch goes to the left when the device is turned.
  EdgeInsets insetsFor({required bool landscape}) => landscape
      ? EdgeInsets.only(left: top, right: bottom)
      : EdgeInsets.only(top: top, bottom: bottom);

  Map<String, dynamic> toJson() => {
    'name': name,
    'width': width,
    'height': height,
    if (top != 0) 'top': top,
    if (bottom != 0) 'bottom': bottom,
  };

  factory UiDevice.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Custom';
    for (final preset in UiDevices.all) {
      if (preset.name == name) return preset;
    }
    return UiDevice(
      name,
      (json['width'] as num?)?.toDouble() ?? 1280,
      (json['height'] as num?)?.toDouble() ?? 720,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UiDevice &&
      other.name == name &&
      other.width == width &&
      other.height == height &&
      other.top == top &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(name, width, height, top, bottom);

  @override
  String toString() => '$name (${width.toInt()}×${height.toInt()})';
}

/// The screens the picker offers: shapes that actually differ.
abstract final class UiDevices {
  static const phone = UiDevice('Phone', 393, 852, top: 47, bottom: 34);
  static const phoneSmall = UiDevice('Small phone', 360, 640, top: 24);
  static const tablet = UiDevice('Tablet', 834, 1194, top: 24, bottom: 20);
  static const laptop = UiDevice('Laptop', 1280, 800);
  static const desktop = UiDevice('Desktop', 1920, 1080);

  static const List<UiDevice> all = [
    phone,
    phoneSmall,
    tablet,
    laptop,
    desktop,
  ];
}
