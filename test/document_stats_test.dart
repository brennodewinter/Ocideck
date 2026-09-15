import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/document_stats.dart';

void main() {
  test('empty document has zero stats', () {
    final stats = computeDocumentStats('');
    expect(stats.words, 0);
    expect(stats.chapters, 0);
    expect(stats.sections, 0);
    expect(stats.tables, 0);
    expect(stats.images, 0);
  });

  test('counts words in plain text', () {
    final stats = computeDocumentStats('Dit is een test met zeven woorden.');
    expect(stats.words, 7);
  });

  test('counts H1 as chapters and H2+ as sections', () {
    final stats = computeDocumentStats('''
# Hoofdstuk 1
## Paragraaf 1.1
### Subparagraaf
## Paragraaf 1.2
# Hoofdstuk 2
''');
    expect(stats.chapters, 2);
    expect(stats.sections, 3);
  });

  test('does not count headings inside fenced code', () {
    final stats = computeDocumentStats('''
# Echt hoofdstuk
```
# Geen hoofdstuk
## Ook geen paragraaf
```
## Echt paragraaf
''');
    expect(stats.chapters, 1);
    expect(stats.sections, 1);
  });

  test('does not count words inside fenced code', () {
    final stats = computeDocumentStats('''
Twee woorden hier
```python
print("geen woorden tellen mee")
```
''');
    expect(stats.words, 3);
  });

  test('counts GFM table blocks', () {
    final stats = computeDocumentStats('''
| Naam | Waarde |
| --- | --- |
| A | 1 |
| B | 2 |

Tussen tekst

| Col1 | Col2 |
| --- | --- |
| X | Y |
''');
    expect(stats.tables, 2);
  });

  test('does not count a pipe line without a delimiter as a table', () {
    final stats = computeDocumentStats(
      '| geen scheidingsrij eronder\n| dus geen tabel',
    );
    expect(stats.tables, 0);
  });

  test('counts image references but not bg images', () {
    final stats = computeDocumentStats('''
![foto](images/pic.png)
![bg](images/background.jpg)
![diagram](charts/flow.svg)
''');
    expect(stats.images, 2);
  });

  test('image paths do not count as words', () {
    final stats = computeDocumentStats('![alt](path/to/image.png)');
    expect(stats.words, 0);
  });

  test('markdown markup does not inflate word count', () {
    final stats = computeDocumentStats('**vet** _schuin_ `code`');
    // "vet", "schuin", "code" — drie woorden, de markdown-tekenreeksen niet.
    expect(stats.words, 3);
  });
}
