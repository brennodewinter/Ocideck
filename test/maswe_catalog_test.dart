import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/mastg_catalog.dart';
import 'package:ocideck/services/maswe_catalog.dart';
import 'package:ocideck/services/reference_standards.dart';
import 'package:ocideck/services/info_safety/info_safety_reference_inventory.dart';

void main() {
  final catalog = MasweCatalog.instance;

  group('de MASWE-lijst', () {
    test('draagt de 78 uitgeschreven zwakheden', () {
      // De herbouw medio 2026 bracht de lijst van 117 (grotendeels concept)
      // terug naar 78 volledig uitgeschreven zwakheden, MASWE-0001..0078.
      expect(catalog.weaknesses, hasLength(78));
      expect(catalog.weaknesses.first.id, 'MASWE-0001');
      expect(catalog.weaknesses.last.id, 'MASWE-0078');
    });

    test('elke zwakheid draagt een omschrijving uit de bron', () {
      // De `requirement:` van OWASP — één zin over wat de app moet doen. Sinds
      // de herbouw heeft élke zwakheid er een.
      for (final w in catalog.weaknesses) {
        expect(w.description, isNotEmpty, reason: '${w.id} mist omschrijving');
      }
    });

    test('ids zijn uniek en gesorteerd', () {
      final ids = catalog.weaknesses.map((w) => w.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, orderedEquals([...ids]..sort()));
    });

    test('elke id ziet eruit als MASWE-0000 met een MASVS-categorie', () {
      for (final w in catalog.weaknesses) {
        expect(w.id, matches(RegExp(r'^MASWE-\d{4}$')));
        expect(w.category, startsWith('MASVS-'));
        expect(w.title, isNotEmpty);
      }
    });

    test('byId vindt een zwakheid en mist een onbekende', () {
      expect(catalog.byId('MASWE-0001'), isNotNull);
      expect(catalog.byId('MASWE-9999'), isNull);
    });

    test('elk canoniek id lost op naar zichzelf, nooit naar een alias', () {
      // De valkuil: beta- en canonieke id's delen dezelfde nummerruimte, dus
      // een huidige zwakheid (bv. MASWE-0001) is óók een beta-id dat elders is
      // opgegaan. byId moet de huidige zwakheid teruggeven, niet de
      // beta-opvolger — anders wijst elke bevinding met een laag id naar de
      // verkeerde titel. Precies de bug die finding_maswe_test ving.
      for (final w in catalog.weaknesses) {
        expect(catalog.byId(w.id)?.id, w.id, reason: '${w.id} werd omgeleid');
      }
    });
  });

  group('de brug naar CWE', () {
    test('de meeste zwakheden komen op een CWE uit', () {
      // 71 van de 78 dragen een CWE-koppeling. De zeven zonder zijn de
      // detectie-zwakheden (root-/debugger-/emulator-detectie e.d.), waar de
      // bron zelf geen CWE noemt — een ontbrekende detectie laat zich niet in
      // één CWE vangen.
      final withCwe = catalog.weaknesses.where((w) => w.cweIds.isNotEmpty);
      expect(withCwe.length, greaterThanOrEqualTo(70));
    });

    test('forCwe vindt de mobiele zwakheid bij een CWE-nummer', () {
      // De brug tussen de mobiele en de algemene taal: een bevinding met een
      // CWE kan zo de mobiele tegenhanger vinden.
      final any = catalog.weaknesses.firstWhere((w) => w.cweIds.isNotEmpty);
      expect(catalog.forCwe(any.cweIds.first), contains(any));
      expect(catalog.forCwe(999999), isEmpty);
    });
  });

  group('de beta-brug', () {
    test('een oud beta-id lost op naar zijn canonieke opvolger', () {
      // Upstream heeft de nummering herzien; de oude concept-id's boven 0078
      // leven voort als alias. byId moet ze nog herkennen, anders breekt elke
      // verwijzing uit de beta-tijd (waaronder de gebundelde MASTG v2.0.0).
      final viaBeta = catalog.byId('MASWE-0119');
      expect(viaBeta, isNotNull);
      expect(viaBeta!.id, 'MASWE-0018');
    });

    test('de twee hand-gekoppelde beta-id\'s lossen op', () {
      // MASWE-0097 (root-/jailbreak-detectie) gaf upstream geen beta-koppeling;
      // hij is met de hand op MASWE-0051 gezet. MASWE-0108 splitst en is op
      // 0073 vastgezet. Beide MOETEN oplosbaar zijn, anders valt de
      // MASTG-koppeling hieronder.
      expect(catalog.byId('MASWE-0097')?.id, 'MASWE-0051');
      expect(catalog.byId('MASWE-0108')?.id, 'MASWE-0073');
    });
  });

  group('de koppeling met MASTG', () {
    test('elke MASTG-test wijst een zwakheid aan die wij kennen', () {
      // Als dit valt, lopen de twee momentopnamen uiteen: MASTG verwijst dan
      // naar een zwakheid (mogelijk via de beta-brug) die in onze MASWE-lijst
      // ontbreekt, en dan klopt de koppeling in een rapport niet meer.
      final unknown = <String>[];
      for (final t in MastgCatalog.instance.tests) {
        if (catalog.byId(t.weakness) == null) unknown.add(t.weakness);
      }
      expect(
        unknown.toSet(),
        isEmpty,
        reason: 'MASTG noemt zwakheden die MASWE hier niet (meer) kent',
      );
    });
  });

  group('registratie', () {
    test('MASWE staat in het register, op datum bevraagd', () {
      final entry = referenceStandardById('maswe')!;
      expect(entry.bundledVersion, masweSnapshotDate);
      expect(entry.probeTarget, 'OWASP/maswe');
      expect(entry.licence, 'CC-BY-SA-4.0');
      // De formaatmigratie (#1156) is voltooid: niet langer adviserend.
      expect(entry.advisory, isFalse);
    });

    test('MASTG en MASWE staan in de referentie-inventaris', () {
      // MASTG ontbrak hier na PR #328; met MASWE erbij is dat rechtgezet.
      final names = InfoSafetyReferenceInventory.snapshot().map((c) => c.name);
      expect(names, contains('Testgevallen (MASTG)'));
      expect(names, contains('Mobiele zwakheden (MASWE)'));
    });
  });
}
