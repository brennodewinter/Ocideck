// Geen landpakket dat aan staat en niets doet.
//
// De instellingen tonen een chip per regio uit `allPrivacyRegions`, allemaal
// standaard aan. Acht daarvan hadden geen enkele regel: CY, LT, LU, LV, MT, SK,
// IS en LI detecteerden nul. Dat is precies de fout die `docs/PRIVACY.md`
// verbiedt — "niemand keek" leest als "niets gevonden" — en op een chip die de
// gebruiker zelf heeft aangezet weegt dat dubbel zo zwaar.
//
// Deze test legt de twee kanten vast:
//
//   * elke regio die je kunt kiezen heeft minstens één regel;
//   * elke regel hangt aan een regio die je kunt kiezen — anders draait ze
//     nooit, en dat is een stille nul aan de andere kant.
//
// De ratchet werkt beide kanten op. Bouw je `lv.pk`, dan is de test rood tot
// `lv` in het pakket staat. Zet je een land in het pakket zonder regel, dan is
// hij net zo rood.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_eu_rules.dart';
import 'package:ocideck/services/privacy/privacy_plate_rules.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_world_rules.dart';

/// Alle regel-ids die de code werkelijk kan uitgeven.
///
/// De catalogi plus een bronscan voor de hardgecodeerde detectoren, die in geen
/// lijst staan. Dezelfde aanpak als `privacy_doc_rule_ids_test.dart`: een tweede
/// handmatige lijst zou precies zo uit de pas lopen als het probleem dat deze
/// test bewaakt.
Set<String> _regelIds() {
  final ids = <String>{
    ...euIdentifierRules.map((r) => r.id),
    ...worldIdentifierRules.map((r) => r.id),
    ...intlPostcodeRules.map((r) => r.ruleId),
  };
  final literal = RegExp(r"\b(?:id|ruleId):\s*'([a-z0-9_]+\.[a-z0-9_]+)'");
  final dir = Directory('${Directory.current.path}/lib/services/privacy');
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m in literal.allMatches(f.readAsStringSync())) {
      ids.add(m.group(1)!);
    }
  }
  return ids;
}

/// De regio's waarvoor werkelijk iets te vinden valt.
Set<String> _regiosMetRegels() {
  final regios = <String>{};
  for (final id in _regelIds()) {
    final gedeeld = sharedRegionRules[id];
    if (gedeeld != null) {
      regios.addAll(gedeeld);
      continue;
    }
    final regio = privacyRuleRegion(id);
    if (regio != null) regios.add(regio);
  }
  return regios;
}

void main() {
  test('de bronscan levert genoeg regels op om iets te bewijzen', () {
    // Zonder ondergrens laat een hernoemd bestand deze test groen door er niets
    // meer in te stoppen — en dan is elke regio "gedekt".
    expect(_regelIds().length, greaterThan(60));
    expect(_regiosMetRegels().length, greaterThan(25));
  });

  test('elk landpakket dat je kunt kiezen vindt ook iets', () {
    expect(
      allPrivacyRegions.difference(_regiosMetRegels()).toList()..sort(),
      isEmpty,
      reason:
          'deze pakketten staan in de instellingen — standaard aan — maar er is '
          'geen enkele regel die eraan hangt. Een chip die aan staat en niets '
          'doet is erger dan geen chip: hij laat "niemand keek" lezen als '
          '"niets gevonden". Bouw de regel, of haal het land uit '
          'defaultPrivacyRegions tot hij er is.',
    );
  });

  test('elke gebouwde regel hangt aan een pakket dat je kunt kiezen', () {
    expect(
      _regiosMetRegels().difference(allPrivacyRegions).toList()..sort(),
      isEmpty,
      reason:
          'voor deze regio bestaat een regel, maar het pakket staat in geen '
          'lijst — dan draait de regel nooit. Zet het land in '
          'defaultPrivacyRegions.',
    );
  });

  group('een gedeelde regel draait onder elk land dat hem deelt', () {
    Set<String> regelsIn(String tekst, Set<String> regios) =>
        PrivacyScanner(regions: regios)
            .scan(
              Deck(
                title: 'D',
                slides: [
                  Slide.create(SlideType.bullets).copyWith(bullets: [tekst]),
                ],
              ),
            )
            .findings
            .map((f) => f.ruleId)
            .toSet();

    test('Slowakije deelt het rodné číslo met Tsjechië', () {
      // Hetzelfde nummer uit Tsjecho-Slowakije, dezelfde controle. Een eigen
      // `sk.`-id zou het dubbel melden; het pakket moet de regel dus delen.
      const nummer = 'Rodné číslo 840512/1230';
      expect(regelsIn(nummer, {'sk'}), contains('cz.rodne_cislo'));
      expect(regelsIn(nummer, {'cz'}), contains('cz.rodne_cislo'));
      expect(regelsIn(nummer, {'nl'}), isNot(contains('cz.rodne_cislo')));
    });

    test('Litouwen deelt de mod-11 met Estland', () {
      // `isValidBalticPersonalCode` valideert isikukood én asmens kodas: elf
      // cijfers, dezelfde twee ronden. Eén regel, twee landen.
      const nummer = 'Isikukood 37205030203';
      expect(regelsIn(nummer, {'lt'}), contains('ee.isikukood'));
      expect(regelsIn(nummer, {'ee'}), contains('ee.isikukood'));
      expect(regelsIn(nummer, {'nl'}), isNot(contains('ee.isikukood')));
    });
  });
}
