// De heenweg [DocumentDeckBridge.documentToDeck] is de spil van het
// zero-loss-contract (DOCUMENT_MODE.md §11.3): élke niet-lege bronregel van een
// plat document hoort in een getypeerd, gescand dia-veld te belanden, zodat de
// OciWacht-projectie later niets mist. Deze tests leggen daarom vooral vast dat
// er niets stilzwijgend verdwijnt — de fout die de oude, op `_inferSlideType`
// leunende parser maakte.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_deck_bridge.dart';

void main() {
  /// Alle tekst uit alle dia-velden waar het zero-loss-contract over gaat:
  /// `customMarkdown` plus elke cel van `tableRows`.
  String allFieldText(Slide slide) =>
      '${slide.customMarkdown}\n${slide.tableRows.expand((r) => r).join('\n')}';

  group('zero-loss invariant', () {
    const doc =
        '# Titel\n'
        '\n'
        'Prosa met UNIEKPROZA.\n'
        '\n'
        '## Kop\n'
        '\n'
        'Uitleg met UNIEKUITLEG.\n'
        '\n'
        '| Naam | BSN |\n'
        '| --- | --- |\n'
        '| UNIEKCEL | 123 |\n'
        '\n'
        '```chart\n'
        'UNIEKCHART\n'
        '```\n';

    test('geen enkel token verdwijnt uit een getypeerd dia-veld', () {
      final deck = DocumentDeckBridge.documentToDeck(doc);
      final haystack = deck.slides.map(allFieldText).join('\n');
      for (final token in const [
        'Titel',
        'UNIEKPROZA',
        'Kop',
        'UNIEKUITLEG',
        'UNIEKCEL',
        '123',
        'UNIEKCHART',
      ]) {
        expect(
          haystack.contains(token),
          isTrue,
          reason: '$token mag in geen enkel dia-veld ontbreken',
        );
      }
    });

    test('de tabel wordt een table-dia met gevulde tableRows', () {
      final deck = DocumentDeckBridge.documentToDeck(doc);
      final table = deck.slides.firstWhere((s) => s.type == SlideType.table);
      // Kolomcontext behouden: de kop 'BSN' staat boven de cel '123'.
      expect(table.tableRows.first, equals(const ['Naam', 'BSN']));
      expect(table.tableRows.any((r) => r.contains('UNIEKCEL')), isTrue);
    });

    test('de chart wordt een aparte chart-dia', () {
      final deck = DocumentDeckBridge.documentToDeck(doc);
      final chart = deck.slides.firstWhere((s) => s.type == SlideType.chart);
      expect(chart.customMarkdown.trim(), equals('UNIEKCHART'));
    });
  });

  group('kop-geleide sectie', () {
    test('verdwijnt niet — het geval dat de oude parser stil dropte', () {
      final deck = DocumentDeckBridge.documentToDeck('## Kop\n\nprosa TOKEN\n');
      expect(deck.slides, hasLength(1));
      final slide = deck.slides.single;
      expect(slide.type, SlideType.freeMarkdown);
      expect(slide.customMarkdown.contains('## Kop'), isTrue);
      expect(slide.customMarkdown.contains('prosa TOKEN'), isTrue);
    });
  });

  group('dia-typering per sectie', () {
    test('een tabel-only sectie krijgt SlideType.table', () {
      final deck = DocumentDeckBridge.documentToDeck(
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n',
      );
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.type, SlideType.table);
    });

    test('een prosa-only sectie krijgt SlideType.freeMarkdown', () {
      final deck = DocumentDeckBridge.documentToDeck(
        'gewoon een alinea zonder kop\n',
      );
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.type, SlideType.freeMarkdown);
    });

    test('een niet-chart fence blijft verbatim in de prosa-flow', () {
      final deck = DocumentDeckBridge.documentToDeck(
        '```mermaid\ngraph TD; A-->B;\n```\n',
      );
      expect(deck.slides.single.type, SlideType.freeMarkdown);
      expect(deck.slides.single.customMarkdown.contains('```mermaid'), isTrue);
      expect(deck.slides.single.customMarkdown.contains('A-->B'), isTrue);
    });

    test('een leeg document geeft één lege freeMarkdown-dia', () {
      final deck = DocumentDeckBridge.documentToDeck('');
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.type, SlideType.freeMarkdown);
      expect(deck.slides.single.customMarkdown, isEmpty);
    });
  });

  group('round-trip tekst', () {
    test('kern-inhoud, tabel en chart overleven documentToDeck → markdown', () {
      const doc =
          '# Titel\n'
          '\n'
          'Prosa met UNIEKPROZA.\n'
          '\n'
          '## Kop\n'
          '\n'
          'Uitleg met UNIEKUITLEG.\n'
          '\n'
          '| Naam | BSN |\n'
          '| --- | --- |\n'
          '| UNIEKCEL | 123 |\n'
          '\n'
          '```chart\n'
          'UNIEKCHART\n'
          '```\n';
      final deck = DocumentDeckBridge.documentToDeck(doc);
      final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);

      for (final token in const [
        'Titel',
        'UNIEKPROZA',
        'Kop',
        'UNIEKUITLEG',
        'UNIEKCEL',
        'UNIEKCHART',
      ]) {
        expect(out.contains(token), isTrue, reason: '$token moet terugkomen');
      }
      // Tabel weer een GFM-tabel, chart weer een ```chart-fence.
      expect(out.contains('| Naam | BSN |'), isTrue);
      expect(out.contains('| --- | --- |'), isTrue);
      expect(out.contains('```chart'), isTrue);
      expect(out.endsWith('\n'), isTrue);
    });

    test('een cel met een pijp wordt ontsnapt en weer ontsnapt', () {
      final doc = [
        '| A | B |',
        '| --- | --- |',
        r'| x \| y | z |',
        '',
      ].join('\n');
      final deck = DocumentDeckBridge.documentToDeck(doc);
      final table = deck.slides.single;
      // De pipe zit als echte tekst in de cel na deconstructie.
      expect(table.tableRows.any((r) => r.contains('x | y')), isTrue);
      // En hij komt ontsnapt terug in de GFM-serialisatie.
      final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);
      expect(out.contains(r'x \| y'), isTrue);
    });

    test(
      'de per-kolomuitlijning overleeft de deconstructie én de round-trip',
      () {
        const doc = '| A | B | C |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |\n';
        final deck = DocumentDeckBridge.documentToDeck(doc);
        final table = deck.slides.firstWhere((s) => s.type == SlideType.table);
        // De uitlijning uit de scheidingsrij landt op de dia.
        expect(table.tableColumnAlignments, const [
          TableAlign.left,
          TableAlign.center,
          TableAlign.right,
        ]);
        // En komt byte-getrouw terug in de scheidingsrij bij serialiseren.
        final out = DocumentDeckBridge.deckToDocumentMarkdown(deck);
        expect(out.contains('| :--- | :---: | ---: |'), isTrue);
      },
    );

    test('een nog onbruikbare tijdlijn blijft atomair en bytegetrouw', () {
      const marked =
          '<!-- timeline -->\n'
          '| Tijd | Feit | Bron | Noot |\n'
          '| :--- | ---: | :---: | --- |\n'
          r'| 12:02 | x \| y |  bron  | <br> |';
      final deck = DocumentDeckBridge.documentToDeck(marked);

      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.type, SlideType.freeMarkdown);
      expect(deck.slides.single.customMarkdown, marked);
      expect(DocumentDeckBridge.deckToDocumentMarkdown(deck), '$marked\n');
    });

    test('een tijdlijn bewaart interne CRLF-regelscheidingen', () {
      const marked =
          '<!-- timeline -->\r\n'
          '| Tijd | Feit | Bron |\r\n'
          '| --- | --- | --- |\r\n'
          '| 12:02 | gemeld | loket |';
      final deck = DocumentDeckBridge.documentToDeck(marked);

      expect(deck.slides.single.customMarkdown, marked);
      expect(DocumentDeckBridge.deckToDocumentMarkdown(deck), '$marked\n');
    });
  });
}
