import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';

void main() {
  group('ExportDocumentMetadata', () {
    test('subject prefixes classification when set', () {
      const meta = ExportDocumentMetadata(
        title: 'Kwartaalupdate',
        tlp: TlpLevel.amber,
      );
      expect(meta.subject('deck'), 'TLP:AMBER — Kwartaalupdate');
    });

    test('subject falls back to title when unclassified', () {
      const meta = ExportDocumentMetadata(title: 'Kwartaalupdate');
      expect(meta.subject('deck'), 'Kwartaalupdate');
      expect(meta.subject('deck'), meta.displayTitle('deck'));
    });

    test('exportKeywords merges deck keywords and TLP markers', () {
      const meta = ExportDocumentMetadata(
        keywords: 'kwartaal, cijfers',
        tlp: TlpLevel.green,
      );
      expect(
        meta.exportKeywords(),
        'kwartaal, cijfers, TLP, TLP:GREEN, green, OciDeck',
      );
    });

    test('exportKeywords always includes OciDeck', () {
      expect(const ExportDocumentMetadata().exportKeywords(), 'OciDeck');
    });

    test('documentAuthor prefers author over organization', () {
      const meta = ExportDocumentMetadata(
        author: 'Alex',
        organization: 'Acme',
      );
      expect(meta.documentAuthor, 'Alex');
    });

    test('fromDeck copies deck fields', () {
      final meta = ExportDocumentMetadata.fromDeck(
        Deck(
          title: 'Rapport',
          author: 'Bob',
          organization: 'Org',
          description: 'Intern',
          keywords: 'rapport',
          tlp: TlpLevel.red,
          slides: [Slide.create(SlideType.title)],
        ),
      );
      expect(meta.subject('x'), 'TLP:RED — Rapport');
      expect(meta.exportKeywords(), contains('TLP:RED'));
      expect(meta.documentAuthor, 'Bob');
    });
  });
}
