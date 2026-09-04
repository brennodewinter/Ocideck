// De lettersneden en de opmaakregels van de PDF-export.
//
// Twee dingen die stil fout kunnen gaan en die je aan het bestand niet ziet:
// welke tekens er níet in kunnen (die verdwijnen zonder klacht uit de tekstlaag)
// en hoe een kleur uit het stijlprofiel wordt gelezen (een verkeerd gelezen
// kleur levert zwart op, en zwart ziet er nooit fout uit).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';

void main() {
  ByteData roboto() => File(
    'assets/fonts/Roboto-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  ByteData inter() => File(
    'assets/fonts/Inter-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  ByteData notoMath() => File(
    'assets/fonts/NotoSansMath-subset.ttf',
  ).readAsBytesSync().buffer.asByteData();

  group('DocumentPdfFonts', () {
    test('een schreefletter in het thema levert een schreefletter op', () {
      expect(
        DocumentPdfFonts.forFamily('EB Garamond').base.fontName,
        startsWith('Times'),
      );
      expect(
        DocumentPdfFonts.forFamily('Lora').base.fontName,
        startsWith('Times'),
      );
    });

    test('een schreefloze letter levert er ook een op', () {
      expect(
        DocumentPdfFonts.forFamily('Arial').base.fontName,
        startsWith('Helvetica'),
      );
      expect(
        DocumentPdfFonts.forFamily('Inter').base.fontName,
        startsWith('Helvetica'),
      );
    });

    test('de naam wordt zonder hoofdlettergevoeligheid gelezen', () {
      expect(
        DocumentPdfFonts.forFamily('  eb garamond ').base.fontName,
        startsWith('Times'),
      );
    });

    test('vet en cursief zijn echte sneden, geen nagebootste', () {
      // De app bundelt alleen variabele fonts, en die dragen één instantie in
      // hun omtrekken: de gewone snede. Vet zou daarmee niet vet zijn.
      final fonts = DocumentPdfFonts.forFamily('Lora');
      expect(fonts.bold.fontName, isNot(fonts.base.fontName));
      expect(fonts.italic.fontName, isNot(fonts.base.fontName));
      expect(fonts.boldItalic.fontName, isNot(fonts.bold.fontName));
    });

    test('Latin-1 komt overal doorheen, ook zonder terugvalfont', () {
      final fonts = DocumentPdfFonts.forFamily('Arial');
      expect(fonts.unsupportedRunes('Café, größer, Zürich, naïve.'), isEmpty);
    });

    test('zonder terugvalfont valt alles buiten Latin-1 op', () {
      final fonts = DocumentPdfFonts.forFamily('Arial');
      expect(fonts.unsupportedRunes('Łódź'), isNotEmpty);
    });

    test('met terugvalfont komen Pools, Grieks en Cyrillisch er wél in', () {
      // Niet aangenomen maar afgelezen: de dekking komt uit de cmap-tabel van
      // het bestand zelf.
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto()],
      );
      expect(fonts.unsupportedRunes('Łódź Ελλάδα Привет'), isEmpty);
    });

    test('wat ook het terugvalfont niet kent wordt gemeld', () {
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto()],
      );
      final missing = fonts.unsupportedRunes('日本語');
      expect(missing, isNotEmpty);
      expect(missing.map(String.fromCharCode).join(), contains('本'));
    });

    test('zonder symbolen-font is een pijl unsupported', () {
      // Roboto dekt geen pijlen (U+2190–U+21FF) — het issue dat #1968 oplost.
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto()],
      );
      expect(fonts.unsupportedRunes('Kritiek → hoog'), contains(0x2192));
    });

    test('met symbolen-font komt een pijl er wél in', () {
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto(), inter(), notoMath()],
      );
      expect(fonts.unsupportedRunes('Kritiek → hoog'), isEmpty);
    });

    test('met symbolen-font komen wiskundetekens er wél in', () {
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto(), inter(), notoMath()],
      );
      expect(fonts.unsupportedRunes('x ≤ ∞, y ≥ 0, z ≠ 1'), isEmpty);
    });

    test('de terugvallijst houdt de volgorde die de aanroeper gaf', () {
      // De volgorde is de bedoeling: `fontFallback` ketent er per teken
      // doorheen en pakt de eerste die het teken kent, en `svgTypesetting`
      // gebruikt hem om gelijk scorende sneden te scheiden.
      final fonts = DocumentPdfFonts.forFamily(
        'Arial',
        fallbackFonts: [roboto(), inter(), notoMath()],
      );
      expect(fonts.fallback, hasLength(3));
      expect(fonts.fallbackCoverages, hasLength(3));
      // Roboto kent geen pijl, Inter wel — dus de tweede dekking, niet de eerste.
      expect(fonts.fallbackCoverages[0].containsKey(0x2192), isFalse);
      expect(fonts.fallbackCoverages[1].containsKey(0x2192), isTrue);
      // En de unie is wat voor de lopende tekst telt.
      expect(fonts.fallbackCoverage.containsKey(0x2192), isTrue);
    });

    // De tekst in een ingesloten tekening gaat niet door het thema maar door de
    // SVG-lezer van `package:pdf`, en die kent alleen Latin-1 (#1942).
    group('de snede voor een ingesloten tekening', () {
      const latin = '<svg><text>Bevindingen per kwartaal</text></svg>';
      const typographic = '<svg><text>Bevindingen — per kwartaal</text></svg>';

      test('Latin-1 laat de lezer zijn eigen standaardsneden kiezen', () {
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [roboto()],
        );
        final typesetting = fonts.svgTypesetting(latin);
        expect(typesetting.settable, isTrue);
        expect(typesetting.font, isNull);
      });

      test('een gedachtestreepje vraagt om het Unicode-font', () {
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [roboto()],
        );
        final typesetting = fonts.svgTypesetting(typographic);
        expect(typesetting.settable, isTrue);
        expect(typesetting.font, same(fonts.unicode));
      });

      test('zonder Unicode-font is de tekening niet te zetten', () {
        // En dan is de bron meer waard dan een export die bij `save()` werpt.
        final fonts = DocumentPdfFonts.forFamily('Arial');
        expect(fonts.svgTypesetting(typographic).settable, isFalse);
        expect(fonts.svgTypesetting(latin).settable, isTrue);
      });

      test('een pijl kiest de snede die het hele label aankan', () {
        // Deze test toetste eerst wélk font uit de lijst gekozen werd (#1968) —
        // en dat was de verkeerde vraag. Het gekozen wiskundefont had geen
        // enkele letter en geen spatie, dus het label werd onzetbaar en de
        // export brak af (#1987). De vraag is of de gekozen snede dit label
        // kán zetten: Inter kan het, Roboto niet (geen pijl) en het
        // wiskundefont niet (geen letters).
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [roboto(), inter(), notoMath()],
        );
        final typesetting = fonts.svgTypesetting(
          '<svg><text>Kritiek → hoog</text></svg>',
        );
        expect(typesetting.settable, isTrue);
        expect(typesetting.font, same(fonts.fallback[1]));
      });

      test('een snede zonder letters wordt nooit gekozen', () {
        // Het wiskundefont begint bij U+2190: geen ASCII, geen spatie. Als
        // enige beschikbare snede kan het dus geen enkel echt label zetten, en
        // dan is de bron meer waard dan een export die werpt (#1987).
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [notoMath()],
        );
        expect(
          fonts.svgTypesetting('<svg><text>laag → hoog</text></svg>').settable,
          isFalse,
        );
      });

      test('een tekening die geen énkele snede helemaal aankan valt terug', () {
        // Ԁ (U+0500) staat alleen in Roboto, ⨁ alleen in het wiskundefont. De
        // unie dekt ze allebei — maar een tekening krijgt één snede, en geen
        // van de drie kan ze samen zetten. Dan is de bron meer waard dan een
        // export die bij `save()` werpt (#1987).
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [roboto(), inter(), notoMath()],
        );
        expect(fonts.unsupportedRunes('Ԁ ⨁'), isEmpty);
        expect(
          fonts.svgTypesetting('<svg><text>Ԁ ⨁</text></svg>').settable,
          isFalse,
        );
      });

      test('een gedachtestreepje kiest nog steeds Roboto', () {
        // Roboto dekt U+2014 — het symbolen-font is hier niet nodig.
        final fonts = DocumentPdfFonts.forFamily(
          'Arial',
          fallbackFonts: [roboto(), inter(), notoMath()],
        );
        final typesetting = fonts.svgTypesetting(typographic);
        expect(typesetting.settable, isTrue);
        expect(typesetting.font, same(fonts.unicode));
      });
    });
  });

  group('DocumentPdfStyle', () {
    test('leest de kleuren uit het stijlprofiel', () {
      final style = DocumentPdfStyle.fromTheme(
        const ThemeProfile(textColor: '#112233', accentColor: '#FF0000'),
      );
      expect(style.textColor.toHex().toUpperCase(), contains('112233'));
      expect(style.accentColor.red, closeTo(1, 0.01));
    });

    test('een onleesbare kleur valt terug in plaats van te weigeren', () {
      // Een exportpad dat struikelt over een tikfout in een kleurcode is erger
      // dan een exportpad dat de standaardkleur pakt.
      final style = DocumentPdfStyle.fromTheme(
        const ThemeProfile(textColor: 'niet-een-kleur'),
      );
      expect(style.textColor, isNotNull);
    });

    test('acht tekens: de doorzichtigheid telt niet mee', () {
      final style = DocumentPdfStyle.fromTheme(
        const ThemeProfile(textColor: '#80112233'),
      );
      expect(style.textColor.toHex().toUpperCase(), contains('112233'));
    });

    test('het koptrapje loopt af en zakt nooit onder de lopende tekst', () {
      final style = DocumentPdfStyle.fromTheme(const ThemeProfile());
      var previous = double.infinity;
      for (var level = 1; level <= 6; level++) {
        final size = style.headingSize(level);
        expect(size, lessThanOrEqualTo(previous));
        expect(size, greaterThanOrEqualTo(style.bodyFontSize));
        previous = size;
      }
    });

    test('alles schaalt mee met de gekozen tekstgrootte', () {
      final small = DocumentPdfStyle.fromTheme(
        const ThemeProfile(documentBodyFontSize: 9),
      );
      final large = DocumentPdfStyle.fromTheme(
        const ThemeProfile(documentBodyFontSize: 18),
      );
      expect(large.headingSize(1), greaterThan(small.headingSize(1)));
      expect(large.blockSpacing, greaterThan(small.blockSpacing));
      expect(large.indent, greaterThan(small.indent));
    });

    test('millimeters worden punten', () {
      // 1 duim = 25,4 mm = 72 punten.
      expect(mmToPt(25.4), closeTo(72, 0.01));
    });
  });
}
