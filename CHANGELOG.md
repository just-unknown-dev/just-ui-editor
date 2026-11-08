# Changelog

## 0.2.0-alpha.1

Each engine has an interface of its own, the layout is by feature, the names follow the engine's rules, and the screen list is never written over. Requires just_game_engine ^2.0.0, just_inputs ^0.2.0, just_editor_core ^0.1.0 and, for the tests, just_game_engine_editor ^0.1.0. Dart ^3.12.0.

### Breaking

- **Renamed, and saved under the new names** (old files are migrated as they load, see Changed):
  - `TextComponent` → `UiTextComponent`, `ButtonComponent` → `UiButtonComponent` (saved types `'UiTextComponent'`, `'UiButtonComponent'`);
  - `TextComponentPainter` → `UiTextComponentPainter`, `ButtonComponentPainter` → `UiButtonComponentPainter`.
- **Renamed:**
  - `UIComponent` → `UiElementComponent`;
  - `UiSystem` → `UiTextSystem`;
  - `UiSchemas` → `UiWorldDefinitions` (file `serialization/ui_world_definitions.dart`; was `ui_schemas.dart`): the definitions of the level's own text and buttons, with the same ids;
  - `UiDefinitions` → `UiScreenDefinitions`, whose `all` is a `List<ComponentCodec>` as `UiWorldDefinitions.all` is;
  - the runtime's `UiAlign` → `UiFlexAlign` (saved by value name, unchanged), and the editor's `UiAlign` → `UiAlignEdge`: the two libraries no longer export one name twice;
  - `localise` → `localize` everywhere: `JustGameUi.install`, `UiScreens`, `UiScreensLayer`, `UiLayer`, `UiTextSystem`, `registerUiSystems`, `UiWorldStyle`, `UiBuildContext`, `UiBindings.resolveText`;
  - the extension `UiEditOps` → `UiEditorSessionEdits`;
  - `UiWidgets.of(id)` → `UiWidgets.of(context).byId(id)`.
- **The registries are per engine** (`EngineContext.slot`), never process-wide: `UiBindings`, `UiActions`, `UiWidgets`, `UiIcons`, `UiThemes` and `UiFonts` are reached through `X.of(engine.context)`, as `UiWorldStyle` already was. `UiBindings.register('coins', …)` is `UiBindings.of(engine.context).register('coins', …)`, and `UiActions.host = …` is `UiActions.of(engine.context).host = …`. The static helpers stay static: `UiBindings.namesIn`, `format`, `hueAt`, `phase`; `UiActions.builtIns`, `linkAction`, `rootOf`, `findBelow`; `UiFonts.familyOf`, `familiesIn`, `defaultFolder`.
- `UiTextComponent.resolve(bindings, {self, localize})` takes the engine's bindings.
- The pointer's ray (`UiPointer.ray`, `UiPointerSystem.buttonAt(ray:)`) is just_dart 0.3.0's `Ray3D` (was `Ray3`), through the engine.
- `UiRichText.toTextSpan` and `UiTextPainter.set` take `icons:` (the engine's `UiIcons`); with none, `[icon=…]` draws nothing.
- `UiBindings.samples` is gone: a tool shows samples in the worlds it previews (`showSamples(world, …)`, `hideSamples(world)`), and a game on the same engine reads its own values.
- `UiBindings.registerBuiltIns()` is gone: `self.name` and `self.id` are there from the start, and after `clear()`.
- `UiThemes.loadFor` is gone (the screens read the themes their canvases name). `UiThemes.useFallback(theme, owner:)` and `releaseFallback(owner)` replace setting `fallback` from the screens.
- `UiSystem.missingBindings(world)` is `UiChecks.missingBindings(world)`, in `editor.dart`.
- `UiSceneExtractor` and `UiSceneExtraction` moved to `editor.dart`: only the editor uses them.
- `UiProject.writeManifest` is `UiProject.updateManifest(change)`, which changes the list as it is on disk; `UiProject.readScreen` takes `hooks:`.
- `UiDocument.migrations` is private; `UiDocument.fromJson` takes `hooks:`.
- `UiFieldEditors.all`, `UiExtras.all` and `UiFieldEditors.inheritedColor` take the edited engine's context; `uiInheritedColor` takes `theme:`. These, the canvas internals, the panels, the inspector rows and `UiSlotState` / `UiSlotEditCommand` are `@internal`; the inspector rows follow the editor core's names (`UiTextStyleFieldRow`, `UiActionsFieldRow`, `UiAnchorFieldRow`, `UiTextFieldRow`).
- `UiCreateOptions.all(widgets)` and `byId(widgets, id)`, `UiCreate.baseNameFor(kind, widgets)` take the engine's widgets.
- `UiThemeDocument` takes `themes:`.
- The editor's `promptForName` is gone: the editor core's `showEditorPrompt`.
- Files moved: `lib/src/` is laid out by feature (`text`, `bindings`, `theme`, `layout`, `controls`, `world`, `serialization`, `screens`, `editor`), each with one barrel; no game imports `src/`.

### Added

- `UiMigrations`: the renamed components (`renamedTypes`), installed into every context with `JustGameUi.extension`.
- `UiDocument` format 2, and its step from format 1.
- `UiTextComponent.resolved`, the text as last resolved, and `resolvedIn`, the world update (`World.updateCount`) in which the text system resolved it (run time, never saved).
- `UiLayerState.walks` (`@visibleForTesting`): how often the layer has walked its tree.
- `UiThemes.of`, `UiFonts.of`, `UiIcons.of`, `UiWidgets.of`, `UiActions.of`, `UiBindings.of`; `UiFonts.useBundle`.
- `UiEditorSession.themeChanged(path)`, `showSamplesIn(world)`, `sampleValues`; `UiEditorWorkspace.onSession`.
- `test/library_layout_test.dart`: the layout, the layers, the runtime/editor split, one name per library, and `just_store.json` against `pubspec.yaml`. `test/editor_dependencies_test.dart`: the editor core brings no native plugin the engine does not.
- The release workflow formats, analyzes and tests before it packs.
- **Closes on Back** (`UiCanvasComponent.closesOnBack`, saved; on by default, so a screen saved before it still closes on Back). With it off, Escape, a pad's cancel and the system's back leave the screen open: only its own buttons (`ui.back` included) and the game close it — a level-complete banner, a lost-controller pause. The inspector shows it under Behaviour. There Escape is not taken: it goes on to the game, like any key a screen does not want; the system's back is still taken, so it does not leave the app. The Problems dock says when such a screen has nothing on it that does anything, and when a layer has it off (Back never closes a layer).
- `UiNavigator.canGoBack` and `handleBack()`: a player's back, which keeps a screen that does not close on Back; `back()`, what `ui.back` runs, still closes whatever is on top.

### Changed

- **Old files load with the new names, whatever their format.** A scene, prefab or timeline is renamed through the context's migrations on every load; a `.ui.json` screen at format 1 is renamed by its format step, and every screen is read with the reader's migrations (`SceneFormat.renameComponents`), so a component a kit renames later reads under its new name too.
- The screens world reads files from the context's bundle by default; so do `UiThemes` and `UiFonts`.
- `UiBuildContext.text(name)` applies the language as well as the bindings, as `resolve` does.
- A sampled binding name reads in a previewed world even when no game offers it.
- Layout: `ui_layer.dart` (2,010 lines) is a library with parts (`ui_element_builders`, `ui_node_boxes`, `ui_screen_route`, `ui_painted_text`, `ui_panel_image`, `ui_atlas_image`); `ui_canvas_view.dart` (1,367) has its gestures and preview worlds in parts.
- Faster frames: the screen layer folds each node's revision into one hash without a list per entity, and reuses the text the text system resolved in the update just before the sync. It walks its tree again only when the world's shape changed (just_game_engine's `World.structureVersion`: an entity made, destroyed, switched or re-parented, a component added, removed or replaced) or a canvas was shown, hidden or reordered, and looks each entity's components up once per walk, not every frame: a still 1,641-entity screen syncs in about 1.15 ms instead of 1.57 ms, a 411-entity one in 0.29 ms instead of 0.36 ms (debug JIT). Field edits and bindings still show at the next sync; rainbow and pulse letters are laid out once and tinted as they are drawn; a theme's role styles and a text's style under a theme are worked out once.
- The Interface editor lets the app idle: its canvas ticks only while something changes or moves.
- The Problems dock's screen checks are kept per engine, read the screen list again only when it changed on disk, and stat the other files.
- **A focus ring.** Whatever holds the keyboard or pad focus is ringed in the theme's `primary`, 3 design pixels clear of its edge and 3 thick: a button, a toggle and its label, a slider, a text field, a dropdown. Material's own focus look, a fill a tenth lighter, could not be seen from across a room. The ring shows on a button filled with `primary` too, since the gap between them shows what is behind.
- A `UiEditorSession` with a context of its own installs the engine's built-in components (`BuiltInComponents.extension`).
- The inspector uses just_editor_core 0.1.0's row names (`ColorFieldRow`, `BoolFieldRow`, `TextFieldRow`, `DropdownFieldRow`, `AssetRefFieldRow`, `EdgeInsetsFieldRow`, `ReadonlyFieldRow`) and `PrefabColors`; the module's commands say their `availability:` (`CommandAvailability`); Show, Hide and a theme's Use name the field they write (`ComponentFieldCommand(field:)`).

### Fixed

- The Interface editor wrote a screen list it had read earlier over a newer one, dropping the screens another tool, a pull or "Move screens out of the level" had listed (UIE-BUG-1). Every list write now starts from the file on disk, and the open editor is told when the list, a screen or a theme changes.
- A panel's picture disappeared when nine-slice was set on it, until something else changed.
- The typewriter cut an emoji, or a letter and its accent, in half.
- `UiFonts.reset()` during a load let the old load take the new one's place.
- A `UiLayer` given another world or navigator kept the first; the editor no longer works round it with a new key per world.
- A screen name nothing has (`ui.push`, `ui.show`) did nothing silently: a debug build says so, once per name. A screen list that names no screens is said in the log.
- With two engines installed, `ui.push` on one engine's screens opened the other's; one engine's list theme restyled another's text; the editor pointed every engine's theme and font loaders at the project.
- A world text's or button's painter was never disposed: it goes with its component.
- The `.pubignore` named files that do not exist, and missed `store/`.
- A `sync()` with no world update since a binding changed showed the old value: the layer reused the text the text system had resolved before the change. It reuses that text only when the system resolved it after the layer's previous sync, and reads the text itself otherwise (an editor's preview, a paused game, a test).

### Removed

- `lib/src/runtime/components/screen/ui_custom_component.dart`, a re-export nothing imported.
- The flat test files named by audit round; the tests mirror `lib/src/`.

## 0.1.0-alpha.1

- **Builds on `just_editor_core`**, the editor's module contract, instead of depending on `just_game_engine_editor`: the module's code needs nothing else of the editor. The tests that drive a real editor take `just_game_engine_editor` as a dev dependency.

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
- `JustGameUi.extension`, `install`, `of` and `uninstall`. `install` builds every listed screen once, in a world of their own (`UiScreens`, with a `UiSystem`, a `TimelineSystem` and the navigator), so they survive level changes. `UiScreensPlugin` ticks them, paused or not, and `UiScreensLayer` draws them on `engine.layers`.
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

### Fixed in the runtime before release

- **A screen file that would not read left half a screen behind**, open and (if modal) in the way of the whole game. Every record is now read before anything is built, and a replacement that will not read leaves the old screen standing.
- **Restarting from an open screen threw** while that screen closed: its route built the canvas `reset()` had just destroyed.
- **Any text that changed rebuilt the whole interface**, every open screen and a `ThemeData` per canvas with it. Each node now rebuilds alone (labels, toggles, sliders and custom-widget props included), and `UiTheme.toThemeData` is made once per theme.
- **A theme that would not load was read again every frame.** It is the fallback until `UiThemes.evict`; `UiThemes.failed` says so.
- **Buttons in the level were pressed through the screens**: through a HUD button, and under a modal screen's barrier. They hear only what the screens let through, follow one pointer (the first down), are pressed where they are drawn (turned and scaled), take a tap that starts and ends between two frames, and ignore presses made while the game is paused. `UiPointerSystem.discardPending` is new.
- **Text and buttons in the level never got the game's theme or language.** `UiWorldStyle` holds both on the engine's context, and `install` fills it in; the static `TextComponentPainter.theme` and `.localise` are gone. Their hover and press sounds come from the theme.
- **`@key` worked only in texts.** Button, toggle, slider and dropdown labels and a field's hint are looked up too (`UiBindings.resolveText`).
- **`[icon=…]` drew nothing and `[link=…]` did nothing.** `UiIcons` registers icons (a glyph anywhere, a widget in screens); a link runs an action when tapped (`UiActions.linkAction`). In a screen, `[wave]`, `[shake]`, `[rainbow]`, `[pulse]`, outlines, gradients and Shrink are drawn by the canvas painter, which animates itself; `[rainbow]` and `[pulse]` alone now animate in the level too, and moving letters wrap and align as still text does. A tag-only change (a colour, a size) redraws.
- **Fonts the editor offered never loaded in the game.** `install(fonts:)` loads every font under `assets/fonts/` (`UiFonts.loadFolder`).
- **Android's back closed the app** with a screen open. It closes the screen on top (`UiLayer.handlesBack`, on in the game's view).
- **The pad slid nothing and took over live play.** A d-pad direction goes to the focused widget first (a slider slides), and a screen takes the pad only while the game is paused or the screen on top is modal (`UiInputBridge.takesPad`).
- **The arrows in a screen's text field moved the focus**, not the caret.
- **Names two screens share**: a screen opens by its canvas's name even when an element elsewhere is called that, and `ui.show`/`ui.hide`/`timeline.play` look in the acting (or top) screen first. Pushing a layer shows it rather than stacking it, and the stack keeps the order screens were opened in.
- **`install` failed on a missing or hand-edited `screens.json`**; it now runs with no screens and says why. A screen file or a list of the wrong shape is a `FormatException` naming the key (`UiScreenManifest.parse` is new).
- **A binding reading infinity or NaN threw every frame**, and a pattern asking for more than 20 decimals threw too.
- **Custom widgets lost the layer's action host and the game world**, so an editor preview's custom button reached the real game.
- **A slider saved the wrong way round, a `flex` or an expanding spacer outside a row or column, a choice listed twice, or a view with no room** each threw while building.
- **Saved but never drawn**: a panel's picture and nine-slice, and an image's atlas region, are drawn now. A panel's gradient is saved (as `#aarrggbb` texts). World text and buttons save their `layer`, and a button whether it can be pressed.
- A screen's `ButtonComponent.wasPressed` lets go after one frame; a second `install` hands the level's systems its new callbacks; `uninstall` gives the built-in theme back; `UiBindings.registerBuiltIns` keeps a game's own `self.name` and `self.id`.
- `UiSceneExtractor.extract` keeps the children of two same-named parents apart, and a canvas with no fields counts as showing.
- **A child whose slot alone changed stayed where it was**, moved or resized by a timeline or by code: its parent places it, and nothing told the parent. A node now rebuilds when one of its children is placed differently, and a canvas's top-level children are built from the canvas's own node.
- **`screens.json` lost what it did not know** on the way back out. `UiScreenManifest.extra` and `UiScreenEntry.extra` keep every other key, and write it back.
- **A theme read that a `UiThemes.reset` or `evict` overtook** still wrote what it read, or that it failed, afterwards.

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

### Fixed in the editor before release

- **A new screen or a copy could be written over another screen.** Two names can share one file (`Main Menu` and `MainMenu` are both `main_menu.ui.json`), and the free-name check compared names differently from how files are named. It now checks the file itself, and `createScreen` refuses a file that is already there.
- **Duplicate and "Open it" dropped the open screen's unsaved work without asking.** `UiEditorSession.duplicateScreen` now returns the copy's path without opening it; the workspace opens it through the same question every other opening asks.
- **Undo and redo of a move could do nothing.** `UiSlotEditCommand` held the slot components themselves, so once an element was made again (a delete undone, a create undone and redone) its moves, resizes, anchors and fits wrote to a component no entity had. It is now keyed by entity and reaches the one there now.
- **A `screens.json` that did not read was taken for an empty list, and the next change wrote over it.** `UiProject.manifestProblem` says why it does not read; `writeManifest` refuses while it does not, the session's list changes return false with `lastError`, the Screens panel and the Problems dock say so, and Move screens out of the level leaves everything alone.
- **Theme edits that were discarded stayed on every screen, in the level's text and in the next play-test.** A theme let go of unsaved is read from its file again.
- **The second play-test showed the screens as they were at the first.** Every file the editor writes, moves or deletes is now reported to the editor (`UiEditorSession(onFilesChanged:)`), and a play-test reads the screen list and its screens afresh when it starts. A Stop that arrives while the files are still being read no longer leaves the screens over the editor.
- **One font file changing made the editor forget every other font.** All the project's fonts are read again.
- **Writes go through `ProjectFiles`:** whole or not at all, retried while Windows holds the file for a moment, with nothing left behind when they fail, and never outside the project or into pub's cache (`UiProject.isWritable`). A rename writes the list before it deletes the old file.
- **A failed save, a screen that does not open, a refused rename or name are said**, in a box or under the field, instead of an exception in the log or nothing at all.
- **Preview played on the screen that is saved.** A player's toggles, sliders, typing and Back wrote into its components, and the next Save wrote them to the file. Preview now plays a copy, made again when the screen is edited.
- **An `editor` block edited by hand** (guides, sample values, the device) could stop the workspace from opening, or throw on every frame. What does not read is passed over.
- **What is drawn under a screen showed only its layers once a second screen was added under it.**
- **Renaming a screen** refuses a name another screen has, whatever its file is called, and one of its own elements' names, which would have re-linked the tree on the next load. Under-it choices follow the rename. A change of letter case only keeps the file it is in.
- **Drags:** each move is applied as it goes, back where it began included, and recorded as one step when it ends; a move keeps the slot's own size, and what is saved is rounded to a hundredth of a pixel. Escape during a drag leaves no step and no unsaved dot. A marquee no longer keeps the screen itself selected beside what it caught.
- **Copies of a switched-off element are switched off**, and the hierarchy's right-click switches an element off or on. A duplicate of elements in different containers goes beside each original.
- **The Theme tab** makes each press its own undo step, and its Save says when it fails.
- **The inspector** reads an empty colour or text role as the element's default, not as `primary`; a custom widget with none chosen says so; an action this build has not registered (`custom:openShop`) still shows its kind.
- **Rebuilds:** a hover or a pan no longer builds the whole screen again, and the inspector, the hierarchy and the Theme tab catch up when a drag ends rather than on every move. The rulers and the overlay repaint when something they show changed, and at most four times a second otherwise; the rulers keep their labels laid out.
- **Hierarchy:** what is folded, renamed or keyed by entity id is forgotten when another screen opens (each screen's ids count from nought).
- **The module** gives `UiThemes` and `UiFonts` back to the bundle when the editor goes, hands its loaders out again after a hot reload, and imports `package:just_editor_core/io.dart` rather than `dart:io`.
- **The Problems checks** build each screen once, and let go of a world when a screen does not read.
- **The name prompt** no longer uses its text after it was disposed, while the dialog closes.
- **Keys:** Backspace deletes on macOS only, as in the rest of the editor; Delete deletes everywhere. Menus name the key as the platform does.
- **The level's own text and buttons** are drawn in the game's theme, the screen list's (`UiWorldStyle`), and follow it when it is saved. A play-test's `install` leaves fonts to the editor, which reads the project's own.
- **More Problems checks:** an `[icon=…]` the game does not register, a `[link=…]` that cannot be clicked (in the level's text, or text a screen paints by hand), a slider whose least is more than its most, a choice a dropdown offers twice, a `flex` or a stretching spacer outside a row or a column, `ui.push` naming a layer, and a theme that is not there or does not read.
- **A panel's gradient** is a row of colours to pick in the inspector, one stop each.

343 tests.


