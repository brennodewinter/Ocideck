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

    test('een bevraagbare standaard noemt zijn doelwit', () {
      for (final s in referenceStandards) {
        if (s.probe == UpstreamProbe.manual) continue;
        expect(
          s.probeTarget,
          isNotEmpty,
          reason: '${s.id}: probe zonder doelwit is een stille no-op',
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

    test('de MIAUW-versie is een datum, want de probe rekent ermee', () {
      // githubReleaseDate vergelijkt met compareTo op JJJJ-MM-DD; een
      // versienummer hier zou die vergelijking stil onzinnig maken.
      final miauw = referenceStandardById('miauw')!;
      expect(miauw.probe, UpstreamProbe.githubReleaseDate);
      expect(miauw.bundledVersion, matches(r'^\d{4}-\d{2}-\d{2}$'));
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
