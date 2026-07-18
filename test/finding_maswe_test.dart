import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/services/maswe_catalog.dart';

void main() {
  final known = MasweCatalog.instance.weaknesses.first;

  group('MASWE in een bevinding', () {
    test('round-trippt door de markdown', () {
      final spec = FindingSpec(heading: 'F-01 · Iets', masweId: known.id);
      final back = FindingSpec.parse(spec.toMarkdown());
      expect(back.masweId, known.id);
    });

    test('schrijft id én titel, met een link naar de juiste pagina', () {
      final md = FindingSpec(heading: 'F-01', masweId: known.id).toMarkdown();
      expect(md, contains('**MASWE:**'));
      expect(md, contains(known.id));
      expect(md, contains(known.title));
      // De categorie zit ín de URL; die komt uit de catalogus en niet uit de
      // bevinding, anders zou een verkeerd opgeslagen categorie een 404 geven.
      expect(
        md,
        contains('mas.owasp.org/MASWE/${known.category}/${known.id}/'),
      );
    });

    test('staat naast CWE, niet in plaats daarvan', () {
      final md = FindingSpec(
        heading: 'F-01',
        cweId: 89,
        masweId: known.id,
      ).toMarkdown();
      expect(md, contains('**CWE:**'));
      expect(md, contains('**MASWE:**'));
    });

    test('geen MASWE betekent geen regel', () {
      expect(
        const FindingSpec(heading: 'F-01').toMarkdown(),
        isNot(contains('MASWE')),
      );
    });
  });

  group('een id dat wij niet kennen', () {
    // Kan gebeuren: de tester typt een id dat nieuwer is dan onze
    // momentopname, of MASWE hernummert.
    const unknown = 'MASWE-9999';

    test('blijft bewaard en leesbaar, maar zonder link', () {
      final md = FindingSpec(heading: 'F-01', masweId: unknown).toMarkdown();
      expect(md, contains(unknown));
      expect(
        md,
        isNot(contains('mas.owasp.org')),
        reason: 'liever geen link dan een die op een 404 uitkomt',
      );
      expect(FindingSpec.parse(md).masweId, unknown);
    });

    test('levert geen titel en geen url op', () {
      const spec = FindingSpec(heading: 'F-01', masweId: unknown);
      expect(spec.masweTitle, isEmpty);
      expect(spec.masweUrl, isNull);
    });
  });
}
