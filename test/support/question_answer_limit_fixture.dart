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
