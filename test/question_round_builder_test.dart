import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/services/question_round_builder.dart';

/// De vraagronde-trekking is uit `_FullscreenPresenterState` gehaald naar
/// [QuestionRoundBuilder] — pure rekenkunde over het model, dus hier zonder een
/// presenter te pompen te toetsen. Een vaste [math.Random] maakt de trekking
/// herhaalbaar; wat willekeurig getrokken wordt, blijft dat, maar de invarianten
/// (welke opties, wie juist is, wanneer er geen timer loopt) liggen vast.
void main() {
  // Vaste seed zodat een schud-afhankelijke assertie niet flakert.
  QuestionRoundBuilder builder() =>
      QuestionRoundBuilder(random: math.Random(42));

  QuestionView draw(QuestionSpec spec) =>
      builder().draw(spec, trueLabel: 'Juist', falseLabel: 'Onjuist');

  group('true/false', () {
    test('toont de twee labels en markeert de juiste kant', () {
      final view = draw(
        const QuestionSpec(kind: QuestionKind.trueFalse, statementIsTrue: true),
      );
      expect(view.options, ['Juist', 'Onjuist']);
      expect(view.correctIndices, [0]);
      expect(view.answerable, isTrue);
    });

    test('een onwaar stelling maakt het tweede label juist', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.trueFalse,
          statementIsTrue: false,
        ),
      );
      expect(view.correctIndices, [1]);
    });

    test('neemt de antwoordtijd over uit de spec', () {
      final view = draw(
        const QuestionSpec(kind: QuestionKind.trueFalse, timeLimitSeconds: 20),
      );
      expect(view.totalSeconds, 20);
      expect(view.remainingMs, 20000);
      expect(view.hasTimer, isTrue);
    });
  });

  group('multiple choice', () {
    QuestionSpec spec({int optionCount = 4, int timeLimitSeconds = 0}) =>
        QuestionSpec(
          kind: QuestionKind.multipleChoice,
          optionCount: optionCount,
          timeLimitSeconds: timeLimitSeconds,
          answers: const [
            QuestionAnswer(text: 'Goed', correct: true),
            QuestionAnswer(text: 'Fout A'),
            QuestionAnswer(text: 'Fout B'),
            QuestionAnswer(text: 'Fout C'),
          ],
        );

    test('trekt optionCount opties met precies één juiste erin', () {
      final view = draw(spec(optionCount: 3));
      expect(view.options, hasLength(3));
      expect(view.correctIndices, hasLength(1));
      expect(view.options[view.correctIndices.single], 'Goed');
      expect(view.multi, isFalse);
      expect(view.answerable, isTrue);
    });

    test('zonder een fout antwoord is de vraag niet te presenteren', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.multipleChoice,
          timeLimitSeconds: 30,
          answers: [QuestionAnswer(text: 'Enig antwoord', correct: true)],
        ),
      );
      expect(view.answerable, isFalse);
      // Een onhaalbare vraag krijgt geen aftelling.
      expect(view.totalSeconds, 0);
      expect(view.remainingMs, 0);
    });
  });

  group('multiple correct', () {
    test('toont álle antwoorden en markeert elke juiste', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.multipleCorrect,
          answers: [
            QuestionAnswer(text: 'A', correct: true),
            QuestionAnswer(text: 'B'),
            QuestionAnswer(text: 'C', correct: true),
          ],
        ),
      );
      expect(view.options.toSet(), {'A', 'B', 'C'});
      expect(view.multi, isTrue);
      // Elke aangemerkte juiste zit in correctIndices, geen enkele foute.
      final correctTexts = [
        for (final i in view.correctIndices) view.options[i],
      ];
      expect(correctTexts.toSet(), {'A', 'C'});
    });

    test('zonder aangemerkt juist antwoord blokkeert het niet', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.multipleCorrect,
          answers: [
            QuestionAnswer(text: 'A'),
            QuestionAnswer(text: 'B'),
          ],
        ),
      );
      expect(view.answerable, isFalse);
    });
  });

  group('ordering', () {
    test('toont geschud, met de auteursvolgorde als juiste sleutel', () {
      const spec = QuestionSpec(
        kind: QuestionKind.ordering,
        optionCount: 3,
        answers: [
          QuestionAnswer(text: 'Eerst'),
          QuestionAnswer(text: 'Dan'),
          QuestionAnswer(text: 'Slot'),
        ],
      );
      final view = draw(spec);
      expect(view.ordering, isTrue);
      expect(view.multi, isTrue);
      expect(view.options.toSet(), {'Eerst', 'Dan', 'Slot'});
      // correctIndices[k] wijst de optie aan die op plek k hoort; die reeks
      // teruglezen moet de auteursvolgorde herstellen.
      final restored = [for (final i in view.correctIndices) view.options[i]];
      expect(restored, ['Eerst', 'Dan', 'Slot']);
    });

    test('met minder dan twee antwoorden niet presenteerbaar', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.ordering,
          answers: [QuestionAnswer(text: 'Alleen dit')],
        ),
      );
      expect(view.answerable, isFalse);
    });
  });

  group('open text', () {
    test('is een getypt antwoord zonder vooraf getoonde opties', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.openText,
          answers: [QuestionAnswer(text: 'sleutelwoord', correct: true)],
        ),
      );
      expect(view.openText, isTrue);
      expect(view.answerable, isTrue);
      expect(view.options, isEmpty);
    });

    test('zonder juist antwoord niet presenteerbaar', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.openText,
          answers: [QuestionAnswer(text: 'niet aangemerkt')],
        ),
      );
      expect(view.answerable, isFalse);
    });
  });

  group('image pair', () {
    test('toont één juiste en één foute afbeelding', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.imagePair,
          answers: [
            QuestionAnswer(image: 'goed.png', correct: true),
            QuestionAnswer(image: 'fout.png'),
          ],
        ),
      );
      expect(view.options, hasLength(2));
      expect(view.optionImages.where((p) => p.isNotEmpty), hasLength(2));
      expect(view.correctIndices, hasLength(1));
      expect(view.optionImages[view.correctIndices.single], 'goed.png');
      expect(view.hasImages, isTrue);
    });

    test('zonder een tegenbeeld niet presenteerbaar', () {
      final view = draw(
        const QuestionSpec(
          kind: QuestionKind.imagePair,
          answers: [QuestionAnswer(image: 'alleen-goed.png', correct: true)],
        ),
      );
      expect(view.answerable, isFalse);
    });
  });

  test('een verse Random per aanroep levert nog steeds geldige rondes', () {
    // Zonder injectie (de productiestand) mag de trekking niet gooien en moet
    // ze aan dezelfde invarianten voldoen.
    const spec = QuestionSpec(
      kind: QuestionKind.multipleChoice,
      answers: [
        QuestionAnswer(text: 'Goed', correct: true),
        QuestionAnswer(text: 'Fout'),
      ],
    );
    for (var i = 0; i < 20; i++) {
      final view = QuestionRoundBuilder().draw(
        spec,
        trueLabel: 'Juist',
        falseLabel: 'Onjuist',
      );
      expect(view.options, contains('Goed'));
      expect(view.options[view.correctIndices.single], 'Goed');
    }
  });
}
