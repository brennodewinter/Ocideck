import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_footnote_setup.dart';

void main() {
  group('documentFootnotePlacement (#1678)', () {
    test('document → achterin', () {
      const source = '---\nreference-location: document\n---\n\n# Titel\n';
      expect(documentFootnotePlacement(source), FootnotePlacement.document);
    });

    test('section ≠ document (Pandoc-semanticus wordt niet uitgevoerd)', () {
      const source = '---\nreference-location: section\n---\n\n# Titel\n';
      // OciDeck voert per-sectie plaatsing niet uit; veilig terugvallen op
      // page (noten op de pagina), niet document (alles achterin).
      expect(documentFootnotePlacement(source), FootnotePlacement.page);
    });

    test('block ≠ document', () {
      const source = '---\nreference-location: block\n---\n\n# Titel\n';
      expect(documentFootnotePlacement(source), FootnotePlacement.page);
    });

    test('onbekende waarde → page', () {
      const source = '---\nreference-location: onzin\n---\n\n# Titel\n';
      expect(documentFootnotePlacement(source), FootnotePlacement.page);
    });

    test('geen sleutel → page', () {
      const source = '# Titel\n';
      expect(documentFootnotePlacement(source), FootnotePlacement.page);
    });
  });
}
