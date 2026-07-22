import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/reference_standard.dart';
import 'package:ocideck/services/reference_standards.dart';
import 'package:ocideck/services/wstg_catalog.dart';

void main() {
  group('het register van gebundelde standaarden', () {
    test('elke standaard is volledig ingevuld', () {
      expect(referenceStandards, isNotEmpty);
      for (final s in referenceStandards) {
        expect(s.id, isNotEmpty, reason: 'id ontbreekt');
        expect(s.name, isNotEmpty, reason: '${s.id}: naam ontbreekt');
        expect(s.url, startsWith('https://'), reason: '${s.id}: EIS 4.8.2.3');
        expect(s.bundled, isNotEmpty, reason: '${s.id}: EIS 4.8.2.1');
        expect(s.licence, isNotEmpty, reason: '${s.id}: licentie ontbreekt');
      }
    });

    test('ids zijn uniek', () {
      final ids = referenceStandards.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('élke standaard is bij de bron te controleren', () {
      // Dit is de regel, niet een eigenschap die toevallig geldt: een nieuwe
      // versie mag niet in stilte voorbijgaan. CWE en CVSS stonden eerst als
      // "niet te bevragen" in het register, tot bleek dat MITRE een REST-API
      // heeft en FIRST per versie een schema op een vaste URL publiceert. Dat
      // was luiheid, geen eigenschap van de bron. Voeg je een standaard toe,
      // dan hoort daar een manier bij om hem te controleren.
      for (final s in referenceStandards) {
        expect(
          s.probeTarget,
          isNotEmpty,
          reason:
              '${s.id}: een probe zonder doelwit is een stille no-op — zoek '
              'uit hoe de bron zijn versie publiceert',
        );
      }
    });

    test('opzoeken op id werkt en is null voor onbekend', () {
      expect(referenceStandardById('wstg')?.name, 'OWASP WSTG');
      expect(referenceStandardById('bestaat-niet'), isNull);
    });
  });

  group('het register loopt niet weg bij de catalogi', () {
    // Het hele punt van dit register is dat er één waarheid is. Als de WSTG-
    // catalogus naar v5.0 gaat en het register op 4.2 blijft staan, dan meldt de
    // verouderingspoort "actueel" over een versie die we niet meer bundelen —
    // erger dan geen poort.
    test('de WSTG-versie is dezelfde als in de catalogus', () {
      expect(referenceStandardById('wstg')!.bundledVersion, wstgVersion);
    });

    test('de CVSS-versie past bij de opvolger-probe', () {
      // successorDocument leidt kandidaten af uit `major.minor`; een andere
      // vorm zou stil nul kandidaten opleveren en dus nooit iets vinden.
      final cvss = referenceStandardById('cvss')!;
      expect(cvss.probe, UpstreamProbe.successorDocument);
      expect(cvss.bundledVersion, matches(r'^\d+\.\d+$'));
      expect(
        cvss.probeTarget,
        contains('{version}'),
        reason: 'zonder plaatshouder valt er niets in te vullen',
      );
    });

    test('de CWE-probe wijst naar de API, niet naar de downloadpagina', () {
      final cwe = referenceStandardById('cwe')!;
      expect(cwe.probe, UpstreamProbe.cweApi);
      expect(cwe.probeTarget, startsWith('https://cwe-api.mitre.org/'));
    });

    test('de MIAUW-versie is een datum, want de probe rekent ermee', () {
      // githubCommitDate vergelijkt datums; een versienummer hier zou die
      // vergelijking stil onzinnig maken. En de datum moet die van de **bron**
      // zijn, niet de dag waarop wij het schema overnamen — dat laatste stond
      // er tot 22-07-2026 en maakte de poort onmogelijk rood.
      final miauw = referenceStandardById('miauw')!;
      expect(miauw.probe, UpstreamProbe.githubCommitDate);
      expect(miauw.bundledVersion, matches(r'^\d{4}-\d{2}-\d{2}$'));
      expect(
        miauw.probePath,
        isNotEmpty,
        reason: 'de bundel komt uit één werkboek, niet uit de hele repo',
      );
    });

    test('een probePath hoort bij een bron die per bestand te volgen is', () {
      // Een pad zonder commitdatum-probe doet niets; dat is een stille no-op en
      // precies het soort halve bedrading dat deze poort moet uitsluiten.
      for (final s in referenceStandards) {
        if (s.probePath.isEmpty) continue;
        expect(
          s.probe,
          UpstreamProbe.githubCommitDate,
          reason:
              '${s.id}: probePath wordt alleen door githubCommitDate gelezen',
        );
      }
    });

    test('LICENSE_COMPLIANCE.md noemt dezelfde versies', () {
      // De licentietabel was tot nu toe de enige plek waar sommige versies
      // stonden. Nu is het register de bron; deze test houdt het doc eraan
      // gelijk in plaats van het stil te laten verouderen.
      final doc = File('docs/LICENSE_COMPLIANCE.md').readAsStringSync();
      for (final s in referenceStandards) {
        if (s.bundledVersion.isEmpty) continue;
        expect(
          doc,
          contains(s.bundledVersion),
          reason:
              '${s.name} ${s.bundledVersion} staat niet in '
              'docs/LICENSE_COMPLIANCE.md',
        );
      }
    });
  });

  group('StandardFreshness', () {
    const s = ReferenceStandard(
      id: 'x',
      name: 'X',
      bundledVersion: '4.2',
      url: 'https://example.org',
      bundled: 'index',
      licence: 'CC-BY-SA-4.0',
      probe: UpstreamProbe.githubReleases,
      probeTarget: 'o/r',
    );

    test('gelijk = actueel', () {
      const f = StandardFreshness(standard: s, latestVersion: '4.2');
      expect(f.isCurrent, isTrue);
      expect(f.isOutdated, isFalse);
      expect(f.isUnknown, isFalse);
    });

    test('afwijkend = verouderd, ook als het nummer lager is', () {
      // MASTG ging van 1.x naar 2.0 bij de herbouw; groter-is-nieuwer gaat niet
      // op, dus elke afwijking hoort een mens te alarmeren.
      expect(
        const StandardFreshness(standard: s, latestVersion: '1.9').isOutdated,
        isTrue,
      );
    });

    test('onbekend is géén synoniem voor actueel', () {
      // De fout die deze hele poort moet voorkomen: stilte lezen als
      // goedkeuring.
      const f = StandardFreshness(
        standard: s,
        unknownReason: 'bron onbereikbaar',
      );
      expect(f.isUnknown, isTrue);
      expect(f.isCurrent, isFalse);
      expect(f.isOutdated, isFalse);
    });
  });
}
