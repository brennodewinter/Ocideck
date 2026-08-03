import 'dart:convert';

/// A question block with a deliberately oversized answer pool.
///
/// Generated instead of committed as a 10,000-line JSON file: callers still
/// exercise the real parser with every record, while the repository does not
/// carry a large opaque fixture.
String questionBlockWithAnswers(int count) =>
    const JsonEncoder.withIndent('  ').convert({
      'kind': 'multipleCorrect',
      'prompt': 'Welke antwoorden horen erbij?',
      'optionCount': 8,
      'answers': [
        for (var i = 0; i < count; i++)
          {'text': 'Antwoord $i', 'correct': i.isEven},
      ],
    });

const multipleChoiceNonBeers = [
  'Karnemelk',
  'Appelsap',
  'Koffie',
  'Thee',
  'Water',
];

/// A realistic multiple-choice bank: five non-beers and many plausible beers.
///
/// The generated tail lets boundary and resource-limit tests reuse the same
/// user-facing example without committing a large opaque fixture.
String multipleChoiceBeerQuestionBlock(int count, {int optionCount = 4}) =>
    const JsonEncoder.withIndent('  ').convert({
      'kind': 'multipleChoice',
      'prompt': 'Wat is geen bier?',
      'optionCount': optionCount,
      'answers': [
        for (var i = 0; i < count; i++)
          {
            'text': i < multipleChoiceNonBeers.length
                ? multipleChoiceNonBeers[i]
                : 'Bier ${i - multipleChoiceNonBeers.length + 1}',
            'correct': i < multipleChoiceNonBeers.length,
          },
      ],
    });
