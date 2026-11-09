import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/info_safety_provider.dart';

/// Legacy slides keep their decoding and rendering support, while the retired
/// module, templates and data acquisition must stay unavailable.
void main() {
  test('the security module is off (and nothing revealed) by default', () {
    const state = InfoSafetyState();
    expect(state.enabled, isFalse);
    expect(state.revealed, isFalse);
  });

  test('every info-security slide type carries the gated category', () {
    // The add-slide picker hides SlideCategory.informationSecurity types when
    // the module is off, so each security type must declare that category.
    const securityTypes = {
      // Aanvalsoppervlak hoort hier: het is MIAUW-materiaal, geen algemeen
      // presentatiemiddel, en miste alleen zijn categorie.
      SlideType.assets,
      // Ontdekkingen hoort bij het aanvalsoppervlak: dezelfde scan, dezelfde
      // lezer, en even min een algemeen presentatiemiddel.
      SlideType.discoveries,
      SlideType.finding,
      SlideType.findingsSummary,
      SlideType.checklist,
      SlideType.scopeMatrix,
      SlideType.signOff,
    };
    for (final type in securityTypes) {
      expect(
        slideTypeMeta[type]!.category,
        SlideCategory.informationSecurity,
        reason: '$type must be gated behind the security module',
      );
    }
    // And no other type is in that category (so nothing else is hidden).
    final gated = slideTypeMeta.entries
        .where((e) => e.value.category == SlideCategory.informationSecurity)
        .map((e) => e.key)
        .toSet();
    expect(gated, securityTypes);
  });

  test('security report templates have been removed', () {
    expect(deckTemplates.where((t) => t.requiresInfoSafety), isEmpty);
    expect(deckTemplateById('miauwReport'), isNull);
  });
}
