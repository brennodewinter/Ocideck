import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/info_safety_provider.dart';

/// Regression guards for feedback #1: self-authoring MIAUW/security content is
/// only offered when the "informatieveiligheid" module is on. The dialog
/// behaviour is covered by add_slide_dialog_test / new_deck_dialog_test; these
/// pin the invariants those gates rely on, so a new security slide type or MIAUW
/// template can't slip through ungated.
void main() {
  test('the security module is off (and nothing revealed) by default', () {
    const state = InfoSafetyState();
    expect(state.enabled, isFalse);
    expect(state.revealed, isFalse);
  });

  test('every info-security slide type carries the gated category', () {
    // The add-slide picker hides SlideCategory.informatieveiligheid types when
    // the module is off, so each security type must declare that category.
    const securityTypes = {
      // Aanvalsoppervlak hoort hier: het is MIAUW-materiaal, geen algemeen
      // presentatiemiddel, en miste alleen zijn categorie.
      SlideType.assets,
      SlideType.finding,
      SlideType.findingsSummary,
      SlideType.checklist,
      SlideType.scopeMatrix,
      SlideType.signOff,
    };
    for (final type in securityTypes) {
      expect(
        slideTypeMeta[type]!.category,
        SlideCategory.informatieveiligheid,
        reason: '$type must be gated behind the security module',
      );
    }
    // And no other type is in that category (so nothing else is hidden).
    final gated = slideTypeMeta.entries
        .where((e) => e.value.category == SlideCategory.informatieveiligheid)
        .map((e) => e.key)
        .toSet();
    expect(gated, securityTypes);
  });

  test(
    'the MIAUW template requires the module (so it is hidden by default)',
    () {
      final miauw = deckTemplates.firstWhere((t) => t.id == 'miauwReport');
      expect(miauw.requiresInfoSafety, isTrue);
    },
  );
}
