import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';

import 'support/question_answer_limit_fixture.dart';

void main() {
  group('QuestionAnswer', () {
    test('round-trips through JSON and copyWith', () {
      const a = QuestionAnswer(text: 'Yes', correct: true);
      final j = a.toJson();
      expect(j, {'text': 'Yes', 'correct': true});

      final b = QuestionAnswer.fromJson(j);
      expect(b.text, 'Yes');
      expect(b.correct, isTrue);

      final c = a.copyWith(correct: false);
      expect(c.text, 'Yes');
      expect(c.correct, isFalse);
    });

    test('fromJson tolerates missing/loose fields', () {
      final a = QuestionAnswer.fromJson(const {});
      expect(a.text, '');
      expect(a.correct, isFalse);
      // `correct` is only true for the literal boolean true.
      expect(QuestionAnswer.fromJson({'correct': 'true'}).correct, isFalse);
      expect(QuestionAnswer.fromJson({'text': 7}).text, '7');
    });
  });

  group('QuestionSpec.parse', () {
    test('reads a well-formed block and normalises the prompt', () {
      final spec = QuestionSpec.parse('''
{
  "kind": "multipleCorrect",
  "prompt": "  Pick the primes  ",
  "optionCount": 5,
  "timeLimitSeconds": 30,
  "onWrong": "lockAndContinue",
  "answers": [
    {"text": "2", "correct": true},
    {"text": "4", "correct": false}
  ]
}
''');
      expect(spec.kind, QuestionKind.multipleCorrect);
      expect(spec.prompt, 'Pick the primes'); // trimmed by normalized()
      expect(spec.optionCount, 5);
      expect(spec.timeLimitSeconds, 30);
      expect(spec.onWrong, QuestionOnWrong.lockAndContinue);
      expect(spec.answers, hasLength(2));
      expect(spec.correctAnswers.map((a) => a.text), ['2']);
      expect(spec.wrongAnswers.map((a) => a.text), ['4']);
    });

    test('falls back to the default for invalid or non-object JSON', () {
      expect(
        QuestionSpec.parse('not json').prompt,
        QuestionSpec.defaultMultipleChoice().prompt,
      );
      // Valid JSON, but not an object.
      expect(QuestionSpec.parse('[1, 2, 3]').kind, QuestionKind.multipleChoice);
    });

    test('unknown enum names fall back to their defaults', () {
      final spec = QuestionSpec.parse(
        '{"kind":"sideways","onWrong":"explode"}',
      );
      expect(spec.kind, QuestionKind.multipleChoice);
      expect(spec.onWrong, QuestionOnWrong.retry);
    });

    test('clamps option count and time limit, and coerces loose numbers', () {
      final low = QuestionSpec.parse('{"optionCount":0,"timeLimitSeconds":-9}');
      expect(low.optionCount, questionMinOptionCount);
      expect(low.timeLimitSeconds, 0);

      final high = QuestionSpec.parse(
        '{"optionCount":99,"timeLimitSeconds":999999}',
      );
      expect(high.optionCount, questionMaxOptionCount);
      expect(high.timeLimitSeconds, questionMaxTimeLimitSeconds);

      // Strings and fractional numbers are coerced to ints.
      final loose = QuestionSpec.parse(
        '{"optionCount":"6","timeLimitSeconds":12.7}',
      );
      expect(loose.optionCount, 6);
      expect(loose.timeLimitSeconds, 13);
    });

    test('keeps the visible option limit separate from answer-bank limits', () {
      expect(questionMaxOptionCount, 8);
      expect(questionMaxAnswerPoolCount, 32);
      expect(questionAnswerCountLimit(QuestionKind.multipleChoice), 32);
      expect(questionAnswerCountLimit(QuestionKind.ordering), 32);
      expect(questionAnswerCountLimit(QuestionKind.imagePair), 32);
      expect(questionAnswerCountLimit(QuestionKind.openText), 32);
      expect(questionAnswerCountLimit(QuestionKind.multipleCorrect), 8);
      expect(questionAnswerCountLimit(QuestionKind.trueFalse), 8);

      final spec = QuestionSpec.parse(
        multipleChoiceBeerQuestionBlock(20, optionCount: 99),
      );
      expect(spec.optionCount, 8);
      expect(spec.answers, hasLength(20));
    });

    test('statementIsTrue defaults true unless explicitly false', () {
      expect(QuestionSpec.parse('{}').statementIsTrue, isTrue);
      expect(
        QuestionSpec.parse('{"statementIsTrue":false}').statementIsTrue,
        isFalse,
      );
    });

    test('accepts exactly eight answers', () {
      final spec = QuestionSpec.parse(questionBlockWithAnswers(8));

      expect(spec.hasValidAnswerCount, isTrue);
      expect(spec.sourceAnswerCount, 8);
      expect(spec.answers, hasLength(8));
    });

    test('accepts a multiple-choice answer bank of twenty', () {
      final spec = QuestionSpec.parse(multipleChoiceBeerQuestionBlock(20));

      expect(spec.prompt, 'Wat is geen bier?');
      expect(spec.hasValidAnswerCount, isTrue);
      expect(spec.sourceAnswerCount, 20);
      expect(spec.answers, hasLength(20));
      expect(
        spec.correctAnswers.map((answer) => answer.text),
        multipleChoiceNonBeers,
      );
      expect(spec.wrongAnswers, hasLength(15));
    });

    test('accepts 32 but preserves and rejects 33 multiple-choice answers', () {
      final atLimit = QuestionSpec.parse(multipleChoiceBeerQuestionBlock(32));
      expect(atLimit.hasValidAnswerCount, isTrue);
      expect(atLimit.sourceAnswerCount, 32);
      expect(atLimit.answers, hasLength(32));

      final overLimitSource = multipleChoiceBeerQuestionBlock(33);
      final overLimit = QuestionSpec.parse(overLimitSource);
      expect(overLimit.hasValidAnswerCount, isFalse);
      expect(overLimit.sourceAnswerCount, 33);
      expect(overLimit.answers, isEmpty);
      expect(overLimit.toBlock(), overLimitSource);
    });

    test('rejects a ninth answer without changing the source', () {
      final source = questionBlockWithAnswers(9);
      final spec = QuestionSpec.parse(source);

      expect(spec.hasValidAnswerCount, isFalse);
      expect(spec.sourceAnswerCount, 9);
      expect(spec.answers, isEmpty);
      expect(spec.isPresentable, isFalse);
      expect(spec.toBlock(), source);
    });

    test('does not materialise the 10,000-answer regression fixture', () {
      final source = multipleChoiceBeerQuestionBlock(10000);
      final spec = QuestionSpec.parse(source);

      expect(spec.hasValidAnswerCount, isFalse);
      expect(spec.sourceAnswerCount, 10000);
      expect(spec.answers, isEmpty);
      expect(spec.toBlock(), source);
    });
  });

  group('QuestionSpec', () {
    test('toBlock → parse round-trips a true/false spec', () {
      const original = QuestionSpec(
        kind: QuestionKind.trueFalse,
        prompt: 'The earth is flat',
        optionCount: 2,
        timeLimitSeconds: 15,
        onWrong: QuestionOnWrong.lockAndContinue,
        statementIsTrue: false,
      );
      final block = original.toBlock();
      // true/false specs persist the statement flag.
      expect(jsonDecode(block)['statementIsTrue'], isFalse);

      final back = QuestionSpec.parse(block);
      expect(back.kind, QuestionKind.trueFalse);
      expect(back.prompt, 'The earth is flat');
      expect(back.optionCount, 2);
      expect(back.timeLimitSeconds, 15);
      expect(back.onWrong, QuestionOnWrong.lockAndContinue);
      expect(back.statementIsTrue, isFalse);
    });

    test('toBlock omits statementIsTrue for non true/false kinds', () {
      const spec = QuestionSpec(kind: QuestionKind.multipleChoice);
      expect(
        jsonDecode(spec.toBlock()).containsKey('statementIsTrue'),
        isFalse,
      );
    });

    test('isPresentable needs a correct and a wrong answer (except T/F)', () {
      expect(
        const QuestionSpec(kind: QuestionKind.trueFalse).isPresentable,
        isTrue,
      );
      const onlyCorrect = QuestionSpec(
        answers: [QuestionAnswer(text: 'a', correct: true)],
      );
      expect(onlyCorrect.isPresentable, isFalse);
      const both = QuestionSpec(
        answers: [
          QuestionAnswer(text: 'a', correct: true),
          QuestionAnswer(text: 'b'),
        ],
      );
      expect(both.isPresentable, isTrue);
      // Blank-text answers are ignored.
      const blanks = QuestionSpec(
        answers: [
          QuestionAnswer(text: '  ', correct: true),
          QuestionAnswer(text: 'b'),
        ],
      );
      expect(blanks.isPresentable, isFalse);
    });

    test('toBlock → parse round-trips an ordering spec', () {
      const original = QuestionSpec(
        kind: QuestionKind.ordering,
        prompt: 'Zet de stappen in volgorde',
        answers: [
          QuestionAnswer(text: 'Eerst'),
          QuestionAnswer(text: 'Dan'),
          QuestionAnswer(text: 'Tot slot'),
        ],
        optionCount: 3,
      );
      final back = QuestionSpec.parse(original.toBlock());
      expect(back.kind, QuestionKind.ordering);
      // De lijstvolgorde ís het juiste antwoord en moet exact bewaard blijven.
      expect(back.filledAnswers.map((a) => a.text), [
        'Eerst',
        'Dan',
        'Tot slot',
      ]);
    });

    test('ordering isPresentable needs at least two filled answers', () {
      const one = QuestionSpec(
        kind: QuestionKind.ordering,
        answers: [
          QuestionAnswer(text: 'a'),
          QuestionAnswer(text: '  '),
        ],
      );
      expect(one.isPresentable, isFalse);
      const two = QuestionSpec(
        kind: QuestionKind.ordering,
        answers: [
          QuestionAnswer(text: 'a'),
          QuestionAnswer(text: 'b'),
        ],
      );
      expect(two.isPresentable, isTrue);
    });

    test('copyWith re-clamps the numeric fields', () {
      final spec = QuestionSpec.defaultMultipleChoice().copyWith(
        optionCount: 100,
        timeLimitSeconds: -1,
        prompt: 'New',
      );
      expect(spec.optionCount, questionMaxOptionCount);
      expect(spec.timeLimitSeconds, 0);
      expect(spec.prompt, 'New');
    });
  });

  group('QuestionView', () {
    const view = QuestionView(
      options: ['a', 'b', 'c'],
      correctIndices: [1],
      selectedIndices: [1],
      result: QuestionResult.correct,
      totalSeconds: 20,
      remainingMs: 5000,
    );

    test('index predicates and derived getters', () {
      expect(view.isCorrect(1), isTrue);
      expect(view.isCorrect(0), isFalse);
      expect(view.isSelected(1), isTrue);
      expect(view.hasSelection, isTrue);
      expect(view.hasTimer, isTrue);
      expect(view.passed, isTrue); // correct
    });

    test('passed is true for a locked wrong answer, false otherwise', () {
      const wrongLocked = QuestionView(
        result: QuestionResult.wrong,
        locked: true,
      );
      expect(wrongLocked.passed, isTrue);
      const wrongOpen = QuestionView(result: QuestionResult.wrong);
      expect(wrongOpen.passed, isFalse);
      expect(const QuestionView().hasTimer, isFalse);
    });

    test('round-trips through JSON', () {
      final back = QuestionView.fromJson(view.toJson());
      expect(back.options, ['a', 'b', 'c']);
      expect(back.correctIndices, [1]);
      expect(back.selectedIndices, [1]);
      expect(back.result, QuestionResult.correct);
      expect(back.totalSeconds, 20);
      expect(back.remainingMs, 5000);
    });

    test('fromJson fills defaults for an empty map', () {
      final v = QuestionView.fromJson(const {});
      expect(v.options, isEmpty);
      expect(v.result, QuestionResult.none);
      expect(v.multi, isFalse);
      expect(v.locked, isFalse);
      expect(v.totalSeconds, 0);
    });

    test('copyWith overrides only the given fields', () {
      final v = view.copyWith(locked: true, result: QuestionResult.wrong);
      expect(v.locked, isTrue);
      expect(v.result, QuestionResult.wrong);
      expect(v.options, view.options); // untouched
    });
  });

  group('QuestionView ordering', () {
    // Juiste volgorde: b (optie 1), a (optie 0), c (optie 2).
    const base = QuestionView(
      options: ['a', 'b', 'c'],
      correctIndices: [1, 0, 2],
      multi: true,
      ordering: true,
    );

    test('selectedPositionOf follows the tap sequence', () {
      final v = base.copyWith(selectedIndices: [2, 0]);
      expect(v.selectedPositionOf(2), 1);
      expect(v.selectedPositionOf(0), 2);
      expect(v.selectedPositionOf(1), isNull);
      expect(v.orderComplete, isFalse);
    });

    test('orderMatches requires the exact sequence, not the set', () {
      expect(base.copyWith(selectedIndices: [1, 0, 2]).orderMatches, isTrue);
      // Zelfde verzameling, verkeerde volgorde: fout.
      expect(base.copyWith(selectedIndices: [0, 1, 2]).orderMatches, isFalse);
      // Onvolledig: fout.
      expect(base.copyWith(selectedIndices: [1, 0]).orderMatches, isFalse);
      expect(base.copyWith(selectedIndices: [1, 0, 2]).orderComplete, isTrue);
    });

    test('ordering flag round-trips through JSON', () {
      final back = QuestionView.fromJson(base.toJson());
      expect(back.ordering, isTrue);
      expect(back.correctIndices, [1, 0, 2]);
      // En blijft standaard uit voor bestaande (oude) payloads.
      expect(QuestionView.fromJson(const {}).ordering, isFalse);
    });
  });
}
