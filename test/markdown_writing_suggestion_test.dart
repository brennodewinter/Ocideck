import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_writing_suggestion.dart';

void main() {
  test('finds repeated words and generated placeholders', () {
    final suggestions = inspectMarkdownWriting(
      'Dit is is dubbel.\n[tekst](url)\n| Waarde | Waarde |',
    );

    expect(
      suggestions.map((suggestion) => suggestion.kind),
      containsAll([
        MarkdownWritingSuggestionKind.repeatedWord,
        MarkdownWritingSuggestionKind.placeholder,
      ]),
    );
  });

  test('does not judge examples inside fenced code', () {
    final suggestions = inspectMarkdownWriting('''
```
dit dit staat in code
[tekst](url)
```
''');

    expect(suggestions, isEmpty);
  });
}
