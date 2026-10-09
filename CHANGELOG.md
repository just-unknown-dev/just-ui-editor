# Changelog

## 0.1.0 (unreleased)

- **Hot reload reaches the interface's components.** `JustGameUi.extension` is a `RefreshableExtension`: after a hot reload the editor puts `UiDefinitions` and `UiSchemas` in place again from the code as it now is, so a field added to one shows in the inspector without a restart. Both are getters now rather than `static final`s, which a reload never rebuilds.

- **Ready for 3-D.** `UiPointer` carries the camera's `ray` when the camera is in space (not a plain 2-D one): a world-space button is then hit where the ray crosses its own depth. A 2-D pointer is unchanged. Screens open their scene with the engine 2.0 `openScene(scene, rootOrder:)`.

First release. The in-game interface leaves the engine and the engine editor and moves into this package, runtime and editor both, as `just_inputs` does. Screens become asset files of their own.

### Moved here

- **From `just_game_engine`**: the whole interface runtime. That covers text (`UiTextStyle`, rich-text tags, `UiTextPainter`, `UiFonts`), themes (`UiTheme`, `UiThemes`), `UiBindings`, `UiActions`, `UiWidgets`, `UiLayer`, `UiNavigator`, `UiInputBridge`, the canvas, slot and element components, world-space `TextComponent` and `ButtonComponent`, `UiSystem`, `UiPointerSystem`, `registerUiSystems`, and their codecs (`UiDefinitions`, `UiSchemas`, `UiFieldTypes`). Type strings and ids are unchanged, so saved scenes still read. The engine keeps no UI.
- **From `just_game_engine_editor`**: the interface editor, the inspector rows for the interface's field types, and the interface's Problems checks. The engine editor's Theme dock is gone. The theme is edited in the interface editor's Theme tab.
- Two libraries: `just_ui_editor.dart`, the runtime a game imports, and `editor.dart`, `UiEditorModule`, which a game never imports.

### Screens as assets

- A screen is a `.ui.json` file (`UiDocument`, format 1): `name`, `entities` as `{name, parentName, components}` with the canvas first, and an `editor` block (guides, sample values, device) that a game never reads. Parents are linked by name, never by id. The canvas's `visible` is not saved.
- `assets/ui/screens.json` (`UiScreenManifest`) lists a game's screens, which of them start open, and the default theme. Level scenes hold no screens.
- `JustGameUi.registerCodecs`, `install`, `of` and `uninstall`. `install` builds every listed screen once, in a world of their own (`UiScreens`, with a `UiSystem`, a `TimelineSystem` and the navigator), so they survive level changes. `UiScreensPlugin` ticks them, paused or not, and `UiScreensLayer` draws them on `engine.layers`.
- `UiScreens`: `push`, `back`, `show`, `hide`, `closeAll`, `isOpen`, `reset`, `reloadFrom`.
- `UiActions.defaults` answers `ui.push`, `ui.back`, `ui.show`, `ui.hide` and `ui.toggle` whatever the game sets in `UiActions.host`. `UiActionContext` gains `gameWorld` and `host`.
- `UiSceneExtractor` turns the canvases an old scene holds into documents and list entries.
- `UiBindings.samples`: values that stand in for bindings while a tool previews a screen.

### Fixed in the runtime, while moving it

- A hidden element was still sized and could still be picked.
- The canvas had no node key, so tools could not find its rectangle.
- `alignSelf` was ignored in rows and columns.
- Hero flights never ran: the screens' own navigator had no `HeroController`.
- Changing an open screen's modal flag or transition made a second route and duplicate `GlobalKey`s.
- Themes load on demand, per canvas, when it is first drawn.
- The layer no longer swaps the global `UiActions.host`.
- A flow child's slot size was never applied.
- Buttons in the level's world get pointer input.

### The Interface editor

- `UiEditorModule({root})`: an **Interface** workspace, opened from its toolbar button, Ctrl+Shift+U, or a `.ui.json` or `.uitheme.json` in the Assets dock.
- Three columns. Left: Screens, Hierarchy and the Widgets palette. Middle: a toolbar (device presets and a size of your own, rotate, zoom, snap, grid, rulers, guides, outlines, Edit or Preview), the device frame, and a preview strip (other screens under this one, a forced button state, text scale, sample binding values, replay the opening transition, the last action pressed). Right: Inspector and Theme tabs.
- A header with the file, a not-saved dot, Save, Undo, Redo, full screen and close. Each screen is a document with its own undo and Save. The editor asks before leaving unsaved work.
- On the canvas: drag to move with snapping (Ctrl turns it off), eight resize handles, marquee select, drag to reorder in rows and columns, guides dragged from the rulers, arrow nudge (Shift for 10), align and distribute, anchor presets that keep the element in place, copy/cut/paste/duplicate with children and free names, a right-click menu, and drag and drop from the palette.
- Keys: Ctrl+S, Z, Y, D, C, X, V, A, 0, 1, =, - and P; Delete, F2, the arrows. Esc steps back one thing at a time: a drag, then Preview, then the selection, then the editor.
- Problems dock checks of every screen on the list (`UiChecks`), a Text prefab in every Level Designer palette, and **Move screens out of the level** as a command and a scene-tree right-click on a canvas (`UiLevelScreens.moveOut`).
- The game's screens show over the viewport only while a play-test runs.

### Fixed in the editor, compared with the old in-editor tool

- The preview refreshes on every edit.
- Drags follow the pointer at any zoom.
- The resize handles work.
- A click no longer moves things.
- One drag is one undo step.
- Esc while typing in a field no longer closes the dialog.
- Create can be undone, and places the new element on screen, under the selected container.

### Found in the real window

- Just opened, the outlines, handles and rulers were missing and the zoom read 100% until something else redrew the canvas: the painters kept what they were given when the canvas was built, before the frame was laid out. They now read it when they paint.
- Opening the editor on a game with a theme changed its header in the middle of a build: the Theme tab opened the theme from its own `initState`. The workspace opens it before anything listens.
- The Problems checks read every screen file and built a world for each, twice, about once a second. They now run again only when the list, a screen file or what the game registered has changed.
- The Screens list named unopened screens after their files (`device_lost`); it uses the screens' own names (`DeviceLost`), as `ui.push` does.
- A screen designed wider than tall opens with the device on its side.
- **A screen opened again while it was still closing broke the canvas.** The leaving route and the arriving one both built it, and each used the same `GlobalKey`. The arriving one tore the canvas out of the other in mid-layout, and Flutter reported "Duplicate GlobalKey detected", a render box mutated during layout, and a broken semantics tree. The editor now finds nodes through `UiNodeBoxes`, which keeps both and answers with the newer one. `UiLayer.nodes` replaces `UiLayer.nodeKeys`, a map of keys.
- The canvas's Visible box is gone from the inspector: whether a screen shows is the game's to say, and was never saved. A note points at the start-open button in Screens instead.

### Spacing and alignment

- **Kept to the safe area, a canvas was squashed.** Its scale came from the whole screen before it was fitted into the safe area, so a phone with a notch drew it scaled more one way than the other, in the game and in the editor alike. The scale is now worked out inside the safe area.
- **The columns start on one line.** The Screens header, the canvas toolbar and the Inspector/Theme tabs share one height, 34 px.
- **Height is shared by what the panels hold.** Screens is as tall as its list, up to a third of the column; Hierarchy and Widgets share the rest. They used to split it 3 : 5 : 4, leaving gaps under short lists.
- **The widget palette's tiles fill the width.** Its content sits at the same inset as the panel titles.
- **Toolbar toggles are spaced apart**, so two lit side by side read as two.
- **The preview strip's groups are divided.** A long message is cut short, and "Open it" is in the editor's accent.
- **The inspector keeps to its columns.**
  - "Pin to" and the Anchor row line up with the rows below.
  - The Anchor row is a box with a chevron, like a dropdown.
  - The text rows have their fold arrow after the label, not in front of it.
- **Align self** is a choice of what the layout knows, not an empty box.
- **The canvas's Showing note** is a read-only box, one line long.
- **A screen's links stay out of its inspector.** The Children card listed the level's entities and offered to cut the tree; the Hierarchy is where the tree is shown.
- **The Theme tab lines up with the Inspector tab.** Its groups are cards like the Inspector's, so switching tabs doesn't move the rows.
- **Menus that tick their current choice**, the device and the grid step, have their labels in one column.
- **A click selects the smallest element under it**, and of two the same size the one on top. Before, a layer stretched over the whole screen (the HUD's touch controls) took every click.

224 tests.
