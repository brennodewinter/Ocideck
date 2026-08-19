import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:ocideck/services/document_timeline.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/timeline_table_embed_syntax.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

void main() {
  const table = '''| Tijd | Gebeurtenis | Status |
| :--- | --- | ---: |
| 13:41 | Herstelclaim weerlegd | Vastgesteld |
|  12:02  | Eerste melding \\| servicedesk | Gemeld |''';
  const marked = '$documentTimelineMarker\n$table';

  test('analyse accepteert twee of drie kolommen en bewaart lege rijen', () {
    final three = analyzeMarkedTimeline(marked);
    expect(three.isUsable, isTrue);
    expect(three.timeline!.headers, ['Tijd', 'Gebeurtenis', 'Status']);
    expect(three.timeline!.events, hasLength(2));

    final two = analyzeTimelineTable('''| Wanneer | Wat |
| --- | --- |
| 10:00 | |
| | Tweede |''');
    expect(two.isUsable, isTrue);
    expect(two.timeline!.events, hasLength(2));
  });

  test('ongeschikte tabel verandert niet en de marker is omkeerbaar', () {
    const four = '''| A | B | C | D |
| --- | --- | --- | --- |
| 1 | 2 | 3 | 4 |''';
    expect(
      analyzeTimelineTable(four).issue,
      TimelineTableIssue.wrongColumnCount,
    );
    expect(unmarkTimeline(markTableAsTimeline(table)), table);
  });

  test('Quill bewaart marker plus raw tabel als één embed', () {
    final document = MarkdownQuillCodec.documentFromMarkdown(marked);
    final embeds = document
        .toDelta()
        .toList()
        .where((operation) => operation.data is Map)
        .map((operation) => (operation.data as Map).keys.single)
        .toList();
    expect(embeds, [EmbeddableTimelineTable.timelineType]);
    expect(MarkdownQuillCodec.markdownFromDocument(document), marked);
  });

  test('document-deck-document houdt marker direct tegen raw tabel', () {
    final deck = DocumentDeckBridge.documentToDeck(marked);
    final restored = DocumentDeckBridge.deckToDocumentMarkdown(
      deck,
    ).trimRight();
    expect(restored, marked);
  });

  testWidgets('de documentweergave toont alle gebeurtenissen als kaarten', (
    tester,
  ) async {
    final rows = List.generate(
      19,
      (index) =>
          '| ${index.toString().padLeft(2, '0')}:00 | Feit $index | Bron $index |',
    ).join('\n');
    final source = '''$documentTimelineMarker
| Tijd | Gebeurtenis | Bron |
| --- | --- | --- |
$rows''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SizedBox())),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DocumentMarkdownView(source)),
        ),
      ),
    );
    await tester.pump();

    for (var index = 0; index < 19; index++) {
      expect(find.text('Feit $index'), findsOneWidget);
      expect(
        DocumentMarkdownView.blockTexts(source)[index],
        contains('Bron $index'),
      );
    }
    expect(DocumentMarkdownView.blockTexts(source), hasLength(19));
  });

  testWidgets('tijdlijn blijft leesbaar en in bronvolgorde bij 200% tekst', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const source = '''$documentTimelineMarker
| Tijd | Gebeurtenis | Bron |
| --- | --- | --- |
| 08:00 | Eerste melding met extra tekst die op tweehonderd procent moet omlopen | Servicedesk |
| 08:30 | Onderzoek gestart met behoud van de volledige leesvolgorde | SOC |
| onbekend | Hersteld en gecontroleerd door een derde bron | Beheer |''';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: DocumentMarkdownView(source)),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final events = [
      'Eerste melding met extra tekst die op tweehonderd procent moet omlopen',
      'Onderzoek gestart met behoud van de volledige leesvolgorde',
      'Hersteld en gecontroleerd door een derde bron',
    ];
    for (final event in events) {
      expect(find.semantics.byLabel(event), findsOneWidget);
    }
    expect(
      events.map((event) => tester.getTopLeft(find.text(event)).dy),
      orderedEquals(
        events.map((event) => tester.getTopLeft(find.text(event)).dy).toList()
          ..sort(),
      ),
    );
    semantics.dispose();
  });
}
