import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mastg_catalog.dart';
import 'package:ocideck/services/maswe_catalog.dart';
import 'package:ocideck/services/reference_standards.dart';
import 'package:ocideck/services/secmodule/sec_reference_inventory.dart';

void main() {
  final catalog = MasweCatalog.instance;

  group('de MASWE-lijst', () {
    test('draagt alle niet-ingetrokken zwakheden', () {
      // 117 van de 119: twee zijn door OWASP ingetrokken en die citeer je niet.
      expect(catalog.weaknesses, hasLength(117));
    });

    test('drie kwart is bij de bron nog niet uitgeschreven', () {
      // Dit getal is geen detail maar de staat van de standaard. Loopt het
      // hard terug, dan heeft OWASP doorgeschreven en is een herziening van
      // de aanroepers de moeite waard.
      expect(catalog.written, hasLength(28));
      expect(catalog.weaknesses.where((w) => w.isPlaceholder), hasLength(89));
    });

    test('ook een conceptzwakheid is volwaardig te citeren', () {
      // Precies het verschil met MASTG, waar placeholders juist wegblijven:
      // hier is de zwakheid geïdentificeerd, alleen de uitleg ontbreekt.
      final draft = catalog.weaknesses.firstWhere((w) => w.isPlaceholder);
      expect(draft.id, startsWith('MASWE-'));
      expect(draft.title, isNotEmpty);
      expect(draft.category, startsWith('MASVS-'));
    });

    test('ids zijn uniek en gesorteerd', () {
      final ids = catalog.weaknesses.map((w) => w.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, orderedEquals([...ids]..sort()));
    });

    test('byId vindt beide helften van de gesplitste data', () {
      final written = catalog.written.first;
      final draft = catalog.weaknesses.firstWhere((w) => w.isPlaceholder);
      expect(catalog.byId(written.id), isNotNull);
      expect(catalog.byId(draft.id), isNotNull);
      expect(catalog.byId('MASWE-9999'), isNull);
    });
  });

  group('de brug naar CWE', () {
    test('vrijwel elke zwakheid komt op een CWE uit', () {
      final withCwe = catalog.weaknesses.where((w) => w.cweIds.isNotEmpty);
      expect(withCwe.length, greaterThan(catalog.weaknesses.length - 6));
    });

    test('forCwe vindt de mobiele zwakheid bij een CWE-nummer', () {
      // De brug tussen de mobiele en de algemene taal: een bevinding met een
      // CWE kan zo de mobiele tegenhanger vinden.
      final any = catalog.weaknesses.firstWhere((w) => w.cweIds.isNotEmpty);
      expect(catalog.forCwe(any.cweIds.first), contains(any));
      expect(catalog.forCwe(999999), isEmpty);
    });
  });

  group('de koppeling met MASTG', () {
    test('elke MASTG-test wijst een zwakheid aan die wij kennen', () {
      // Als dit valt, lopen de twee momentopnamen uiteen: MASTG verwijst dan
      // naar een zwakheid die in onze MASWE-lijst ontbreekt, en dan klopt de
      // koppeling in een rapport niet meer.
      final unknown = <String>[];
      for (final t in MastgCatalog.instance.tests) {
        if (catalog.byId(t.weakness) == null) unknown.add(t.weakness);
      }
      expect(
        unknown.toSet(),
        isEmpty,
        reason: 'MASTG noemt zwakheden die MASWE hier niet heeft',
      );
    });
  });

  group('registratie', () {
    test('MASWE staat in het register, op datum bevraagd', () {
      final entry = referenceStandardById('maswe')!;
      expect(entry.bundledVersion, masweSnapshotDate);
      expect(entry.probeTarget, 'OWASP/maswe');
      expect(entry.licence, 'CC-BY-SA-4.0');
    });

    test('MASTG en MASWE staan in de referentie-inventaris', () {
      // MASTG ontbrak hier na PR #328; met MASWE erbij is dat rechtgezet.
      final names = SecReferenceInventory.snapshot().map((c) => c.name);
      expect(names, contains('Testgevallen (MASTG)'));
      expect(names, contains('Mobiele zwakheden (MASWE)'));
    });
  });
}
