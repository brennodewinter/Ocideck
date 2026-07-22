// `COMPLIANCE.md` is de vrijwillige beveiligingsattestatie: een zelfverklaring
// die een buitenstaander leest in plaats van ons te mailen.
//
// Juist daarom is dit het document dat níét stil mag verouderen. Een attestatie
// die naar een verdwenen bestand wijst, of die een ander meldadres noemt dan
// `SECURITY.md`, is erger dan geen attestatie: hij leest als "hier is over
// nagedacht" terwijl de werkelijkheid verderop staat.
//
// Wat hier bewaakt wordt is de mechanische helft — bestaan de dingen waar hij
// naar wijst, en spreken de twee documenten elkaar niet tegen. Of de
// zelfverklaring *klopt* kan geen test zeggen; dat blijft mensenwerk, en de
// niet-aangevinkte regels zijn precies waar dat aan hangt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final compliance = File('COMPLIANCE.md').readAsStringSync();

  test('COMPLIANCE.md bestaat en noemt zichzelf geen conformiteitsclaim', () {
    // De kop is de belangrijkste alinea van het document: hij bepaalt of een
    // lezer dit als zelfverklaring of als certificaat opvat.
    expect(compliance, contains('Not a conformity claim'));
    expect(compliance, contains('not an\n> audit'));
  });

  test('elk bestand waar de attestatie naar wijst, bestaat ook', () {
    // Markdown-verwijzingen van de vorm [tekst](pad) naar iets in deze repo.
    final links = RegExp(r'\]\((?!https?:)([^)#]+)').allMatches(compliance);
    expect(links, isNotEmpty, reason: 'geen enkele verwijzing gevonden?');

    final missing = <String>[];
    for (final m in links) {
      final target = m.group(1)!.trim();
      final exists =
          File(target).existsSync() || Directory(target).existsSync();
      if (!exists) missing.add(target);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'COMPLIANCE.md verwijst naar iets wat er niet is. Een attestatie die '
          'doodloopt, is precies de vorm van vertrouwen die dit document niet '
          'hoort te wekken.',
    );
  });

  test('het meldadres is hetzelfde als in SECURITY.md', () {
    // De twee documenten mogen niet uit elkaar lopen: dit is het adres waarop
    // iemand een kwetsbaarheid meldt, en de attestatie is de kopie die een
    // machine of een inkoper leest.
    final security = File('SECURITY.md').readAsStringSync();
    final address = RegExp(r'[\w.+-]+@[\w.-]+\.\w+');
    final inSecurity = address
        .allMatches(security)
        .map((m) => m.group(0)!)
        .toSet();
    final inCompliance = address
        .allMatches(compliance)
        .map((m) => m.group(0)!)
        .toSet();

    expect(inCompliance, isNotEmpty);
    expect(
      inCompliance.difference(inSecurity),
      isEmpty,
      reason:
          'COMPLIANCE.md noemt een adres dat niet in SECURITY.md staat. Eén van '
          'de twee is verouderd, en de melder ontdekt welke.',
    );
  });

  test('de niet-aangevinkte regels staan er nog als niet-aangevinkt', () {
    // Drie regels kunnen vandaag niet aangevinkt worden (QA.06, QA.07 en de
    // release-regels). Wordt er ooit één stilletjes aangevinkt zonder dat het
    // waar is, dan is dat precies de schade die dit document moet vermijden.
    //
    // Deze test dwingt geen antwoord af — hij dwingt af dat het antwoord bewust
    // wordt gewijzigd. Vinkt iemand QA.06 aan, dan hoort hij hier langs te
    // komen en AUTHORS.md te hebben aangevuld.
    final unchecked = RegExp(
      r'^- \[ \] \*\*(\w+\.\d+)',
      multiLine: true,
    ).allMatches(compliance).map((m) => m.group(1)!).toSet();
    expect(
      unchecked,
      containsAll(<String>['QA.06', 'QA.07']),
      reason:
          'QA.06/QA.07 gaan over meer dan één actieve bijdrager en review door '
          'een niet-auteur. Vink die pas aan als AUTHORS.md dat waarmaakt.',
    );
  });
}
