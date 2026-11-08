// The text painter: laid out once, drawn every frame.

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void paintAt(UiTextPainter painter, double seconds) {
    final recorder = ui.PictureRecorder();
    painter.paint(
      Canvas(recorder),
      Offset.zero,
      animation: UiTextAnimation(seconds: seconds),
    );
    recorder.endRecording().dispose();
  }

  test('rainbow and pulse letters are laid out once, not every frame', () {
    final painter = UiTextPainter()
      ..set(
        text: UiRichText.parse(
          '[rainbow]Colours[/rainbow] [pulse]beat[/pulse]',
        ),
        style: const UiTextStyle(size: 16),
      );
    addTearDown(painter.dispose);

    paintAt(painter, 0);
    final laid = painter.glyphLayouts;
    expect(laid, greaterThan(0));
    for (var frame = 1; frame <= 30; frame++) {
      paintAt(painter, frame / 60);
    }

    expect(painter.glyphLayouts, laid, reason: 'only tinted as drawn');
  });

  test('changing the text lays its letters out again', () {
    final painter = UiTextPainter()
      ..set(
        text: UiRichText.parse('[rainbow]ab[/rainbow]'),
        style: const UiTextStyle(size: 16),
      );
    addTearDown(painter.dispose);
    paintAt(painter, 0);
    final before = painter.glyphLayouts;

    painter.set(
      text: UiRichText.parse('[rainbow]abc[/rainbow]'),
      style: const UiTextStyle(size: 16),
    );
    paintAt(painter, 0);

    expect(painter.glyphLayouts, greaterThan(before));
  });
}
