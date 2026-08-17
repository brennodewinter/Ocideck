import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

/// Een opsommingsregel die in de bron over twee regels is afgebroken hoort één
/// item te blijven. Hij werd een losse alinea: zonder bolletje, op de
/// linkermarge, met de lijst in tweeën — en dat verschoof ook nog de gemeten
/// blokhoogte waar de pagina-einden op rekenen.
void main() {
  test('een afgebroken regel blijft bij zijn eigen item', () {
    const markdown = '''
- Eerste punt
- Tweede punt, dat in de bron is afgebroken en
  op de volgende regel doorloopt
- Derde punt
''';
    final blocks = DocumentMarkdownView.blockTexts(markdown);
    expect(
      blocks,
      hasLength(1),
      reason: 'dit is één lijst, geen lijst plus alinea',
    );
    expect(blocks.single, contains('afgebroken en op de volgende regel'));
  });

  test('een lege regel sluit de lijst wel af', () {
    const markdown = '''
- Eerste punt
- Tweede punt

Een gewone alinea eronder.
''';
    final blocks = DocumentMarkdownView.blockTexts(markdown);
    expect(blocks, hasLength(2));
    expect(blocks.last, 'Een gewone alinea eronder.');
  });

  test('een kop na een lijst blijft een kop', () {
    const markdown = '''
- Eerste punt
## Een kop
''';
    final blocks = DocumentMarkdownView.blockTexts(markdown);
    expect(blocks, hasLength(2));
    expect(blocks.last, 'Een kop');
  });

  test('een tabel na een lijst wordt niet opgeslokt', () {
    const markdown = '''
- Eerste punt
| A | B |
|---|---|
| 1 | 2 |
''';
    final blocks = DocumentMarkdownView.blockTexts(markdown);
    expect(blocks, hasLength(2));
    expect(blocks.last, contains('A'));
  });

  testWidgets('de doorlopende regel krijgt geen eigen alinea in beeld', (
    tester,
  ) async {
    const markdown = '''
- Eerste punt
- Tweede punt, dat in de bron is afgebroken en
  op de volgende regel doorloopt
''';
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 900, child: DocumentMarkdownView(markdown)),
        ),
      ),
    );

    // Twee bolletjes voor twee items — niet twee bolletjes plus een zwevende
    // regel ernaast.
    expect(find.text('•'), findsNWidgets(2));
  });
}
