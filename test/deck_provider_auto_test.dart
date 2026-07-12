import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/finding_numbering.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';

/// Tests the automation extension on [DeckNotifier] (P2-AUTO §10): renumbering
/// every finding in one undoable step, and stamping an imported RFC 3161
/// timestamp token onto a sealed deck (allowed post-seal because the token lives
/// outside the hashed content).
DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Slide _finding(String id, String heading) =>
    Slide.create(SlideType.finding).copyWith(
      findingId: id,
      customMarkdown: FindingSpec(heading: heading).toMarkdown(),
    );

void main() {
  group('autoRenumberFindings', () {
    test('renumbers findings sequentially in deck order', () {
      final n = _notifier();
      n.loadDeck(
        Deck(
          title: 'Rapport',
          slides: [
            Slide.create(SlideType.title).copyWith(title: 'Rapport'),
            _finding('F-05', 'Zwak wachtwoordbeleid'),
            _finding('F-09', 'Ontbrekende rate limiting'),
          ],
        ),
      );

      final count = n.autoRenumberFindings();

      expect(count, 2);
      final ids = deckFindingList(n.state.deck!).map((f) => f.id).toList();
      expect(ids, ['F-01', 'F-02']);
    });

    test('returns 0 and does nothing on a deck without findings', () {
      final n = _notifier();
      n.loadDeck(
        Deck(
          title: 'Leeg',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Leeg')],
        ),
      );
      final before = n.state.deck!;

      expect(n.autoRenumberFindings(), 0);
      // No findings → no mutation: the deck reference is left untouched.
      expect(identical(n.state.deck, before), isTrue);
      expect(deckFindingList(n.state.deck!), isEmpty);
    });

    test('returns 0 when no deck is open', () {
      expect(_notifier().autoRenumberFindings(), 0);
    });
  });

  group('setSealTimestampToken', () {
    test('stamps the token onto a sealed deck', () {
      final n = _notifier();
      n.newDeck('Verzegeld');
      n.finalizeAndSeal();
      expect(n.state.deck!.sealHash, isNotEmpty, reason: 'deck is sealed');

      n.setSealTimestampToken('base64url-tsr-token');

      expect(n.state.deck!.sealTimestampToken, 'base64url-tsr-token');
      // The deck stays finalised; the token lives outside the hashed content.
      expect(n.state.deck!.finalized, isTrue);
    });

    test('is a no-op on an unsealed deck', () {
      final n = _notifier();
      n.newDeck('Onverzegeld');
      expect(n.state.deck!.sealHash, isEmpty);

      n.setSealTimestampToken('genegeerd');

      expect(n.state.deck!.sealTimestampToken, isEmpty);
    });

    test('is a no-op when no deck is open', () {
      final n = _notifier();
      // Must not throw when there is no deck.
      n.setSealTimestampToken('genegeerd');
      expect(n.state.deck, isNull);
    });
  });
}
