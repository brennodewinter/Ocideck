import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/checklist_templates.dart';
import 'package:ocideck/services/mastg_catalog.dart';
import 'package:ocideck/services/reference_standards.dart';

void main() {
  final catalog = MastgCatalog.instance;

  group('de MASTG-catalogus', () {
    test('draagt de v2.0-index, niet de ingetrokken v1-tests', () {
      // 186 actieve tests in v2.0.0: 92 vervallen v1-tests en 14 placeholders
      // blijven er bewust uit. Verandert dit getal, dan is de catalogus
      // opnieuw gegenereerd en hoort iemand te kijken wat er is verschoven.
      expect(catalog.tests, hasLength(186));
      expect(catalog.version, '2.0.0');
      expect(catalog.standardLabel, 'OWASP MASTG v2.0.0');
    });

    test('elke test is bruikbaar als checklistregel', () {
      for (final t in catalog.tests) {
        expect(
          t.id,
          startsWith('MASTG-TEST-'),
          reason: 'onverwacht id-formaat',
        );
        expect(t.title, isNotEmpty, reason: '${t.id} heeft geen titel');
        expect(
          t.category,
          startsWith('MASVS-'),
          reason: '${t.id} zit niet in een MASVS-categorie',
        );
      }
    });

    test('ids zijn uniek', () {
      final ids = catalog.tests.map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('elke test wijst een MASWE-zwakheid aan', () {
      // De koppeling die MASTG v2 legt: een test verifieert een zwakheid. Dit
      // is meteen het aanknopingspunt voor de MASWE-lijst die hierna komt.
      for (final t in catalog.tests) {
        expect(
          t.weakness,
          startsWith('MASWE-'),
          reason: '${t.id} noemt geen zwakheid',
        );
      }
    });

    test('de platformsplitsing is volledig en overlapt niet', () {
      final android = catalog.forPlatform('android');
      final ios = catalog.forPlatform('ios');
      expect(android.length + ios.length, catalog.tests.length);
      expect(
        android
            .map((t) => t.id)
            .toSet()
            .intersection(ios.map((t) => t.id).toSet()),
        isEmpty,
      );
      expect(ios.every((t) => t.platform == 'ios'), isTrue);
    });

    test('byId vindt een bestaande test en geeft null voor de rest', () {
      final first = catalog.tests.first;
      expect(catalog.byId(first.id)?.title, first.title);
      expect(catalog.byId('MASTG-TEST-9999'), isNull);
    });
  });

  group('MASTG als checklistbron', () {
    test('staat als twee losse bronnen in de kiezer', () {
      // Bewust per platform: een checklist van 186 regels waarvan de helft niet
      // van toepassing is, wordt weggeklikt in plaats van afgewerkt.
      final labels = checklistSources(const []).map((s) => s.label).toList();
      expect(labels, contains('OWASP MASTG v2.0.0 — Android'));
      expect(labels, contains('OWASP MASTG v2.0.0 — iOS'));
    });

    test('het standaard-etiket op de slide draagt de versie', () {
      // Zo bevriest een checklist de versie waartegen is getoetst, ook als
      // OciDeck later een nieuwere MASTG meedraagt.
      final source = checklistSources(
        const [],
      ).firstWhere((s) => s.label.contains('Android'));
      expect(source.standardLabel, 'OWASP MASTG v2.0.0');
      expect(source.rows, isNotEmpty);
      expect(source.rows.first.id, startsWith('MASTG-TEST-'));
    });
  });

  group('MASTG in het register van standaarden', () {
    test('is opgenomen, met de versie uit de catalogus', () {
      final entry = referenceStandardById('mastg')!;
      expect(entry.bundledVersion, mastgVersion);
      expect(entry.licence, 'CC-BY-SA-4.0');
      expect(entry.probeTarget, 'OWASP/mastg');
    });
  });
}
