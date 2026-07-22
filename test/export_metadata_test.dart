import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

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

    test('creator and producer identify OciDeck', () {
      const meta = ExportDocumentMetadata();
      expect(meta.creator, kOciDeckCreator);
      expect(meta.producer, kOciDeckProducer);
    });

    test('documentAuthor prefers author over organization', () {
      const meta = ExportDocumentMetadata(author: 'Alex', organization: 'Acme');
      expect(meta.documentAuthor, 'Alex');
    });

    test('fromDeck copies deck fields', () {
      final meta = ExportDocumentMetadata.fromDeck(
        PrivacyProjection.forAudience(
          Deck(
            title: 'Rapport',
            author: 'Bob',
            organization: 'Org',
            description: 'Intern',
            keywords: 'rapport',
            tlp: TlpLevel.red,
            slides: [Slide.create(SlideType.title)],
          ),
        ),
      );
      expect(meta.subject('x'), 'TLP:RED — Rapport');
      expect(meta.exportKeywords(), contains('TLP:RED'));
      expect(meta.documentAuthor, 'Bob');
    });

    test('fromDeck kan de bron niet meer bereiken', () {
      // Waarom deze fabriek een AudienceDeck eist en geen Deck: deze zes velden
      // belanden leesbaar in de PDF-info en de PPTX-docProps, ook al staat er op
      // geen enkele dia iets van te zien. Nam ze een rauwe Deck, dan was
      // "vergeten te projecteren" hier een stille lek — precies wat de
      // projectiegrens elders juist afvangt. Nu ís er geen weg langs de
      // projectie: de compiler weigert het, en wat er wél doorkomt is geredigeerd.
      final meta = ExportDocumentMetadata.fromDeck(
        PrivacyProjection.forAudience(
          Deck(
            title: 'Rapport',
            author: 'jan@klant.nl',
            privacy: PrivacyDisposition.redact,
            slides: [Slide.create(SlideType.title)],
          ),
        ),
      );
      expect(meta.documentAuthor, isNot(contains('jan@klant.nl')));
      expect(meta.documentAuthor, contains(kRedactionBlock));
    });
  });
}
