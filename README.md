# just_ui_editor

The in-game interface for `just_game_engine` (HUDs, menus, and text and buttons in the level) and the editor that builds it. Screens are asset files, drawn as real Flutter widgets over the game: a text field is a `TextField` and a button is a button. One package holds both halves: the runtime a game ships, and an editor that never ships. (Input splits them instead: `just_inputs` is the runtime, `just_input_editor` its editor.)

| Library | What it is | Who imports it |
|---|---|---|
| `package:just_ui_editor/just_ui_editor.dart` | The runtime: screens, components, systems, themes, bindings, actions | The game |
| `package:just_ui_editor/editor.dart` | `UiEditorModule`, the Interface editor | `lib/main_editor.dart` only |

The platformer template's `tool/check_release_imports.dart` fails if `editor.dart`, or anything under `src/editor/`, can be reached from `lib/main.dart`.

## What it saves

| File | What it is |
|---|---|
| `assets/ui/pause.ui.json` | One screen: a canvas and everything under it |
| `assets/ui/screens.json` | The game's list of screens, and its default theme |
| `assets/ui/default.uitheme.json` | A theme: colour roles, text styles, sounds |

A screen (`UiDocument`):

```json
{
  "format": 1,
  "name": "Pause",
  "entities": [
    {"name": "Pause", "parentName": null, "components": [...]},
    {"name": "PauseCard", "parentName": "Pause", "components": [...]}
  ],
  "editor": {"guides": [], "samples": {}, "device": {...}}
}
```

The first entity is the canvas, and every other entity sits under it. Parents are named, never numbered, because entity ids are handed out again each time a file is read. Siblings keep the order the file lists them in. The canvas's `visible` is not saved. Whether a screen is open is decided while the game runs, not in the file. The `editor` block (guides, sample values, the device) is the editor's alone, and a game never reads it. `UiDocument.currentFormat` is 1. A file from a newer format is refused rather than half read.

The list (`UiScreenManifest`):

```json
{
  "format": 1,
  "theme": "assets/ui/default.uitheme.json",
  "screens": [
    {"path": "assets/ui/hud.ui.json", "startOpen": true},
    {"path": "assets/ui/pause.ui.json"}
  ]
}
```

A screen marked `startOpen`, such as a HUD, shows from the first frame. The rest wait to be opened by name, which is the canvas's name. `theme` is the theme for any canvas that does not name its own, and for the text and buttons placed in the level.

A screen file that will not read (a component from a plugin the game does not have, a value of the wrong kind) is left out and said so in the log; nothing of it is built. A game with no screen list, or one that will not read, runs with no screens. A value of the wrong kind is a `FormatException` that names it.

Screens used to live inside a level's scene. `UiSceneExtractor.extract(scene)` splits such a scene into the scene without its canvases, one `UiDocument` per canvas, and a list entry for each.

## Adding it to a game

```dart
// With the game's other extensions, so a level can hold text and buttons:
final engine = Engine(
  config: const EngineConfig(extensions: [JustGameUi.extension]),
);
await engine.initialize();

// Once the engine exists:
await JustGameUi.install(engine); // reads assets/ui/screens.json
```

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/ui/
```

Every argument to `install` is optional:

| | |
|---|---|
| `manifest` | Where the list is. `assets/ui/screens.json` by default |
| `screens` | A `UiScreenManifest` to use instead of reading one |
| `read` | Reads a text asset. The app bundle when null |
| `input` | The actions that work menus from a pad. `UiInputActions()` means `ui/navigate`, `ui/submit` and `ui/cancel`; null leaves menus to the keyboard, mouse and touch |
| `localise` | Turns a `@key` into words, in screens and in the level's own text and buttons |
| `onSound` | Plays a UI sound by path: the theme's hover, press and toggle sounds |
| `fonts` | A folder in the bundle whose font files are all loaded at boot (`UiFonts.loadFolder`). `assets/fonts/` by default; null loads none |

What `install` puts into the engine:

- **`UiScreens`**: every screen on the list, built once, in a `World` of their own with a `UiSystem`, a `TimelineSystem` and the navigator. Loading or clearing a level leaves them alone.
- **`UiScreensPlugin`**, an `EnginePlugin`, ticks that world every frame, paused or not and with no widget on screen. A pause menu keeps working while the game it paused is stopped.
- **`UiScreensLayer`**, a `GameLayer` on `engine.layers`, draws the screens over the game in every `GameWidget`, and tells buttons in the level where the pointer is.
- A `UiSystem` and a `UiPointerSystem` in the level's world, for text and buttons placed there (`registerUiSystems`).
- The theme and the language those are drawn with, on the engine's context (`UiWorldStyle`).

Installing again replaces the screens and hands the level's systems the new `localise` and `onSound`. `JustGameUi.uninstall(engine)` takes out the screens, their layer and the language; the components stay known to the engine, since a level may still hold them.

## Opening screens

```dart
final screens = JustGameUi.of(engine)?.screens;
screens?.push('Pause');     // over what is open
screens?.back();            // closes the one on top
screens?.isOpen('Pause');
screens?.show('Hud');       // a screen goes on the stack; a layer appears
screens?.hide('Hud');
screens?.closeAll();        // every screen; the layers stay
screens?.reset();           // every screen as it was first built: a restart
screens?.reloadFrom(manifest, read: read); // read every file again
```

A button does the same by name: `ui.push Pause`, `ui.back`. A screen opens by its canvas's name, whatever else is called that; pushing a layer (a canvas that is not a screen) just shows it. Two screens may each hold an element of one name: `ui.show`, `ui.hide` and `timeline.play` look in the screen they are run from, or the one on top, first. Screens stack in `sortOrder` order, and among screens of one order, in the order they were opened.

Android's back button and gesture (and a browser's back) close the screen on top while one is open. Once the interface is installed, `UiActions.defaults` answers `ui.push`, `ui.back`, `ui.show`, `ui.hide` and `ui.toggle` for whatever the game's `UiActions.host` leaves unset. So a game sets only what it handles itself:

```dart
UiActions.host = UiActionHost(pause: engine.pause, resume: engine.resume);
```

## What a screen reads, does and places

A saved file cannot hold a Dart closure, so a screen names things and the game says what the names mean:

```dart
UiBindings.register('coins', () => signals.collected.value);  // "Coins: {coins}"
UiActions.register('restart', (_) => restart());                // custom:restart
UiWidgets.register(UiWidgetDefinition(
  id: 'touch_controls',
  label: 'Touch controls',
  build: (context) => TouchControls(engine: engine),
  props: [UiWidgetProp('jumpLabel', 'Jump label', UiPropKind.text)],
));
```

- **Bindings.** `{coins}`, with a format after a colon: `{time:mm:ss}`, `{score:n0}`, `{health:0.0}`, `{fill:%}`. `{{` writes a plain brace. `UiBindings.registerForEntity('health', (e) => …)` offers `{self.health}`, read from the entity the text belongs to. A name nobody offers stays on screen as written, and a number that is not finite is written `Infinity` or `NaN`.
- **Languages.** A text that starts with `@` is a key: `@menu.resume`. It is looked up through `install(localise:)` on every label the inspector offers it for: texts, buttons, toggles, sliders, dropdowns and a field's hint.
- **Actions.** The built-ins are in `UiActions.builtIns`: `signal`, `timeline.play`, `timeline.stop`, `scene.load`, `ui.show`, `ui.hide`, `ui.toggle`, `ui.push`, `ui.back`, `game.pause`, `game.resume`, `game.quit`, `audio.play`. `custom:<name>` runs one the game registered.
- **Widgets.** A registered widget can be placed from the editor like a built-in one, with its props in the inspector, saved as a `UiCustomComponent`.

Text also takes tags: `[b]`, `[i]`, `[color=…]`, `[size=…]`, `[font=…]`, `[icon=…]`, `[wave]`, `[shake]`, `[rainbow]`, `[pulse]`, `[link=…]`, `[br]`.

- `[icon=name]` draws what `UiIcons` has under that name: `UiIcons.register('heart', Icons.favorite)` (a glyph, drawn everywhere) or `UiIcons.registerWidget('coin', (size) => Image.asset(…))` (a widget, drawn in screens only). A name nobody registered draws nothing.
- `[link=shop]Shop[/link]` runs `custom:shop` when tapped; a built-in takes its argument after a space, `[link=ui.push Credits]`. Links work in screen text that Flutter draws, not in world text or painted text.
- `[wave]`, `[shake]`, `[rainbow]`, `[pulse]`, an outline, a gradient, and the Shrink overflow are drawn by the canvas painter, in a screen as in the level. A gradient does not combine with the moving tags.
- In a screen, text always wraps at its box; `wrap` and Min font size are for the level's text (and for Shrink).

Register the bindings and the widgets in the editor too, so it can draw screens as the game does and offer the names. Leave the actions out. In the editor's Preview, a button says what it would do rather than doing it. The template splits these three into `registerBindings`, `registerActions` and `registerWidgets` in `lib/game/ui/game_ui.dart`, and `lib/main_editor.dart` calls only the first and the last.

## Themes and fonts

A widget names a *role*, not a colour, so restyling a game means editing one file. A `.uitheme.json` (`UiTheme`) holds colour roles (`primary`, `onPrimary`, `surface`, `onSurface`, `accent`, `danger`, `success`, `muted`, `outline`), text styles by role (`body`, `title`, `heading`, `button`, `caption`, `value`, and any others a game names), a default corner radius and gap, and the sounds a menu makes (`hover`, `press`, `toggle`).

A canvas names its theme. `UiThemes` reads it when the canvas is first drawn and keeps it. Until it arrives, the canvas draws with `UiThemes.fallback`. A theme that will not load is the fallback, and is not read again until `UiThemes.evict` forgets it. A tool replaces `UiThemes.loader` to read project files instead of the bundle.

Font files are loaded while the game runs, grouped into families by file name (`Inter-Bold.ttf` is `Inter`). `install` loads every font under `assets/fonts/` (`UiFonts.loadFolder`), so the families the editor offers from that folder are the ones the game draws. The folder must be listed under `flutter: assets:`, but `pubspec.yaml` needs no `fonts:` section. `UiFonts.loadAll(paths)` loads any others.

## Text and buttons in the level

`TextComponent` and `ButtonComponent` also work in a level's own world. They sit at an entity's transform and are painted on the game canvas, with the same styles, tags, bindings and language as a screen, in the screen list's theme (`UiWorldStyle`). Use them for a sign, a name over a head or a damage number. `install` adds their systems, and the layer passes them the pointer.

A button is pressed where it is drawn, turned and scaled with its entity, and the higher `layer` takes a press where two overlap; Can be pressed off draws it faded. The pointer reaches it only through what the screens let through: a press on a HUD button, or anywhere under a modal screen, is not a press in the world. It follows one pointer at a time (the first finger down), and a press made while the game is paused does not land when it resumes. Hover and press play the theme's sounds through `onSound`.

## The editor

```dart
// lib/main_editor.dart — never lib/main.dart
import 'package:just_ui_editor/editor.dart';

final plugin = await JustGameEditorPlugin.register(
  engine: engine,
  modules: [UiEditorModule()], // root: the project folder; the working directory by default
);
```

**Interface** opens from its toolbar button, from **Ctrl+Shift+U** (**Cmd+Shift+U** on macOS), or by opening a `.ui.json` or `.uitheme.json` from the Assets dock. It has three columns:

- **Left:** the Screens list, the Hierarchy, and the Widgets palette. Screens shows every screen file. One not on the game's list is faded, with a button to add it, and a toggle sets whether a screen starts open. **+** makes a Screen (opened and closed) or a Layer (always there, like a HUD). Right-click a screen to rename, duplicate, delete it, or take it off the list.
- **Middle:** a toolbar, the device frame, and a preview strip. The toolbar has device presets (Phone, Small phone, Tablet, Laptop, Desktop, or a size of your own), rotate, zoom, snap, grid (right-click for the step), rulers, guides, outlines on every element, and Edit or Preview. The strip shows other screens under this one, forces every button into a state (hover, pressed, off), scales the text to 130% or 160%, sets sample values for bindings, replays the opening transition, and says what the last button pressed in Preview would have done.
- **Right:** the Inspector and Theme tabs.

The header shows the file, a dot while there is unsaved work, Save, Undo and Redo, full screen and close. Each screen is its own document with its own undo and its own Save, and the theme likewise. The editor asks before leaving unsaved work, including when something opens another workspace over it.

**On the canvas.** Below, Ctrl is Cmd on macOS. Drag to move, snapping to edges, centres and guides; hold Ctrl to place freely. The selection has eight resize handles. Drag on empty space for a marquee. Shift- or Ctrl-click adds to the selection, and Alt-click picks the container instead of the element. In a row or column, dragging a child reorders it. Drag guides out of the rulers, and drag them back to remove them. The wheel pans (Shift sideways), and Ctrl+wheel or a pinch zooms at the pointer. A right-click offers cut, copy, paste, duplicate, delete, select the container, bring to front, send to back, and hide. Drop palette tiles on the canvas or on a hierarchy row. Clicking a tile adds the element inside the selected container, on screen. The inspector has align and distribute, and anchor presets that keep the element where it is. Copy, cut, paste and duplicate take the children along, give every copy a free name, and keep a switched-off element switched off; a duplicate goes beside its own original. Every drag is one undo step, and a drag given up with Esc leaves none. Right-click a hierarchy row to switch an element off or on: that is saved, unlike the eye.

**Preview** plays a copy of the screen: toggles, sliders, typing and Back change the copy, never the screen that is saved. An edit made while Preview is on starts the copy again.

**Files.** New screens, copies and renames never take a file another screen has: two names can share one (`Main Menu` and `MainMenu` are both `main_menu.ui.json`), and the editor offers a free name instead. A screen's name must also differ from every other screen's and from its own elements'. Every write is whole or not at all, and stays inside the project. While `screens.json` does not read, the Screens panel says so and the editor writes nothing to it; the Problems dock says so too. Every file the editor writes, moves or deletes is reported to the editor, so the Assets dock and the next play-test read it again.

| Keys | |
|---|---|
| Ctrl+S | Save |
| Ctrl+Z / Ctrl+Y | Undo / redo: the theme's while its tab shows, the screen's otherwise |
| Ctrl+D, Ctrl+C, Ctrl+X, Ctrl+V | Duplicate, copy, cut, paste |
| Ctrl+A | Select everything but the canvas |
| Ctrl+0 / Ctrl+1 / Ctrl+= / Ctrl+- | Fit / 100% / zoom in / zoom out |
| Ctrl+P | Edit or Preview |
| Delete (Backspace too on macOS) | Delete |
| F2 | Rename |
| Arrows / Shift+arrows | Nudge 1 px (a grid step with the grid on) / 10 px |
| Esc | One step back: cancel a drag, leave Preview, clear the selection, close |

**Outside the workspace**, the module also adds:

- inspector rows for the interface's field types (text styles, actions, anchors, theme roles), which text and buttons in a level use too;
- Problems dock checks (`UiChecks`) of every screen on the list: a missing or unreadable file or list, two screens with one name, `ui.push` to a screen not on the list or to a layer, an action, binding, widget or `[icon=…]` the game does not register, a `[link=…]` that cannot be clicked, a button that does nothing, a slider from more to less, a choice offered twice, a `flex` or a stretching spacer outside a row or a column, a theme that is not there or does not read, and a screen with nothing to focus;
- the level's own text and buttons drawn in the game's theme (the screen list's);
- a **Text** prefab in every Level Designer palette;
- **Move screens out of the level**, a command and a right-click on a canvas in the scene tree (`UiLevelScreens.moveOut`). It writes each canvas still in the level to a `.ui.json`, lists it, and takes it out of the level in one undoable step. The files stay after an undo;
- the game's screens over the viewport while a play-test runs, and only then.

The theme is edited in the Theme tab. Every edit shows on the canvas at once, and nothing is written until Save. Edits that are discarded — the editor closed without saving, another theme opened — are dropped everywhere: the screens, the level's text and the next play-test go back to the file.


## Tests

`flutter test`: 343 tests, runtime and editor.

