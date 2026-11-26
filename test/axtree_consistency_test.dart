import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

import 'support/warm_image_cache.dart';

/// De `Failed to update ui::AXTree`-poort (#3268).
///
/// Op macOS (en Windows) deserialiseert de engine elke `SemanticsUpdate` in een
/// `ui::AXTree`. Twee inconsistenties laten `Unserialize` de héle update
/// verwerpen — "N will not be in the tree and is not the new root" — waarna de
/// boom bevroren blijft voor de schermlezer:
///
/// 1. De update bevat een node die niet in de bestaande boom zit én door geen
///    enkele andere node in díe update als child wordt geclaimd (een wees).
/// 2. Een node wisselt van ouder (reparent). De engine verwijdert dan eerst de
///    hele oude subboom; de update moet dus óók álle bestaande afstammelingen
///    opnieuw sturen. Wie alleen de verhuisde knoop stuurt, laat zijn kinderen
///    wezen achter.
///
/// Deze test speelt de engine voor: hij vangt elke verzonden update met een
/// spy-builder en rekent dezelfde regels na als `AXTree::Unserialize`. De
/// scenario's zijn de paden waarop de fout in #3268 optrad: de eerste
/// serialisatie van de presenter en elke onthulstap van een callout-dia.

typedef _NodeObs = ({Int32List children, String label, String hint});

class _SpyBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _SpyBuilder();
}

/// Intercepteert `SemanticsUpdateBuilder.updateNode`. Per `build()` staat één
/// update klaar in [_SpyBuilder.updates]: node-id → childrenInTraversalOrder.
class _SpyBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  final ui.SemanticsUpdateBuilder _inner = ui.SemanticsUpdateBuilder();

  static final List<Map<int, _NodeObs>> updates = [];

  Map<int, _NodeObs> _current = {};

  @override
  void updateNode({
    required int id,
    required SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int? traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required Rect rect,
    required String identifier,
    required String label,
    List<StringAttribute>? labelAttributes,
    required String value,
    List<StringAttribute>? valueAttributes,
    required String increasedValue,
    List<StringAttribute>? increasedValueAttributes,
    required String decreasedValue,
    List<StringAttribute>? decreasedValueAttributes,
    required String hint,
    List<StringAttribute>? hintAttributes,
    String? tooltip,
    TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String? linkUrl,
    SemanticsRole role = SemanticsRole.none,
    required List<String>? controlsNodes,
    SemanticsValidationResult validationResult = SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    _current[id] = (
      children: childrenInTraversalOrder,
      label: label,
      hint: hint,
    );
  }

  @override
  ui.SemanticsUpdate build() {
    updates.add(_current);
    _current = {};
    return _inner.build();
  }
}

/// Speelt `ui::AXTree::Unserialize` na over de verzonden updates. [apply]
/// retourneert de fouten die de engine zou loggen; bij een fout wordt de hele
/// update verworpen en blijft de boom onaangeroerd — zoals de echte bridge.
class _AXTreeSim {
  final Map<int, Int32List> _children = {};
  Set<int> _inTree = {};

  Set<int> _subtree(int root) {
    final out = <int>{};
    void walk(int id) {
      if (!out.add(id)) return;
      _children[id]?.forEach(walk);
    }

    walk(root);
    return out;
  }

  List<String> apply(Map<int, _NodeObs> update) {
    if (update.isEmpty) return const [];
    final errors = <String>[];
    final claimed = <int>{};
    update.forEach((_, n) => claimed.addAll(n.children));

    // Wees: niet in de boom, niet geclaimd, niet de (nieuwe) root.
    for (final id in update.keys) {
      final isNewRoot = _inTree.isEmpty && !claimed.contains(id);
      if (!isNewRoot && !_inTree.contains(id) && !claimed.contains(id)) {
        final n = update[id]!;
        errors.add(
          '$id will not be in the tree and is not the new root '
          '(label: "${n.label}", hint: "${n.hint}")',
        );
      }
    }

    // Geclaimd maar afwezig: een ouder noemt een child dat noch in de boom
    // zit noch meekomt in de update.
    for (final id in claimed) {
      if (!_inTree.contains(id) && !update.containsKey(id)) {
        errors.add('claimed child $id is not in the update');
      }
    }

    // Reparent: een bestaande knoop komt onder een nieuwe ouder. Zijn hele
    // oude subboom moet meekomen, want die wordt eerst afgebroken.
    final parent = <int, int>{};
    _children.forEach((p, kids) {
      for (final k in kids) {
        parent[k] = p;
      }
    });
    update.forEach((id, n) {
      for (final c in n.children) {
        if (_inTree.contains(c) && parent[c] != id) {
          for (final d in _subtree(c)) {
            if (!update.containsKey(d)) {
              errors.add(
                '$d will not be in the tree (reparented subtree of $c)',
              );
            }
          }
        }
      }
    });

    if (errors.isNotEmpty) return errors;

    update.forEach((id, n) => _children[id] = n.children);
    _inTree = {};
    // De root is de enige knoop die niemand claimt.
    for (final id in _children.keys) {
      if (!claimed.contains(id) && update.containsKey(id)) _subtree(id);
    }
    // Bepaal bereikbaarheid vanuit elke ongeclaimde root-kandidaat.
    final allParents = <int>{};
    _children.forEach((p, kids) => allParents.addAll(kids));
    for (final root in _children.keys.where((id) => !allParents.contains(id))) {
      _inTree.addAll(_subtree(root));
    }
    return errors;
  }
}

Slide _revealSlide(String imagePath) => Slide(
  id: 'onthullen',
  anchor: 'onthullen',
  type: SlideType.bulletsImage,
  title: 'Stap voor stap',
  bullets: const [
    'Het water komt hier binnen (A)',
    'Hier wordt de druk gemeten (B)',
    'Deze regel heeft geen verwijzing',
  ],
  imagePath: imagePath,
  calloutReveal: BulletRevealMode.steps,
  callouts: [
    const ImageCallout(
      reference: 'A',
      targets: [CalloutPoint(0.25, 0.34)],
      description: 'de aanvoerklep links',
    ),
    const ImageCallout(
      reference: 'B',
      targets: [CalloutPoint(0.69, 0.60), CalloutPoint(0.70, 0.30)],
      description: 'de meetkamer',
    ),
  ],
);

/// Een echt PNG op schijf: `CalloutOverlay` tekent pas markeringen als de
/// intrinsieke beeldmaat er is, en die komt uit een echte decode.
String _writePng() {
  final dir = Directory.systemTemp.createTempSync('ocideck_axtree');
  final file = File('${dir.path}/beeld.png');
  final image = img.Image(width: 200, height: 100);
  img.fill(image, color: img.ColorRgb8(180, 180, 180));
  file.writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
  return file.path;
}

Widget _host(List<Slide> slides, {String? projectPath}) => MaterialApp(
  localizationsDelegates: const [
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: FullscreenPresenter(
    slides: slides,
    projectPath: projectPath,
    themeProfile: const ThemeProfile(),
    initialIndex: 0,
  ),
);

void _drain(_AXTreeSim sim, Object step) {
  final errors = <String>[];
  for (final update in _SpyBuilder.updates) {
    errors.addAll(sim.apply(update));
  }
  // ignore: avoid_print
  print(
    'step $step: ${_SpyBuilder.updates.length} updates, '
    '${_SpyBuilder.updates.fold<int>(0, (s, u) => s + u.length)} nodes',
  );
  _SpyBuilder.updates.clear();
  expect(errors, isEmpty, reason: 'AXTree-fouten bij stap $step: $errors');
}

void main() {
  _SpyBinding();

  testWidgets('elke semantiekupdate van de onthulstappen is serialiseerbaar', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final handle = tester.ensureSemantics();
      final sim = _AXTreeSim();
      final path = _writePng();
      await warmImageCache(path, projectPath: File(path).parent.path);

      await tester.pumpWidget(
        _host([_revealSlide(path)], projectPath: File(path).parent.path),
      );
      await tester.pumpAndSettle();
      _drain(sim, 0); // eerste serialisatie — de opstartfout uit #3268

      for (var step = 1; step <= 4; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        _drain(sim, step);
      }

      // Ook in de presenter graften tooltip-bubbles via dezelfde identifiers —
      // de navigatieknoppen dragen er allemaal één.
      final tooltips = find.byType(Tooltip).evaluate().length;
      for (var i = 0; i < tooltips; i++) {
        tester
            .state<TooltipState>(find.byType(Tooltip).at(i))
            .ensureTooltipVisible();
      }
      await tester.pumpAndSettle();
      _drain(sim, 'presenter-tooltips');
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      _drain(sim, 'presenter-tooltips-uit');

      handle.dispose();
    });
  });

  testWidgets('de hele app-shell: geen wees-node in de opstart-updates', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final handle = tester.ensureSemantics();
    final sim = _AXTreeSim();

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    _drain(sim, 'app-start');

    handle.dispose();
  });

  // De wezen uit de live-app (nodes 62/83) komen van de recente-bestandentegel:
  // drie `Tooltip`s per rij, waarvan er twee op kale `Icon`s zitten. Die icons
  // vormen zelf geen semantieknode, dus hun `traversalParentIdentifier`s mergen
  // op de InkWell-node — en `SemanticsConfiguration.absorb` bewaart er maar
  // één (`??=`). De bubble van de verloren identifier graft nooit en blijft
  // voorgoed een wees (flutter/flutter#197194). Dezelfde botsing kan overal
  // zitten waar twee tooltip/menu-ankers één semantieknode delen — daarom
  // veegt deze scene élke tooltip en elk menu op het welkomstscherm open.
  testWidgets('app-shell: geen enkele getoonde tooltip of menu is een wees', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      // Legacy padenlijst: genoeg voor de tegels om te verschijnen.
      'recentFiles': ['/tmp/een.md', '/tmp/twee.md'],
    });
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final handle = tester.ensureSemantics();
    final sim = _AXTreeSim();

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    _drain(sim, 'lijst');

    // Elke tooltip-bubble opent via traversalParent/Child-grafting — hetzelfde
    // pad als hover/VoiceOver, maar dan programmeerbaar over het hele scherm.
    // Elke identifier die weggemerged is laat zijn bubble als wees achter.
    final tooltips = find.byType(Tooltip).evaluate().length;
    for (var i = 0; i < tooltips; i++) {
      tester
          .state<TooltipState>(find.byType(Tooltip).at(i))
          .ensureTooltipVisible();
      await tester.pumpAndSettle();
      _drain(sim, 'tooltip-$i-aan');
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      _drain(sim, 'tooltip-$i-uit');
    }

    // Menus graften via dezelfde machinery (OverlayPortal-identifiers):
    // openen en sluiten telt mee als semantiek-update.
    final menus = find.byType(PopupMenuButton).evaluate().length;
    for (var i = 0; i < menus; i++) {
      await tester.tap(find.byType(PopupMenuButton).at(i));
      await tester.pumpAndSettle();
      _drain(sim, 'menu-$i-open');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      _drain(sim, 'menu-$i-dicht');
    }

    handle.dispose();
  });
}
