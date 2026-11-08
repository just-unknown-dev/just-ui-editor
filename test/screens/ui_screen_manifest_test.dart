// The screen list: what it reads and writes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the screen list reads and writes itself', () {
    final manifest = UiScreenManifest.fromJson({
      'theme': 'assets/ui/default.uitheme.json',
      'screens': [
        {'path': 'assets/ui/hud.ui.json', 'startOpen': true},
        {'path': 'assets/ui/pause.ui.json'},
      ],
    });

    expect(manifest.theme, 'assets/ui/default.uitheme.json');
    expect(manifest.screens, const [
      UiScreenEntry(path: 'assets/ui/hud.ui.json', startOpen: true),
      UiScreenEntry(path: 'assets/ui/pause.ui.json'),
    ]);
    expect(
      UiScreenManifest.fromJson(manifest.toJson()).screens,
      manifest.screens,
    );
  });
}
