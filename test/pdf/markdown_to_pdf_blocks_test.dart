// Zelfcontrole voor de Markdown→PDF-omzetting. Bewijst per constructie welke
// beslissing eruit komt: koppen, lijsten, tabellen, code, inline-opmaak, links,
// voetnoten, de inhoudsopgave en het pagina-einde.
//
// Zusje van `markdown_to_latex_test.dart`, en met opzet even fijnmazig: dit is
// de laag waar een fout in de PDF ontstaat, en de enige waar een gewone test
// hem nog kan zien.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';

void main() {
  group('markdownToPdfBlocks', () {
    test('lege bron levert geen blokken', () {
      expect(markdownToPdfBlocks('   \n\n'), isEmpty);
    });

    test('koppen houden hun niveau en hun platte titel', () {
      final blocks = markdownToPdfBlocks('# Titel\n\n### Diep **vet**\n');
      final headings = blocks.whereType<PdfHeadingBlock>().toList();
      expect(headings, hasLength(2));
      expect(headings.first.level, 1);
      expect(headings.first.outlineText, 'Titel');
      expect(headings.last.level, 3);
      // De bladwijzerboom kent geen opmaak: de titel is de platte tekst.
      expect(headings.last.outlineText, 'Diep vet');
      expect(headings.last.spans.last.bold, isTrue);
    });

    test('inline-opmaak wordt platgeslagen tot losse stukken', () {
      final blocks = markdownToPdfBlocks(
        'Gewoon **vet** en *cursief* en ~~weg~~ en `code`.',
      );
      final spans = (blocks.single as PdfParagraphBlock).spans;
      expect(spans.firstWhere((s) => s.text == 'vet').bold, isTrue);
      expect(spans.firstWhere((s) => s.text == 'cursief').italic, isTrue);
      expect(spans.firstWhere((s) => s.text == 'weg').strikeThrough, isTrue);
      expect(spans.firstWhere((s) => s.text == 'code').code, isTrue);
    });

    test('geneste opmaak erft beide stijlen', () {
      final blocks = markdownToPdfBlocks('**vet *en cursief***');
      final spans = (blocks.single as PdfParagraphBlock).spans;
      final both = spans.firstWhere((s) => s.text.contains('en cursief'));
      expect(both.bold, isTrue);
      expect(both.italic, isTrue);
    });

    test('een link draagt zijn doel mee', () {
      final blocks = markdownToPdfBlocks('Zie [de site](https://librekat.nl).');
      final spans = (blocks.single as PdfParagraphBlock).spans;
      expect(
        spans.firstWhere((s) => s.text == 'de site').href,
        'https://librekat.nl',
      );
    });

    test('onveilige links blijven platte tekst', () {
      for (final href in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,evil',
        'relative/path',
      ]) {
        final blocks = markdownToPdfBlocks('[doel]($href)');
        final spans = (blocks.single as PdfParagraphBlock).spans;
        expect(spans.single.text, 'doel');
        expect(spans.single.href, isNull, reason: href);
      }
    });

    test('web-, mail- en ankerlinks blijven interactief', () {
      for (final href in [
        'https://example.test',
        'mailto:a@example.test',
        '#kop',
      ]) {
        final blocks = markdownToPdfBlocks('[doel]($href)');
        final spans = (blocks.single as PdfParagraphBlock).spans;
        expect(spans.single.href, href);
      }
    });

    test('een thematische breuk is een pagina-einde, geen streep', () {
      // DOCUMENT_MODE.md §13: in een document is `---` een nieuw blad. Dezelfde
      // afspraak als de `\newpage` van de LaTeX-export.
      final blocks = markdownToPdfBlocks('Voor\n\n---\n\nNa');
      expect(blocks[1], isA<PdfPageBreakBlock>());
    });

    test('elk hoofdstuk op een nieuw blad, behalve het eerste', () {
      final blocks = markdownToPdfBlocks(
        '# Een\n\ntekst\n\n# Twee\n\ntekst\n',
        chapterPageBreak: true,
      );
      // Geen leeg openingsblad: vóór de eerste H1 staat niets.
      expect(blocks.first, isA<PdfHeadingBlock>());
      expect(blocks.whereType<PdfPageBreakBlock>(), hasLength(1));
    });

    test('zonder de instelling breekt een hoofdstuk niets af', () {
      final blocks = markdownToPdfBlocks('# Een\n\ntekst\n\n# Twee\n');
      expect(blocks.whereType<PdfPageBreakBlock>(), isEmpty);
    });

    test('een opsomming houdt zijn punten', () {
      final blocks = markdownToPdfBlocks('- Appel\n- Peer\n');
      final list = blocks.single as PdfListBlock;
      expect(list.ordered, isFalse);
      expect(list.items, hasLength(2));
      expect(
        (list.items.first.blocks.single as PdfParagraphBlock).spans.single.text,
        'Appel',
      );
    });

    test('een genummerde lijst telt door vanaf zijn eigen begin', () {
      final list = markdownToPdfBlocks('3. Derde\n4. Vierde\n').single;
      expect((list as PdfListBlock).ordered, isTrue);
      expect(list.startNumber, 3);
    });

    test('een geneste lijst blijft in zijn punt zitten', () {
      final blocks = markdownToPdfBlocks('- Boven\n  - Onder\n');
      final outer = blocks.single as PdfListBlock;
      expect(outer.items, hasLength(1));
      expect(outer.items.single.blocks.whereType<PdfListBlock>(), hasLength(1));
    });

    test('een takenlijst draagt zijn vinkjes', () {
      final list =
          markdownToPdfBlocks('- [x] Gedaan\n- [ ] Nog niet\n').single
              as PdfListBlock;
      expect(list.items.first.checked, isTrue);
      expect(list.items.last.checked, isFalse);
      // Een gewone opsomming heeft géén vakje — anders krijgt elk punt er een.
      final plain = markdownToPdfBlocks('- Gewoon\n').single as PdfListBlock;
      expect(plain.items.single.checked, isNull);
    });

    test('een tabel houdt zijn koprij en zijn uitlijning', () {
      final table =
          markdownToPdfBlocks(
                '| Naam | Aantal | Bedrag |\n'
                '| --- | :---: | ---: |\n'
                '| Jan | 3 | 12 |\n',
              ).single
              as PdfTableBlock;
      expect(table.hasHeader, isTrue);
      expect(table.rows, hasLength(2));
      expect(table.rows.first.first.single.bold, isTrue);
      expect(table.alignments, [
        PdfColumnAlignment.left,
        PdfColumnAlignment.center,
        PdfColumnAlignment.right,
      ]);
    });

    test('een codeblok houdt zijn taal en zijn inhoud letterlijk', () {
      final code =
          markdownToPdfBlocks('```dart\nvoid main() {}\n```\n').single
              as PdfCodeBlock;
      expect(code.language, 'dart');
      expect(code.code.trim(), 'void main() {}');
    });

    test('mermaid en grafiek gaan letterlijk mee, met hun soort erbij', () {
      // Een PDF kent geen JavaScript-laag; liever de bron leesbaar dan een leeg
      // vlak. Dezelfde uitkomst als de LaTeX-export, die ze als codeblok laat
      // staan.
      final mermaid =
          markdownToPdfBlocks('```mermaid\ngraph TD;\n```\n').single
              as PdfVerbatimBlock;
      expect(mermaid.kind, PdfVerbatimKind.mermaid);
      expect(mermaid.source.trim(), 'graph TD;');

      final chart =
          markdownToPdfBlocks('```chart\n{"type":"bar"}\n```\n').single
              as PdfVerbatimBlock;
      expect(chart.kind, PdfVerbatimKind.chart);
    });

    group('display-wiskunde', () {
      test('een formule op eigen regels wordt een letterlijk blok', () {
        final block =
            markdownToPdfBlocks(
                  'Tekst.\n\n\$\$E = mc^2\$\$\n\nMeer tekst.\n',
                )[1]
                as PdfVerbatimBlock;
        expect(block.kind, PdfVerbatimKind.math);
        expect(block.source, 'E = mc^2');
      });

      test('een formule over meerdere regels blijft heel', () {
        final block =
            markdownToPdfBlocks(
                  '\$\$\n'
                  '\\int_0^1 x\\,dx = \\frac{1}{2}\n'
                  '\$\$\n',
                ).single
                as PdfVerbatimBlock;
        expect(block.kind, PdfVerbatimKind.math);
        // De backslashes staan er nog: de parser stript die vóór leestekens, en
        // juist de bron is het enige wat de PDF van een formule kan tonen.
        expect(block.source, contains(r'\int_0^1'));
        expect(block.source, contains(r'x\,dx'));
      });

      test('wiskunde middenin een regel blijft gewone tekst', () {
        // Alleen een formule die op eigen regels staat is een blok; \$…\$ in een
        // zin hoort in die zin thuis.
        final blocks = markdownToPdfBlocks('De massa is \$m\$ in de formule.');
        expect(blocks.single, isA<PdfParagraphBlock>());
      });

      test('dollartekens in een codeblok blijven code', () {
        final block =
            markdownToPdfBlocks('```sh\n\$\$ is het proces-id\n```\n').single
                as PdfCodeBlock;
        expect(block.language, 'sh');
        expect(block.code, contains(r'$$'));
      });

      test('een formule die nooit sluit wordt niet opgegeten', () {
        // Stil verdwijnen is in een export het ergste wat er kan gebeuren.
        final blocks = markdownToPdfBlocks('\$\$\nx = 1\n');
        final text = blocks
            .whereType<PdfParagraphBlock>()
            .expand((b) => b.spans)
            .map((s) => s.text)
            .join();
        expect(text, contains('x = 1'));
      });
    });

    test('de inhoudsopgave-marker wordt een eigen blok', () {
      final blocks = markdownToPdfBlocks('# Titel\n\n<!-- toc -->\n\nTekst.\n');
      expect(blocks[1], isA<PdfTocBlock>());
      // En de alinea eronder blijft een eigen alinea, zonder de marker erin.
      final paragraph = blocks[2] as PdfParagraphBlock;
      expect(paragraph.spans.single.text.trim(), 'Tekst.');
    });

    test('de marker lekt niet als tekst het document in', () {
      // Het patroon dat de marker vervangt mag de lege regel eronder niet
      // opeten: dan plakt de marker aan de volgende alinea en verschijnt hij
      // letterlijk in de uitvoer.
      final blocks = markdownToPdfBlocks('<!-- toc -->\n\nTekst.\n');
      for (final block in blocks.whereType<PdfParagraphBlock>()) {
        for (final span in block.spans) {
          expect(span.text, isNot(contains('OCIDECK')));
        }
      }
    });

    test('een document zonder koppen houdt zijn kale marker niet over', () {
      final blocks = markdownToPdfBlocks('<!-- toc -->\n');
      expect(blocks.single, isA<PdfTocBlock>());
    });

    test('voetnoten worden merktekens plus een lijst achterin', () {
      final blocks = markdownToPdfBlocks(
        'Bewering[^a] en nog een[^b].\n'
        '\n'
        '[^a]: Eerste bron.\n'
        '[^b]: Tweede bron.\n',
        footnotesTitle: 'Noten',
      );
      final paragraph = blocks.first as PdfParagraphBlock;
      final markers = paragraph.spans.where((s) => s.superscript).toList();
      expect(markers.map((s) => s.text), ['1', '2']);
      // De definities staan niet meer als losse alinea's in de stroom.
      expect(paragraph.spans.map((s) => s.text).join(), isNot(contains('[^')));

      final title = blocks.whereType<PdfHeadingBlock>().last;
      expect(title.outlineText, 'Noten');
      expect(
        (blocks.last as PdfParagraphBlock).spans.map((s) => s.text).join(),
        contains('Tweede bron.'),
      );
    });

    test('een tijdlijn wordt een gewone tabel, zonder zijn marker', () {
      final blocks = markdownToPdfBlocks(
        '<!-- timeline -->\n'
        '| Tijd | Gebeurtenis |\n'
        '| --- | --- |\n'
        '| 13:41 | Bevestigd |\n',
      );
      expect(blocks.whereType<PdfTableBlock>(), hasLength(1));
      // Het HTML-commentaar mag niet als alinea in de PDF landen.
      for (final block in blocks.whereType<PdfParagraphBlock>()) {
        expect(
          block.spans.map((s) => s.text).join(),
          isNot(contains('timeline')),
        );
      }
    });

    test('een citaat houdt zijn blokken', () {
      final quote =
          markdownToPdfBlocks('> Eerste regel\n>\n> Tweede alinea\n').single
              as PdfQuoteBlock;
      expect(quote.blocks.whereType<PdfParagraphBlock>(), hasLength(2));
    });

    test('een alinea met alleen een afbeelding wordt een eigen blok', () {
      final image =
          markdownToPdfBlocks('![Een grafiek](plaatje.png)\n').single
              as PdfImageBlock;
      expect(image.source, 'plaatje.png');
      expect(image.alt, 'Een grafiek');
    });

    test('een afbeelding midden in een regel houdt zijn beschrijving', () {
      // Een PDF-alinea kan geen plaatje dragen; de beschrijving houdt de
      // betekenis vast in plaats van hem te laten vallen.
      final blocks = markdownToPdfBlocks('Zie ![het schema](s.png) hierboven.');
      final spans = (blocks.single as PdfParagraphBlock).spans;
      expect(spans.map((s) => s.text).join(), contains('het schema'));
    });
  });
}
