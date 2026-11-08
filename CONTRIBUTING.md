# Contributing to Just UI Editor

Thank you for your interest in contributing to **Just UI Editor**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-ui-editor/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the output of `flutter --version`, and the platform (Android, iOS, Linux, macOS, Windows, web; for the web, the browser and whether it was a JavaScript or a WebAssembly build);
- where it happens: in a running game, in the Interface editor (in Edit or in Preview), or both;
- the screen's `.ui.json`, or the smallest part of it that shows the problem, and the game's `assets/ui/screens.json`; for a problem with how things look, the `.uitheme.json` too;
- for text or a button placed in a level, the entity's saved `UiTextComponent` or `UiButtonComponent` from the scene file;
- for a layout bug, the screen size or the editor's device preset, the canvas's design size, scale mode and safe area, and a screenshot;
- for a binding, an action or a custom widget, what the game registers with `UiBindings.of(context).register`, `UiActions.of(context).register` or `UiWidgets.of(context).register`, and on which engine's context;
- for a menu worked from a gamepad, the `UiInputActions` given to `JustGameUi.install`, and whether those actions fire in `just_inputs` on their own. If they don't, the bug belongs in [just_inputs](https://github.com/just-unknown-dev/just-inputs/issues);
- for an editor bug, what you clicked or pressed, and any lines it left in the editor's Console.

A bug in the engine itself (scenes, `GameWidget`, `engine.layers`, timelines) belongs in [just_game_engine](https://github.com/just-unknown-dev/just-game-engine/issues). A bug in the editor around the Interface workspace (its docks, the scene tree, play-testing) belongs in `just_game_engine_editor`.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is the in-game interface and the editor that builds it: screens and the screen list, themes and fonts, text styles and tags, bindings, actions, game-registered widgets, and text and buttons in the level. Running the game loop is `just_game_engine`'s job, and turning device input into actions is `just_inputs`'. A change to a saved format (`.ui.json`, `screens.json`, `.uitheme.json`, or a component's saved fields) affects every game's files, so open the issue first and agree the approach before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Dart | 3.12.0 |
| Flutter | 3.47.1 |

Those are this package's own constraints (`pubspec.yaml`), and the floor of `just_game_engine` (Flutter GPU, `just_box_2d` and `just_jolt`).

There is no app to run here: you work on the package and its tests. To try a change in a real game, add the package to the game as a path dependency (`path: ../just_ui_editor`). The game imports `package:just_ui_editor/just_ui_editor.dart`. Only its editor entry point imports `package:just_ui_editor/editor.dart` and passes `UiEditorModule()` to `JustGameEditorPlugin.register`.

`flutter pub get` resolves every dependency from pub.dev. To work against a version that is not published yet, see [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies).

```bash
git clone https://github.com/just-unknown-dev/just-ui-editor.git just_ui_editor
cd just_ui_editor
flutter pub get
flutter test
```

If you're working from the Just engine monorepo, run every command from `plugins/just_ui_editor`.

---

## Working Against Unpublished Dependencies

The package's `just_*` dependencies are `just_game_engine`, `just_inputs` and `just_signals`, which the runtime uses, and `just_editor_core`, which only `lib/editor.dart` reaches: `pubspec.yaml` marks it design-time only. `just_game_engine_editor` is a dev dependency, for the tests that host the module in a real editor. All of them are on pub.dev. Check one out when your change needs an unreleased version, put the checkout next to this repository, and point the package at it with a `pubspec_overrides.yaml` in the repository root:

```yaml
# pubspec_overrides.yaml: local only; .gitignore keeps it out of commits.
dependency_overrides:
  just_game_engine:
    path: ../just_game_engine
  just_editor_core:
    path: ../just_editor_core
  just_game_engine_editor:
    path: ../just_game_engine_editor
  just_inputs:
    path: ../just_inputs
  # A dependency of a dependency is overridden the same way:
  just_game_engine_formats:
    path: ../just_game_engine_formats
```

Then run `flutter pub get`. Delete an entry and run `flutter pub get` again to go back to the published version.

Do not change `pubspec.yaml` to a path dependency. If your pull request needs a version of a dependency that is not published yet, say which one in the pull request: this package can only be released after it.

No other package depends on this one; games do. A game lists it under `dependencies`, not `dev_dependencies`, because the runtime ships with the game. `just game doctor` (from `just_game_engine_cli`, run by `just doctor`) allows that for this package alone of the `just_*_editor` packages. The Asset Store reads `just_store.json` to wire the package into a game. If you change the public API, `just_store.json` or a saved format, say in the pull request what a game will need to change.

---

## How the Package Fits Together

One package holds two libraries: the runtime a game ships, and an editor that never ships. `lib/src/` is laid out by feature, one folder each, and each folder has one barrel named after it (`text/text.dart`) that exports what the folder makes public; a file no barrel exports marks its public declarations `@internal`. The features sit in layers, and a feature imports only its own layer or those below — `test/library_layout_test.dart` checks all of it.

| Layer (bottom first) | Folder | Contents |
|---|---|---|
| 1 | `lib/src/text/` | `UiTextStyle`, rich-text tags (`UiRichText`), `UiIcons`, `UiTextPainter`, `UiFonts` |
| 1 | `lib/src/bindings/` | `UiBindings`; `UiAction`, `UiActionList`, `UiActionHost` and `UiActions`: what a screen reads from the game and does to it |
| 2 | `lib/src/theme/` | `UiTheme`, `UiPalette`, `UiSounds`; `UiThemes`, which loads and keeps them; `UiWorldStyle`, the look of the level's own text |
| 3 | `lib/src/layout/` | `UiCanvasComponent`, `UiSlotComponent` and `UiAnchor`, `UiLayoutComponent` (`UiFlexAlign`), `UiPanelComponent`, `UiSpacerComponent` |
| 4 | `lib/src/controls/` | `UiElementComponent`, `UiTextComponent`, `UiButtonComponent`, the other controls, `UiWidgets` (widgets a game registers), `UiTextSystem` |
| 5 | `lib/src/world/` | Text and buttons in the level: `UiTextComponentPainter`, `UiButtonComponentPainter`, `UiPointerSystem`, `registerUiSystems` |
| 6 | `lib/src/serialization/` | How it is saved: `UiScreenDefinitions`, `UiWorldDefinitions`, `UiFieldTypes`, `UiMigrations` (the renames), and the components extension (`@internal`) |
| 7 | `lib/src/screens/` | `JustGameUi`; screens as files (`UiDocument`, `UiScreenManifest`) and as widgets (`UiScreens`, `UiScreensPlugin`, `UiScreensLayer`, `UiLayer` and its parts, `UiNavigator`, `UiInputBridge`) |
| 8 | `lib/src/editor/` | The Interface editor: `UiEditorModule` and `UiEditorWorkspace` at its top, then, bottom first, `project/` (`UiProject`, `UiLevelScreens`, `UiSceneExtractor`, `UiChecks`), `document/`, `geometry/`, `session/`, `inspector/`, `canvas/`, `panels/` |
| | `lib/just_ui_editor.dart` | The runtime library, the only one a game imports: the seven runtime barrels |
| | `lib/editor.dart` | The editor library: `src/editor/editor.dart`. Only an editor entry point imports it |
| | `just_store.json` | The Asset Store manifest (a `kit`, shown as Interface). It names the runtime extension (`JustGameUi.extension`), the editor module (`UiEditorModule`), and the editor-only libraries (`editor.dart`, `src/editor/`) |
| | `test/` | Mirrors `lib/src/`: `test/<feature>/…`, and `test/editor/<part>/…`. `test/support/` holds the runtime tests' helpers |

A few rules hold the package together. Keep them:

- **The runtime never reaches the editor.** Nothing outside `lib/src/editor/` imports it, `lib/editor.dart`, `just_editor_core`, `just_game_engine_editor` or `just_signals`. The editor imports the runtime, never the other way round. `test/library_layout_test.dart` checks it, and that `lib/just_ui_editor.dart` reaches nothing under `src/editor/`. A game's release check (`just game check release-imports`, from `just_game_engine_cli`) fails too when the game's entry point reaches a library that `just_store.json` lists under `editor.editorOnlyLibraries`.
- **Each engine has its own.** `UiBindings`, `UiActions`, `UiWidgets`, `UiIcons`, `UiThemes`, `UiFonts` and `UiWorldStyle` live on an `EngineContext` (`UiBindings.of(context)`), never in a static, so two engines — a game and an editor's preview — never share them. Code that reads them finds the context through the world it has (`entity.world!.context`, `widget.world.context`). Keep new state the same way.
- **The runtime runs wherever the game does**, the web included, so it never touches files. It reads assets through seams: the context's bundle by default, the `read` argument of `JustGameUi.install`, and the engine's `UiThemes.loader` and `UiFonts.read`. The editor replaces them to read the project from disk. File access lives in the editor, in `UiProject`.
- **Saved files must keep loading.** A screen (`UiDocument`) carries `format: 2` and the screen list (`UiScreenManifest`) `format: 1`; both refuse a newer format rather than half-read it. A theme (`UiTheme`) writes `formatVersion: 1`. A new field is optional, with a default that keeps the old behaviour, and then needs no new format. A change old files cannot take raises `UiDocument.currentFormat` and adds a step to `UiDocument`'s private `_steps`. Never rename or reuse a key without a migration, and add a test that reads JSON written before your change.
- **A screen file links by name.** Each entity is `{name, parentName, components}`: the canvas first, parents before children, siblings in file order. Entity ids are handed out afresh on every read, so they are never saved, and `ParentComponent` and `ChildrenComponent` are rebuilt from the names. The canvas's `visible` is not saved: whether a screen starts open is the game's choice (`startOpen` in `screens.json`). The `editor` block (guides, sample values, the device) is the editor's alone, and the runtime never reads it.
- **Saved names change only with a migration.** Files hold component types (`UiCanvasComponent`, `UiTextComponent`, …), field names, the definition ids `text_effcff19` and `button_388d5c40`, enum values (saved by name), action kinds (`UiActions.builtIns`) and text tags (`[b]`, `[color=…]`). To rename a component, add the old name to `UiMigrations.renamedTypes` (keep the old entries: renames chain). The engine applies it to every scene, prefab and timeline it loads, whatever the format, and `UiDocument` to every screen (a format step, and the reader's `context.migrations`). Add a test that an old scene and an old `.ui.json` load (`test/serialization/ui_migrations_test.dart`).
- **Files name things; the game says what the names mean.** A button saves a `UiActionList` of `{kind, arg}`, a text saves `{coins}`, a custom widget saves its `widgetId`, and the game fills its engine's `UiActions`, `UiBindings` and `UiWidgets`. A file never holds a closure. A name nobody registered must not take the game down: an unknown action does nothing, and an unknown binding stays on screen as written. `UiChecks` reports them in the Problems dock instead, and stays quiet while the game has registered nothing, because then it cannot tell.
- **Definitions are built in getters.** `UiScreenDefinitions` and `UiWorldDefinitions` make each definition in a getter, not a `static final`, so `JustGameUi.extension` can put the current code in place after a hot reload; `test/serialization/ui_components_extension_test.dart` checks it. A new component goes in `UiScreenDefinitions.all` (screens) or `UiWorldDefinitions.all` (the level). A new field type needs an inspector row in `UiFieldEditors.all`, found by its `id`. A new element for the palette goes in `UiCreateOptions.builtIns`.
- **The layer only notices what it is told.** `UiLayerState` rebuilds one node when `_revisionOf` changes, and the tree when `_structure` changes (both in `lib/src/screens/ui_layer.dart`; what each kind of element becomes is in its part `ui_element_builders.dart`). A field you add to a UI component must be in one of them, or the screen will not show the change. A new UI component type must also be in `_UiParts`, the components the layer looks up once per walk: it walks the tree again only when the world's `structureVersion` moves (an entity made, destroyed, switched or re-parented, a component added, removed or replaced) or a canvas is shown, hidden or reordered. Code that reorders a `ChildrenComponent`'s list in place calls `world.markStructureChanged()` (or the layer's `markDirty()`).
- **Edits are undoable, and reach disk on Save.** Edits to a screen go through its `UiScreenDocument.history`, and edits to the theme through `UiThemeDocument.history`. A drag's `UiSlotEditCommand`s merge, so a whole drag is one undo step. File operations write at once instead: creating, duplicating, renaming or deleting a screen, and changing the game's list in the Screens panel. So does **Move screens out of the level** (`UiLevelScreens.moveOut`), whose files stay after an undo. Write files through `UiProject`: it writes a `.saving` file and renames it into place, so a crash never leaves half a screen, and it writes JSON with two-space indents and a final newline. Change the screen list only through `UiProject.updateManifest`, which reads the list on disk first: a copy read earlier would write over whatever changed it since.
- **Preview never touches the game.** In Preview, buttons run against a private `UiActionHost`, and the preview strip says what they would have done. The game's own screens show over the editor's viewport only while a play-test runs.
- **The module is not a Level Designer.** Its Text prefab is in `sharedPrefabs`. A module with `prefabs` counts as a designer (`EditorModule.providesLevelDesigner`), so don't move it there.

---

## Running the Tests

Run the commands from the repository root.

```bash
# The whole suite: runtime and editor.
flutter test

# The editor's tests only.
flutter test test/editor

# One file.
flutter test test/screens/ui_screens_test.dart
```

**Runtime and editor tests.** `test/` mirrors `lib/src/`. The runtime's tests (every folder but `test/editor/`) import `just_ui_editor.dart`, the engine and `just_inputs`, and nothing from the editor, so they see the package the way a game does. Keep it that way. The editor's tests are in `test/editor/`, by the part they test. `test/library_layout_test.dart` checks the layout, the layers, the runtime/editor split, that no name is exported by both libraries, and that `just_store.json` agrees with `pubspec.yaml`.

**The saved formats.** `test/screens/ui_document_test.dart` pins the screen file (canvas first, parents by name, no ids, no `visible`, a newer format refused), `ui_screen_manifest_test.dart` the screen list, and `test/editor/project/ui_scene_extractor_test.dart` the extractor that takes screens out of an old scene. `test/text/`, `test/bindings/`, `test/theme/` and `test/world/ui_world_test.dart` check that text styles, actions, themes, text and buttons survive a save, and `ui_world_test.dart` also reads text and buttons from a version 4 scene. `test/serialization/ui_migrations_test.dart` reads scenes and screens saved before the renames. Add to them when you touch a saved format.

**Writing tests.** The registries are per engine context, so a test needs no clean-up: a world made with `uiWorld()` (`test/support/ui_test_support.dart`) has a context of its own, and `uiWorld(context)` shares one between a test's worlds; register on that context (`UiBindings.of(context)`). A test that runs a whole `Engine` registers on `engine.context`. An editor test that needs files writes a small project into `Directory.systemTemp.createTempSync(...)` and hands it to `UiProject` or `UiEditorModule(root:)`. Drive widgets as a person would: tap, drag, type and press keys. `test/editor/ui_editor_workspace_test.dart` drags on a 1920×1080 design shrunk onto a phone, where a drag that forgets the scale shows at once.

---

## Coding Guidelines

- **Formatting.** Code is formatted with `dart format`. Format the files you change, for example `dart format lib/src/screens/ui_layer.dart test/screens/ui_layer_test.dart`. The whole package is format-clean.
- **Analysis.** `flutter analyze` must report no issues at all: no errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`.
- **The runtime and editor split.** Code a game needs goes in a runtime feature folder and is exported through its barrel and `lib/just_ui_editor.dart`. Editor code goes under `lib/src/editor/` and is exported through `src/editor/editor.dart` and `lib/editor.dart`. If you rename `UiEditorModule` or `JustGameUi.extension`, or put editor code anywhere else, update `just_store.json`, and keep its `version` and `requires` equal to `pubspec.yaml`'s. `test/library_layout_test.dart` checks all of this.
- **Web and WebAssembly.** The runtime runs on every Flutter platform, including web builds compiled to JavaScript and to WebAssembly. Nothing outside `lib/src/editor/` may import `dart:io` or `dart:html`; the layout test checks that too. The editor reads and writes files through `just_editor_core/io.dart`.
- **Words.** Text the player or designer sees uses British spelling ("colour") and sentence case. Identifiers follow Flutter (`colorRole`), and saved names, such as the `[color=…]` tag, stay as they are.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update [README.md](README.md) if the public API or a saved file changes.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.
- **Dependencies.** Do not add a dependency without discussing it in an issue first. One the runtime imports ships in every game.
- **Structure.** A file goes in the feature it belongs to and is named after its main class; a new top-level folder takes a layer in `test/library_layout_test.dart`. Games and other packages import `lib/just_ui_editor.dart` and `lib/editor.dart`, not files under `lib/src/`.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b fix/hero-flight-on-reopen
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format <the files you changed>
   flutter analyze
   flutter test
   ```
4. Commit with a [conventional commit message](#commit-message-convention).
5. Push to your fork and open a pull request against `main`. Say what changed and why. List any unpublished dependency version it needs, any change to a saved format or to `just_store.json`, and what a game will need to change. For a change you can see in the editor or on a screen, add before and after screenshots.
6. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Use the area as the scope. For the runtime, that is its feature folder under `lib/src/`: `text`, `bindings`, `theme`, `layout`, `controls`, `world`, `serialization` or `screens`. For anything under `lib/src/editor/`, use `editor`. Mark a change that breaks the public API or a saved format with `!` and a `BREAKING CHANGE:` footer.

**Examples:**
```
fix(screens): keep a hidden element from taking room in a row
feat(bindings): add an audio.stop built-in action
fix(editor): make one drag one undo step at any zoom
docs(contributing): explain the runtime and editor split
```

---

## License

By contributing to Just UI Editor you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).
