import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/markdown_validator.dart';

void main() {
  final service = MarkdownService();
  final validator = MarkdownValidator();

  test('valid generated deck has no errors', () {
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Kop',
            bullets: ['Eerste punt'],
          ),
        ],
      ),
    );

    final result = validator.validate(markdown);
    expect(result.isValid, isTrue);
    expect(result.hasIssues, isFalse);
  });

  test('detects unclosed front matter', () {
    const markdown = '---\nmarp: true\ntheme: ocideck\n# Titel\n';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('Front matter is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects unclosed code fence', () {
    const markdown = '''
---
marp: true
---

# Code

```dart
void main() {}
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('Codeblok is niet afgesloten'),
      ),
      isTrue,
    );
  });

  test('detects code slide without fenced block', () {
    const markdown = '''
---
marp: true
---

<!-- _class: code -->

# Titel
print('hi');
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('broncode-slide vereist'),
      ),
      isTrue,
    );
  });

  test('detects invalid chart JSON', () {
    const markdown = '''
---
marp: true
---

<!-- _class: chart -->

```chart
{ broken json
```
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('grafiek-JSON is ongeldig'),
      ),
      isTrue,
    );
  });

  test('detects split slide with missing divs', () {
    const markdown = '''
---
marp: true
---

<!-- _class: split -->

<div class="split-text">

# Kop

</div>
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('split-image'),
      ),
      isTrue,
    );
  });

  test('detects invalid two-bullets encoded comment', () {
    const markdown = '''
---
marp: true
---

<!-- _class: two-bullets -->
<!-- ocideck_two_bullets_left: !!! -->
<div class="ocideck-two-bullets">
<div></div>
<div></div>
</div>
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('ocideck_two_bullets_left:'),
      ),
      isTrue,
    );
  });

  test('detects table without separator row', () {
    const markdown = '''
---
marp: true
---

<!-- _class: table -->

| Kop 1 | Kop 2 |
| a | b |
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('scheidingsrij'),
      ),
      isTrue,
    );
  });

  test('detects malformed image markdown', () {
    const markdown = '''
---
marp: true
---

![bg 50%](images/foto.png
''';

    final result = validator.validate(markdown);
    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.message.contains('afbeeldings-markdown'),
      ),
      isTrue,
    );
  });

  test('accepts valid encoded two-bullets payload', () {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(['A', 'B'])));
    final markdown = '''
---
marp: true
---

<!-- _class: two-bullets -->
<!-- ocideck_two_bullets_left: $encoded -->
<div class="ocideck-two-bullets">
<div></div>
<div></div>
</div>
''';

    final result = validator.validate(markdown);
    expect(
      result.issues.where(
        (issue) => issue.message.contains('ocideck_two_bullets_left:'),
      ),
      isEmpty,
    );
  });
}
