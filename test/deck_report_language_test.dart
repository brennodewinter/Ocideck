import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/models/miauw_compliance.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_compliance_analyzer.dart';

/// The report language (MIAUW EIS 2.3): agreed and recorded before the pentest,
/// so the deck has to be able to carry it — and carry it through a save/open
/// cycle, because a requirement that survives only in memory proves nothing.
Deck _deck({String language = ''}) => Deck(
  title: 'Rapport',
  language: language,
  slides: [
    Slide.create(SlideType.bullets).copyWith(bullets: const ['Een']),
  ],
);

Deck _roundTrip(Deck deck) {
  final markdown = MarkdownService().generateDeck(deck);
  final parsed = MarkdownService().parseDeck(markdown);
  expect(parsed, isNotNull, reason: 'deck failed to parse back');
  return parsed!;
}

void main() {
  test('a recorded report language survives the round-trip', () {
    expect(_roundTrip(_deck(language: 'nl')).language, 'nl');
    expect(_roundTrip(_deck(language: 'en')).language, 'en');
  });

  test('an unrecorded language writes no key and stays empty', () {
    final markdown = MarkdownService().generateDeck(_deck());
    expect(
      markdown.contains('language:'),
      isFalse,
      reason:
          'An empty language must stay out of the file entirely — the front '
          'matter only carries what was actually decided.',
    );
    expect(_roundTrip(_deck()).language, isEmpty);
  });

  group('EIS 2.3', () {
    final analyzer = const MiauwComplianceAnalyzer();

    EisResult resultFor(Deck deck) =>
        analyzer.analyze(deck).results.firstWhere((r) => r.entry.id == '2.3');

    test('is derived from content, not left to a human attestation', () {
      // It was `manual` for as long as the deck had nowhere to record the
      // language — filed as unprovable while it was merely unrecordable.
      expect(resultFor(_deck()).entry.derivation, EisDerivation.automatic);
      expect(resultFor(_deck()).entry.check, EisCheck.reportLanguage);
    });

    test('is open while no language is recorded', () {
      expect(resultFor(_deck()).status, EisStatus.open);
    });

    test('is met once a language is recorded', () {
      expect(resultFor(_deck(language: 'nl')).status, EisStatus.voldaan);
    });

    test('whitespace is not a record', () {
      expect(resultFor(_deck(language: '   ')).status, EisStatus.open);
    });
  });
}
