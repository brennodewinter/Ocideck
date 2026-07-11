import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Deck _deckWith(List<Slide> slides) => Deck(title: 'Rapport', slides: slides);

void main() {
  final md = MarkdownService();

  group('AI-assist marker round-trip', () {
    test('aiAssistedFields survive serialize → parse', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        title: 'Bevinding',
        bullets: const ['Eén'],
        aiAssistedFields: const ['description', 'impact'],
      );
      final markdown = md.generateDeck(_deckWith([slide]));
      expect(markdown, contains('ocideck_ai_assisted: description, impact'));

      final out = md.parseDeck(markdown)!.slides.single;
      expect(out.aiAssistedFields, ['description', 'impact']);
    });

    test('a slide without markers writes no marker comment', () {
      final markdown = md.generateDeck(
        _deckWith([
          Slide.create(SlideType.bullets).copyWith(bullets: const ['x']),
        ]),
      );
      expect(markdown.contains('ocideck_ai_assisted'), isFalse);
    });

    test('markers survive on a finding header slide too', () {
      final slide = Slide.create(SlideType.finding).copyWith(
        findingId: 'F-01',
        findingRole: FindingRole.header,
        aiAssistedFields: const ['recommendation'],
      );
      final out = md
          .parseDeck(md.generateDeck(_deckWith([slide])))!
          .slides
          .single;
      expect(out.type, SlideType.finding);
      expect(out.findingId, 'F-01');
      expect(out.aiAssistedFields, ['recommendation']);
    });
  });

  group('seal-gate helpers', () {
    test('detects the 1-based slide numbers carrying markers', () {
      final deck = _deckWith([
        Slide.create(SlideType.title),
        Slide.create(
          SlideType.bullets,
        ).copyWith(aiAssistedFields: const ['description']),
        Slide.create(SlideType.bullets),
        Slide.create(
          SlideType.bullets,
        ).copyWith(aiAssistedFields: const ['impact']),
      ]);
      expect(deckHasUnreviewedAiMarkers(deck), isTrue);
      expect(slidesWithUnreviewedAiMarkers(deck), [2, 4]);
    });

    test('a clean deck has no markers', () {
      final deck = _deckWith([Slide.create(SlideType.title)]);
      expect(deckHasUnreviewedAiMarkers(deck), isFalse);
      expect(slidesWithUnreviewedAiMarkers(deck), isEmpty);
    });
  });

  group('finalizeAndSeal gate', () {
    test('refuses to seal while an AI marker is unreviewed', () {
      final n = _notifier();
      n.loadDeck(
        _deckWith([
          Slide.create(SlideType.title),
          Slide.create(
            SlideType.bullets,
          ).copyWith(aiAssistedFields: const ['description']),
        ]),
      );
      expect(n.slidesBlockingSeal, [2]);
      n.finalizeAndSeal();
      expect(n.state.deck!.finalized, isFalse); // blocked
    });

    test('seals once the markers are cleared', () {
      final n = _notifier();
      n.loadDeck(_deckWith([Slide.create(SlideType.title)]));
      expect(n.slidesBlockingSeal, isEmpty);
      n.finalizeAndSeal();
      expect(n.state.deck!.finalized, isTrue);
      expect(n.state.deck!.sealHash, isNotEmpty);
    });
  });
}
