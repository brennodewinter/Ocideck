import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_links.dart';
import 'package:ocideck/services/pdf/document_pdf_renderer.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';

import 'pdf_text_probe.dart';

Future<Uint8List> _render(String markdown) => buildDocumentPdf(
  markdownToPdfBlocks(markdown),
  style: DocumentPdfStyle.fromTheme(const ThemeProfile()),
  fonts: DocumentPdfFonts.forFamily(''),
  verbatimLabel: (kind) => kind.name,
);

List<String> _pages(Uint8List bytes) {
  final pages = pdfVisibleTextPerPage(
    bytes,
  ).where((p) => p.trim().isNotEmpty).toList();
  expect(pdfPageCount(bytes), pages.length, reason: 'Geen extra lege pagina');
  return pages;
}

void main() {
  test('fragmentnamen volgen Markdown inclusief accenten en duplicaten', () {
    final names = pdfHeadingLinks(['Eén beeld!', 'Eén beeld!', 'En beeld-1']);
    expect(names['en-beeld'], 'ocideck-kop-0');
    expect(names['en-beeld-1'], 'ocideck-kop-1');
    expect(names['en-beeld-1-1'], 'ocideck-kop-2');
    expect(pdfFragmentDestination('#en%2Dbeeld', names), 'ocideck-kop-0');
    expect(pdfFragmentDestination('#%QQ', names), isNull);
    expect(pdfFragmentDestination('#onbekend', names), isNull);
  });

  test(
    'gewone fragmentlinks worden PDF-links en behouden externe links',
    () async {
      final raw = latin1.decode(
        await _render(
          '[lees verder](#eerste) [tweede](#eerste-1) '
          '[onbekend](#onbekend) [website](https://librekat.nl)\n\n'
          '## Eerste\n\nEen\n\n## Eerste\n\nTwee',
        ),
      );
      expect(raw, contains('/D(ocideck-kop-0)'));
      expect(raw, contains('/D(ocideck-kop-1)'));
      expect(raw, isNot(contains('/URI(#')));
      expect(raw, contains('https://librekat.nl'));
      expect(raw, isNot(contains('/D(onbekend)')));
    },
  );

  test(
    'structurele inhoudsopgave staat alleen en links blijven intact',
    () async {
      final bytes = await _render(
        '# Titel\n\nVoorwoord.\n\n## Wegwijzer\n\n'
        '- [Eerste](#eerste)\n- [Tweede](#tweede)\n\n'
        '## Eerste\n\nBegin.\n\n## Tweede\n\nEinde.',
      );
      final pages = _pages(bytes);
      expect(pages, hasLength(3));
      expect(pages[0], contains('Voorwoord'));
      expect(pages[0], isNot(contains('Wegwijzer')));
      expect(pages[1], contains('Wegwijzer'));
      expect(pages[1], isNot(contains('Begin.')));
      expect(pages[2], contains('Begin.'));
      final raw = latin1.decode(bytes);
      expect(raw, contains('/D(ocideck-kop-2)'));
      expect(raw, contains('/D(ocideck-kop-3)'));
    },
  );

  test(
    'alleen de titel Inhoud maakt een gewone sectie geen inhoudsopgave',
    () async {
      final pages = _pages(
        await _render(
          'Voorwoord.\n\n## Inhoud\n\n- Gewone tekst\n- Nog een punt\n\nVerder.',
        ),
      );
      expect(pages, hasLength(1));
    },
  );

  test('terugverwijzingen en gemengde lijsten zijn geen inhoudsopgave', () {
    for (final list in [
      '- [Een](#een)\n- [Twee](#twee)',
      '- [Een](#een)\n- [Extern](https://librekat.nl)',
    ]) {
      final blocks = markdownToPdfBlocks(
        '## Een\n\n## Twee\n\n## Verder\n\n$list',
      );
      expect(blocks.whereType<PdfPageBreakBlock>(), isEmpty);
    }
  });

  test(
    'gegenereerde inhoudsopgave krijgt eigen pagina en correcte nummers',
    () async {
      final bytes = await _render(
        '# Titel\n\nVoorwoord.\n\n<!-- toc -->\n\n## Hoofdstuk\n\nBegin.',
      );
      final pages = _pages(bytes);
      expect(pages, hasLength(3));
      expect(pages[1], contains('Hoofdstuk 3'));
      expect(pages[2], contains('Begin.'));
    },
  );

  test(
    'inhoudsopgave aan begin of tussen pagina-einden maakt geen lege pagina',
    () async {
      final pages = _pages(
        await _render('<!-- toc -->\n\n---\n\n## Een\n\nTekst.'),
      );
      expect(pages, hasLength(2));
      expect(pages.every((p) => p.trim().isNotEmpty), isTrue);
      final blocks = markdownToPdfBlocks(
        'Voorwoord\n\n---\n\n## Inhoud\n\n<!-- toc -->\n\n---\n\n## Een\n\nTekst',
      );
      for (var i = 1; i < blocks.length; i++) {
        expect(
          blocks[i] is PdfPageBreakBlock && blocks[i - 1] is PdfPageBreakBlock,
          isFalse,
        );
      }
    },
  );

  test('lange inhoudsopgave mag meerdere paginas beslaan', () async {
    final source =
        '<!-- toc -->\n\n${List.generate(90, (i) => '## Hoofdstuk $i\n\nTekst $i.').join('\n\n')}';
    final pages = _pages(await _render(source));
    expect(pages.length, greaterThan(3));
    final firstBodyPage = pages.indexWhere((p) => p.contains('Tekst 0.'));
    expect(firstBodyPage, greaterThan(1));
    expect(pages.take(firstBodyPage).join(' '), contains('Hoofdstuk 89'));
  });
  test('lege inhoudsopgave voegt geen lege pagina toe', () async {
    final pages = _pages(
      await _render('Voorwoord.\n\n<!-- toc -->\n\nVerder.'),
    );
    expect(pages, hasLength(1));
    expect(pages.single, contains('Voorwoord.'));
    expect(pages.single, contains('Verder.'));
  });
}
