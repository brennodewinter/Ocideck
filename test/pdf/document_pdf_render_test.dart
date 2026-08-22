// Toetst het geléverde bestand, niet de bedoeling ervan.
//
// De blokkentest ernaast bewijst dat de omzetting de juiste beslissingen neemt.
// Deze test opent de PDF die daaruit rolt en kijkt of die beslissingen er ook in
// staan: is de tekst terug te lezen (de hele belofte van dit exportpad), staan de
// koppen in de bladwijzerboom, breekt de pagina waar hij hoort te breken, en komt
// het vel uit op het gevraagde formaat.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_renderer.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/pdf/markdown_to_pdf_blocks.dart';

import 'pdf_text_probe.dart';

void main() {
  /// Het gebundelde terugvalfont, rechtstreeks van schijf: `rootBundle` is
  /// schilwerk en deze laag is met opzet Flutter-vrij.
  ByteData fallbackFont() => File(
    'assets/fonts/Roboto-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  Future<Uint8List> render(
    String markdown, {
    ThemeProfile theme = const ThemeProfile(),
    PageSizeSpec? pageSize,
    PageMargins? pageMargins,
    bool cropMarks = false,
    bool chapterPageBreak = false,
    DocumentPdfChrome chrome = const DocumentPdfChrome(),
  }) => buildDocumentPdf(
    markdownToPdfBlocks(markdown, chapterPageBreak: chapterPageBreak),
    style: DocumentPdfStyle.fromTheme(theme),
    fonts: DocumentPdfFonts.forFamily(
      theme.fontFamily,
      fallbackFont: fallbackFont(),
    ),
    verbatimLabel: (kind) => 'bron: ${kind.name}',
    chrome: chrome,
    pageSize: pageSize,
    pageMargins: pageMargins,
    cropMarks: cropMarks,
  );

  test('levert een geldig PDF-bestand', () async {
    final bytes = await render('# Titel\n\nEen alinea.\n');
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(latin1.decode(bytes).trimRight(), endsWith('%%EOF'));
  });

  test('de tekst is terug te lezen — dit exportpad zet geen plaatjes', () async {
    // Dit ís het verschil met de PDF van een deck, die één bitmap per bladzijde
    // plakt: hier staat de tekst als tekst, dus doorzoekbaar, te kopiëren en
    // voor te lezen.
    final bytes = await render(
      '# Jaarverslag\n\n'
      'Een alinea met **nadruk** en een [verwijzing](https://librekat.nl).\n',
    );
    final text = pdfVisibleText(bytes);
    expect(text, contains('Jaarverslag'));
    expect(text, contains('Een alinea met'));
    expect(text, contains('nadruk'));
  });

  test('accenten overleven het zetten', () async {
    final text = pdfVisibleText(await render('Café, naïve, größer, Zürich.'));
    expect(text, contains('Café'));
    expect(text, contains('größer'));
  });

  test('een pagina-einde levert werkelijk een tweede blad', () async {
    final one = await render('Alleen dit.');
    final two = await render('Voor\n\n---\n\nNa');
    expect(pdfPageCount(one), 1);
    expect(pdfPageCount(two), 2);
  });

  test('de koppen staan in de bladwijzerboom', () async {
    final bytes = await render('# Hoofdstuk\n\ntekst\n\n## Deel\n\ntekst\n');
    expect(pdfOutlineTitles(bytes), containsAll(['Hoofdstuk', 'Deel']));
  });

  test('de inhoudsopgave krijgt bladzijdenummers', () async {
    // Twee opmaakrondes: de eerste rekent uit waar de koppen landen, de tweede
    // zet die nummers erin. Zonder die tweede ronde blijft de kolom leeg.
    final bytes = await render(
      '# Eerste\n\n<!-- toc -->\n\ntekst\n\n---\n\n# Tweede\n\ntekst\n',
    );
    final text = pdfVisibleText(bytes);
    expect(text, contains('Eerste'));
    expect(text, contains('Tweede'));
    // De tweede kop staat op blad twee, en dat nummer hoort in de opgave.
    expect(RegExp(r'\bTweede\b\s+2\b').hasMatch(text), isTrue, reason: text);
  });

  test('het vel komt uit op het gevraagde formaat', () async {
    // A5 staand is 148 × 210 mm; in punten (1 mm = 72/25,4) 419,5 × 595,3.
    final bytes = await render(
      'tekst',
      pageSize: const PageSizeSpec(series: PaperSeries.a, number: 5),
    );
    final box = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)',
    ).firstMatch(latin1.decode(bytes));
    expect(box, isNotNull);
    expect(double.parse(box!.group(1)!), closeTo(419.5, 1));
    expect(double.parse(box.group(2)!), closeTo(595.3, 1));
  });

  test('afloop maakt het blad rondom groter', () async {
    // Dezelfde afspraak als bij de LaTeX- en HTML-uitvoer: het vel groeit met
    // de afloop aan elke zijde, de tekstspiegel schuift evenveel op.
    final bytes = await render(
      'tekst',
      pageSize: const PageSizeSpec(series: PaperSeries.a, number: 4),
      pageMargins: const PageMargins(bleedMm: 5),
    );
    final box = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)',
    ).firstMatch(latin1.decode(bytes))!;
    // A4 is 210 mm breed; met 5 mm afloop rondom wordt dat 220 mm.
    expect(double.parse(box.group(1)!), closeTo(220 * 72 / 25.4, 1));
  });

  test('kop- en voettekst staan op elke bladzijde', () async {
    final bytes = await render(
      'Voor\n\n---\n\nNa',
      chrome: const DocumentPdfChrome(
        headerText: 'Vertrouwelijk',
        footerText: 'Stichting LibreKAT',
        showPageNumbers: true,
      ),
    );
    final text = pdfVisibleText(bytes);
    expect('Vertrouwelijk'.allMatches(text), hasLength(2));
    expect('Stichting LibreKAT'.allMatches(text), hasLength(2));
  });

  test('een tabel levert zijn cellen af', () async {
    final text = pdfVisibleText(
      await render('| Maatregel | Score |\n| --- | ---: |\n| Logging | 61 |\n'),
    );
    expect(text, contains('Maatregel'));
    expect(text, contains('Logging'));
    expect(text, contains('61'));
  });

  test('een tijdlijn levert koppen, gebeurtenissen en metadata af', () async {
    final text = pdfVisibleText(
      await render(
        '<!-- timeline -->\n'
        '| Tijd | Gebeurtenis | Bron |\n'
        '| --- | --- | --- |\n'
        '| 09:00 | Start onderzoek | Logboek |\n'
        '| 13:41 | Herstel bevestigd | Controle |\n',
      ),
    );
    expect(text, contains('Tijd'));
    expect(text, contains('GEBEURTENIS'));
    expect(text, contains('09:00'));
    expect(text, contains('Start onderzoek'));
    expect(text, contains('Bron: Logboek'));
  });

  test(
    'een smalle kolom in een tabel met proza stapelt niet verticaal',
    () async {
      // Reproduceert de RWM-zorgplichttabel: een prozakolom die op één regel
      // breder is dan het blad, met daarnaast een smalle oordeel-kolom. Onder
      // de oude `IntrinsicColumnWidth`-standaard perste de prozakolom de
      // smalle kolom samen tot één teken per regel, en kwam "Onvoldoende" als
      // "O n v o l d e n d e" in het bestand te staan — niet als één woord.
      const prose =
          'Een zin van ruim tweehonderd tekens die de prozakolom op één regel '
          'breder maakt dan de hele bladspiegel, zodat de smalle kolommen '
          'onder de oude standaard werden samengeperst tot één teken per '
          'regel en de tekst verticaal in de cel kwam te staan in plaats van '
          'horizontaal, wat de tabel onleesbaar maakte voor de lezer.';
      final text = pdfVisibleText(
        await render(
          '| Nr | Oordeel | Toelichting |\n'
          '| --- | --- | --- |\n'
          '| 1 | Onvoldoende | $prose |\n',
        ),
      );
      // Het woord staat heel in de tekstlaag, niet opgebroken per teken.
      expect(
        text,
        contains('Onvoldoende'),
        reason:
            'De smalle kolom is op haar inhoud gezet, niet samengeperst: '
            '"$text"',
      );
      // En de prozakolom is niet verdwenen — ze flext en breekt netjes af.
      expect(text, contains('onleesbaar'));
    },
  );

  test('een logo in de band staat als afbeelding in het bestand', () async {
    // Het logo mag niet op zijn natuurlijke pixelmaat (uitgerekt) neergezet
    // worden, maar het moet wél in het bestand staan. Deze rooktest bewaakt
    // de aanwezigheid; de maat volgt uit de width-driven plaatsing.
    final logo = File('assets/images/vigilis-logo.png').readAsBytesSync();
    final bytes = await render(
      'Tekst op het blad.',
      chrome: DocumentPdfChrome(
        headerText: 'Vigilis',
        logo: logo,
        logoAtTop: true,
        logoAtRight: false,
        logoWidth: 56,
      ),
    );
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    // Een ingebedde afbeelding draagt een Image-XObject.
    expect(latin1.decode(bytes), contains('/Subtype/Image'));
    expect(pdfPageCount(bytes), 1);
  });

  test(
    'een mermaid-blok komt als bron in het bestand, niet als niets',
    () async {
      final text = pdfVisibleText(await render('```mermaid\ngraph TD;\n```\n'));
      expect(text, contains('bron: mermaid'));
      expect(text, contains('graph TD;'));
    },
  );

  test('een onvindbare afbeelding laat zijn beschrijving achter', () async {
    // Een leeg gat laat de lezer denken dat er niets hoorde te staan.
    final text = pdfVisibleText(await render('![Het schema](weg.png)\n'));
    expect(text, contains('Het schema'));
  });

  test('een lang document verdeelt zich over meerdere bladzijden', () async {
    final long = List.generate(
      60,
      (i) => 'Alinea nummer $i met genoeg tekst om het blad te vullen.',
    ).join('\n\n');
    expect(pdfPageCount(await render(long)), greaterThan(1));
  });

  test(
    'een lange tijdlijn loopt door en houdt haar laatste gebeurtenis',
    () async {
      final rows = List.generate(
        45,
        (index) => '| $index:00 | Gebeurtenis $index | Bron $index |',
      ).join('\n');
      final bytes = await render(
        '<!-- timeline -->\n'
        '| Tijd | Gebeurtenis | Bron |\n'
        '| --- | --- | --- |\n'
        '$rows\n',
      );
      expect(pdfPageCount(bytes), greaterThan(1));
      expect(pdfVisibleText(bytes), contains('Gebeurtenis 44'));
    },
  );

  group('blokken die hoger zijn dan een bladzijde', () {
    // Deze groep bewaakt één ding: geen enkel blok mag de export kunnen
    // afbreken. `MultiPage` laat maar een handvol widgets over een bladovergang
    // heen lopen, en wie zo'n widget in een kader zet om er marge of een
    // achtergrond aan te geven, neemt hem dat vermogen af. Dan is een lange
    // alinea geen lelijke opmaak maar een `PdfException` en een export die niets
    // oplevert.

    test(
      'een alinea van meer dan een blad loopt door op het volgende',
      () async {
        final long = List.generate(
          220,
          (i) => 'zin nummer $i met voldoende woorden erin',
        ).join(', ');
        final bytes = await render('$long.\n');
        expect(pdfPageCount(bytes), greaterThan(1));
        expect(pdfVisibleText(bytes), contains('zin nummer 210'));
      },
    );

    test('een alinea zonder spaties breekt de export niet af', () async {
      // Niets om op af te breken: het ergste geval voor een tekstzetter.
      final bytes = await render('${'x' * 6000}\n');
      expect(pdfPageCount(bytes), greaterThan(1));
    });

    test('een codeblok van honderden regels loopt door', () async {
      final code = List.generate(300, (i) => 'regel $i;').join('\n');
      final bytes = await render('```dart\n$code\n```\n');
      expect(pdfPageCount(bytes), greaterThan(1));
      expect(pdfVisibleText(bytes), contains('regel 290;'));
    });

    test('een lange tabel loopt door en herhaalt zijn koprij', () async {
      final rows = List.generate(120, (i) => '| rij $i | $i |').join('\n');
      final bytes = await render('| Naam | Nummer |\n| --- | --- |\n$rows\n');
      expect(pdfPageCount(bytes), greaterThan(1));
      final text = pdfVisibleText(bytes);
      expect(text, contains('rij 110'));
      // De koprij hoort op elk blad opnieuw te staan, anders weet de lezer op
      // blad twee niet meer welke kolom wat is.
      expect('Naam'.allMatches(text).length, greaterThan(1));
    });

    test(
      'een tabel die meer dan twintig bladzijden beslaat slaat de export niet stuk',
      () async {
        // De standaard `maxPages: 20` uit `package:pdf` is een
        // oneindige-lus-wachter, geen documentlengtelimiet. Een tabel van
        // tweeduizend rijen loopt ver over twintig bladzijden en mag de export
        // niet afbreken met `PdfTooBigPageException`.
        final rows = List.generate(
          2000,
          (i) => '| rij $i met wat tekst | $i |',
        ).join('\n');
        final bytes = await render('| Naam | Nummer |\n| --- | --- |\n$rows\n');
        expect(pdfPageCount(bytes), greaterThan(20));
        expect(pdfVisibleText(bytes), contains('rij 1990'));
      },
    );

    test('een lange lijst loopt door', () async {
      final items = List.generate(150, (i) => '- punt $i').join('\n');
      final bytes = await render('$items\n');
      expect(pdfPageCount(bytes), greaterThan(1));
      expect(pdfVisibleText(bytes), contains('punt 140'));
    });

    test(
      'een kop bindt niet aan een blok dat te groot is om te binden',
      () async {
        // De binding houdt een kop bij zijn tekst, maar een gebonden paar kan niet
        // breken. Een lange alinea hoort daarom níet gebonden te worden.
        final long = List.generate(200, (i) => 'woord$i').join(' ');
        final bytes = await render('## Kop\n\n$long\n');
        expect(pdfVisibleText(bytes), contains('Kop'));
      },
    );
  });

  group('de opmaak die de bron voorschrijft', () {
    test('een kop staat vet', () async {
      // Geen enkel sterretje in de bron: het vet komt van de kop zelf. Stond de
      // vette snede er niet in, dan had elke span hem één laag lager weer
      // uitgezet.
      final bytes = await render('# Titel\n');
      expect(pdfBaseFonts(bytes), contains('Helvetica-Bold'));
    });

    test('de band boven het blad draagt Markdown', () async {
      final bytes = await render(
        'Tekst.\n',
        chrome: const DocumentPdfChrome(headerText: '**VERTROUWELIJK**'),
      );
      final text = pdfVisibleText(bytes);
      expect(text, contains('VERTROUWELIJK'));
      expect(text, isNot(contains('*')));
      expect(pdfBaseFonts(bytes), contains('Helvetica-Bold'));
    });

    test('een citaat krijgt hetzelfde vlak als op het scherm', () async {
      // De documentweergave zet een citaat op een tint van het accent met een
      // streep ervoor. De export tekende alleen de streep, en dan is het citaat
      // op papier iets anders dan in de editor.
      final bytes = await render(
        '> Een citaat.\n',
        theme: const ThemeProfile(accentColor: '#003399'),
      );
      // Het accent (0 / 0,2 / 0,6) op een tiende over wit papier.
      expect(
        pdfFillColors(bytes),
        contains(
          isA<List<double>>()
              .having((c) => c[0], 'rood', closeTo(0.9, 0.01))
              .having((c) => c[1], 'groen', closeTo(0.92, 0.01))
              .having((c) => c[2], 'blauw', closeTo(0.96, 0.01)),
        ),
      );
    });

    test('het logo staat één keer in het bestand', () async {
      final long = List.generate(400, (i) => 'woord$i').join(' ');
      final bytes = await render(
        '$long\n\n$long\n',
        chrome: DocumentPdfChrome(logo: _onePixelPng, logoAtTop: true),
      );
      expect(pdfPageCount(bytes), greaterThan(1));
      // Eén afbeelding, hoeveel bladzijden de band ook draagt. Hooguit twee
      // objecten: een doorzichtig plaatje draagt zijn masker apart.
      expect(pdfImageCount(bytes), lessThanOrEqualTo(2));
    });
  });
}

/// Een geldige PNG van één beeldpunt — genoeg om te toetsen hoe váák hij in het
/// bestand belandt, zonder er een bestand voor nodig te hebben.
final _onePixelPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
    'IQAAAABJRU5ErkJggg==',
  ),
);
