import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/deck_quality_provider.dart';

/// De lege-dia-melding op een deck dat de gebruiker nog niet heeft aangeraakt.
///
/// 'Leeg deck' levert sinds deze wijziging één lege dia in plaats van een
/// titelpagina met de ingetypte titel erop. Daarmee begroette de app een vers
/// deck meteen met "Deze dia is leeg" — een verwijt over precies wat de
/// gebruiker zelf net had gevraagd. De melding zwijgt nu tot hij iets doet.
void main() {
  // De instellingen (stijlprofiel, contrastdrempel) hangen aan
  // SharedPreferences; zonder binding + mock sterft al het aanmaken van een
  // deck, nog voor er iets te meten valt.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer newContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  bool hasEmptySlideIssue(ProviderContainer container) => container
      .read(deckQualityProvider)
      .issues
      .any((issue) => issue.kind == SlideQualityIssueKind.emptySlide);

  test('een vers, leeg deck krijgt geen lege-dia-melding', () {
    final container = newContainer();
    container
        .read(deckProvider.notifier)
        .newDeck('Leegproef', slides: [Slide.create(SlideType.bullets)]);

    expect(hasEmptySlideIssue(container), isFalse);
    // Ook de ruwe analyse zwijgt, anders zet de miniatuur alsnog een badge op
    // een dia waar de gebruiker nog niets mee heeft gedaan.
    expect(
      container
          .read(deckQualityRawProvider)
          .issues
          .where((issue) => issue.kind == SlideQualityIssueKind.emptySlide),
      isEmpty,
    );
  });

  test('zodra de gebruiker iets doet, telt de melding weer mee', () {
    final container = newContainer();
    final notifier = container.read(deckProvider.notifier)
      ..newDeck('Leegproef', slides: [Slide.create(SlideType.bullets)]);

    // Een bewerking die de dia leeg láát: de gebruiker is begonnen, dus de
    // melding hoort terug te komen — ook al staat er nog steeds niets.
    notifier.addSlide(SlideType.bullets);

    expect(container.read(deckProvider).canUndo, isTrue);
    expect(hasEmptySlideIssue(container), isTrue);
  });

  test('een geopend deck met een lege dia waarschuwt gewoon', () {
    // Er is een bestand, dus dit deck is niet meer "nog nooit aangeraakt": de
    // lege dia stond blijkbaar al op schijf, en dat is wél iets om te melden.
    final container = newContainer();
    container
        .read(deckProvider.notifier)
        .loadDeck(
          Deck(title: 'Van schijf', slides: [Slide.create(SlideType.bullets)]),
          filePath: '/tmp/van-schijf.md',
        );

    expect(hasEmptySlideIssue(container), isTrue);
  });

  test('andere meldingen blijven ook op een vers deck staan', () {
    // De stilte geldt alleen de lege dia. Een melding over wat er wél staat —
    // hier een vraag die niet te spelen is — hoort meteen zichtbaar te zijn,
    // ook op een deck dat nog nergens is opgeslagen.
    final container = newContainer();
    container
        .read(deckProvider.notifier)
        .newDeck(
          'Quiz',
          slides: [
            Slide.create(SlideType.question).copyWith(
              customMarkdown: const QuestionSpec(
                prompt: 'Wat is het antwoord?',
                answers: [QuestionAnswer(text: 'Enige optie', correct: false)],
              ).toBlock(),
            ),
          ],
        );

    expect(
      container.read(deckQualityProvider).issues.map((i) => i.kind),
      contains(SlideQualityIssueKind.questionNotAnswerable),
    );
  });
}
