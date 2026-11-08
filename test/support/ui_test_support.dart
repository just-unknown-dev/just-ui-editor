// What the runtime's tests share: a world that knows the interface, screens
// and elements made in a line, the layer pumped at a size, and a bundle
// that records what it is asked for.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_ui_editor/just_ui_editor.dart';

/// A world whose context knows the interface's components, as a game's
/// engine does with JustGameUi.extension installed: on [context], which the
/// worlds of one test share (their bindings, actions and widgets), or on a
/// context of its own, where they all start empty.
World uiWorld([EngineContext? context]) => World(context: context)
  ..context.install(JustGameUi.extension)
  ..initialize();

/// A canvas called [name], 400×300, with no transition to wait for.
Entity addCanvas(
  World world,
  String name, {
  bool isScreen = false,
  bool modal = false,
  bool visible = true,
  String theme = '',
  int sortOrder = 0,
}) => world.createEntityWithComponents([
  UiCanvasComponent(
    designSize: const Size(400, 300),
    safeArea: false,
    isScreen: isScreen,
    modal: modal,
    visible: visible,
    theme: theme,
    sortOrder: sortOrder,
    transition: UiTransition.none,
  ),
], name: name);

/// An entity made of [components], hung under [parent].
Entity addUnder(
  World world,
  Entity parent,
  List<Component> components, {
  String? name,
}) {
  final entity = world.createEntityWithComponents(components, name: name);
  UiDocument.link(entity, parent);
  return entity;
}

/// A slot that fills its parent.
UiSlotComponent fillSlot() =>
    UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch);

/// [world]'s canvas called [name], as a document.
UiDocument documentOf(World world, String name) =>
    UiDocument.capture(world.findEntityByName(name)!, world);

/// A screen file: a canvas called [name] with a card and a title.
UiDocument screenDocument(
  String name, {
  bool isScreen = true,
  bool modal = false,
  UiTransition transition = UiTransition.fade,
}) {
  final world = uiWorld();
  final canvas = world.createEntityWithComponents([
    UiCanvasComponent(
      designSize: const Size(400, 300),
      isScreen: isScreen,
      modal: modal,
      transition: transition,
    ),
  ], name: name);
  final card = addUnder(world, canvas, [
    UiPanelComponent(),
    UiLayoutComponent(),
    UiSlotComponent(size: const Size(300, 200)),
  ], name: '${name}Card');
  addUnder(world, card, [
    UiTextComponent(text: '$name title'),
    UiSlotComponent(),
  ], name: '${name}Title');
  return documentOf(world, name);
}

/// The interface over nothing, at 400×300.
Future<GlobalKey<UiLayerState>> showLayer(
  WidgetTester tester,
  World world, {
  UiActionHost? host,
  bool handlesBack = false,
  String Function(String key)? localize,
  Size size = const Size(400, 300),
}) async {
  final key = GlobalKey<UiLayerState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: UiLayer(
            key: key,
            world: world,
            actionHost: host,
            handlesBack: handlesBack,
            localize: localize,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

/// Text drawn by the canvas painter rather than a `Text`, by its words.
Finder paintedText(String words) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == words,
);

/// A component nobody registered, by its saved form.
const Map<String, dynamic> nobodysComponent = {
  'type': 'NobodysComponent',
  'fields': <String, Object>{},
};

/// A screen whose third entity names [nobodysComponent].
UiDocument brokenScreen(String name) => UiDocument(
  name: name,
  entities: [
    {
      'name': name,
      'parentName': null,
      'components': [
        {
          'type': 'UiCanvasComponent',
          'fields': {'isScreen': true, 'modal': true},
        },
      ],
    },
    {
      'name': '${name}Card',
      'parentName': name,
      'components': [
        {'type': 'UiPanelComponent', 'fields': <String, Object>{}},
      ],
    },
    {
      'name': '${name}Odd',
      'parentName': '${name}Card',
      'components': [nobodysComponent],
    },
  ],
);

/// A bundle holding [assets] in its manifest, recording what is read.
class FontBundle extends CachingAssetBundle {
  FontBundle(this.assets);

  /// Null: no manifest at all.
  final List<String>? assets;
  final List<String> read = [];

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final listed = assets;
      if (listed == null) throw FlutterError('No manifest');
      return const StandardMessageCodec().encodeMessage({
        for (final asset in listed)
          asset: [
            {'asset': asset},
          ],
      })!;
    }
    read.add(key);
    // Not a font: the family stays the fallback, quietly.
    return ByteData(0);
  }
}
