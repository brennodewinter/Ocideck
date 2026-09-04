// De letters van de PDF-export.
//
// **Waarom niet het lettertype van het stijlprofiel?** Omdat de LaTeX-export dat
// ook niet doet: die zet geen enkel font in de preamble en laat de compiler zijn
// eigen letter kiezen. Een tekstlaag-export draagt de *structuur* en de
// *paginaopmaak* van het document, niet de typografie van dít scherm — dat is
// dezelfde grens als bij `theme:`, dat wél wordt opgelost maar niet als naam
// meereist (FILE_FORMAT.md §14.5).
//
// **Waarom de standaardfonts van PDF?** De app bundelt alleen *variabele*
// fonts, en die dragen precies één instantie in hun omtrekken: de gewone
// snede. Wie daarmee vet zet, zet niets vet — er ís geen vette omtrek in het
// bestand. De veertien standaardfonts die elke PDF-lezer zelf heeft (Times,
// Helvetica, Courier) dragen wél een echte vette en cursieve snede, kosten geen
// enkele byte in het bestand, en zijn in elke lezer identiek.
//
// **En de rest van Unicode dan?** Die standaardfonts reiken tot Latin-1. Alles
// daarbuiten — Pools, Grieks, Cyrillisch — valt terug op een gebundeld font dat
// de aanroeper meegeeft. [DocumentPdfFonts.unsupportedRunes] zegt eerlijk welke
// tekens ook dáár niet in staan, zodat de export kan waarschuwen in plaats van
// ze stil te laten verdwijnen.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// De lettersneden waarmee de PDF wordt gezet.
class DocumentPdfFonts {
  DocumentPdfFonts({
    required this.base,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.mono,
    this.fallback = const [],
    this.fallbackCoverages = const [],
  }) : fallbackCoverage = {
         for (final coverage in fallbackCoverages) ...coverage,
       };

  final pw.Font base;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final pw.Font mono;

  /// De fonts waar een teken op terugvalt dat de standaardsnede niet kent.
  final List<pw.Font> fallback;

  /// Wat élk terugvalfont dekt, in dezelfde volgorde als [fallback].
  /// Rechtstreeks uit de `cmap`-tabel van het TTF-bestand: geen aanname over
  /// welke schriften erin zitten, maar de tabel zelf.
  ///
  /// Per font en niet als één hoop, want de twee vragen die deze klasse
  /// beantwoordt hebben een ander antwoord nodig. Voor de lopende tekst telt de
  /// unie — `fontFallback` ketent per teken en pakt het eerste font dat het
  /// kent. Voor een ingesloten tekening telt één font tegelijk, want de
  /// SVG-lezer ketent niet. Zie [svgTypesetting].
  final List<Map<int, int>> fallbackCoverages;

  /// Wat de terugvalfonts sámen dekken — de vraag die voor de lopende tekst
  /// telt.
  final Map<int, int> fallbackCoverage;

  /// Bouwt de sneden voor een document met een *schreefloze* of *schreef*-letter,
  /// afgeleid van [fontFamily] van het stijlprofiel.
  ///
  /// De exacte letter reist niet mee (zie de kop van dit bestand), maar het
  /// *karakter* wel: wie zijn document in EB Garamond of Lora schrijft, krijgt
  /// een PDF met schreef; wie Arial of Inter koos, krijgt er een zonder. Dat
  /// kost niets en scheelt de lezer een document dat niet lijkt op wat hij zag.
  ///
  /// [fallbackFonts] zijn de bytes van Unicode-rijke TTF-bestanden, in de
  /// volgorde waarin ze geprobeerd worden. Voor de lopende tekst ketent
  /// `fontFallback` er per teken doorheen; voor een ingesloten tekening kiest
  /// [svgTypesetting] er één uit. Is de lijst leeg, dan blijft de export bij
  /// Latin-1 — [unsupportedRunes] meldt dan navenant meer.
  factory DocumentPdfFonts.forFamily(
    String fontFamily, {
    List<ByteData> fallbackFonts = const [],
  }) {
    final serif = _serifFamilies.contains(fontFamily.toLowerCase().trim());
    return DocumentPdfFonts(
      base: serif ? pw.Font.times() : pw.Font.helvetica(),
      bold: serif ? pw.Font.timesBold() : pw.Font.helveticaBold(),
      italic: serif ? pw.Font.timesItalic() : pw.Font.helveticaOblique(),
      boldItalic: serif
          ? pw.Font.timesBoldItalic()
          : pw.Font.helveticaBoldOblique(),
      mono: pw.Font.courier(),
      fallback: [for (final bytes in fallbackFonts) pw.Font.ttf(bytes)],
      fallbackCoverages: [
        for (final bytes in fallbackFonts) TtfParser(bytes).charToGlyphIndexMap,
      ],
    );
  }

  /// De families die de app als schreefletter aanbiedt. Kleingeschreven, want
  /// de vergelijking is dat ook.
  static const _serifFamilies = {
    'eb garamond',
    'lora',
    'georgia',
    'times',
    'times new roman',
    'serif',
  };

  /// Het thema dat elke tekst in het document erft.
  pw.ThemeData themeData({required double fontSize, required PdfColor color}) =>
      pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
        fontFallback: fallback,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(
          font: base,
          fontBold: bold,
          fontItalic: italic,
          fontBoldItalic: boldItalic,
          fontFallback: fallback,
          fontSize: fontSize,
          color: color,
          lineSpacing: fontSize * 0.35,
        ),
      );

  /// Hoe de tekst in een *ingesloten tekening* gezet moet worden.
  ///
  /// Waarom een tekening een eigen antwoord krijgt: `pw.SvgImage` gaat niet
  /// door het thema hierboven maar door de SVG-lezer van `package:pdf`. Die
  /// kiest voor elke `<text>` hardgecodeerd een van de veertien standaardsneden
  /// (`src/svg/painter.dart`) — zonder terugvallijst. Die sneden reiken tot
  /// Latin-1, en `stringMetrics` *werpt* op alles daarboven, vanuit
  /// `SvgImage.paint`. Dat is tijdens `document.save()`, dus buiten elke `try`
  /// rond de tekening zelf: één gedachtestreepje in een grafiektitel kostte zo
  /// het hele document (#1942).
  ///
  /// **De gekozen snede moet de tekening hélemaal kunnen zetten, of hij wordt
  /// niet getekend.** Dat lijkt streng — waarom niet de snede die het meeste
  /// dekt, en de rest een leeg blokje? Omdat een ontbrekende glyph in
  /// `TtfWriter.withChars` niet betrouwbaar een blokje wordt. Nagemeten met
  /// Roboto:
  ///
  /// | tekst | uitkomst |
  /// |---|---|
  /// | `laag ⨁ ∮ hoog` | blokjes |
  /// | `a ⨁ ∮` | **worp** |
  /// | `Ԁ ∮` | blokje |
  /// | `Ԁ ⨁ ∮` | **worp** |
  ///
  /// Of het een blokje wordt of een uitzondering hangt af van hoeveel glyphs de
  /// subset verderop nog over heeft — een grens die niet na te bouwen is en die
  /// bij de volgende versie van de bibliotheek anders kan liggen. Een regel die
  /// op zo'n grens balanceert is geen regel. Alles-of-de-bron is wél te
  /// beredeneren, en het is dezelfde afweging die er voor een onleesbare SVG al
  /// stond: de bron tonen is vervelend, de export verliezen is erger (#1987).
  ///
  /// Er wordt naar de héle SVG gekeken en niet alleen naar de tekstknopen. Dat
  /// is met opzet ruimer dan nodig: een scan die één plek mist waar tekst kan
  /// staan (een `<text>` in een `<symbol>` die via `<use>` wordt aangeroepen,
  /// bijvoorbeeld) zet de afbreker terug. De prijs is dat een tekening die een
  /// bijzonder teken alleen buiten haar tekst draagt strenger beoordeeld wordt
  /// dan nodig — en dan haar bron toont, wat leesbaar blijft.
  ///
  /// De volgorde van [fallback] is de voorkeur: de eerste snede die alles kan
  /// zetten wint. Zo houdt een tekening zonder bijzondere tekens de letter die
  /// de rest van het document ook heeft.
  SvgTypesetting svgTypesetting(String svg) {
    final runes = svg.runes.toSet();
    if (!runes.any((rune) => rune > 0xFF)) {
      return const SvgTypesetting.standard();
    }
    for (var index = 0; index < fallback.length; index++) {
      final coverage = index < fallbackCoverages.length
          ? fallbackCoverages[index]
          : const <int, int>{};
      if (runes.every(coverage.containsKey)) {
        return SvgTypesetting.withFont(fallback[index]);
      }
    }
    return const SvgTypesetting.unsettable();
  }

  /// Het gebundelde Unicode-rijke font, of `null` als de aanroeper er geen gaf.
  pw.Font? get unicode => fallback.isEmpty ? null : fallback.first;

  /// De tekens in [text] die geen enkele beschikbare snede kan zetten.
  ///
  /// Waarom dit bestaat: een teken dat nergens in staat verdwijnt in een PDF
  /// niet met een foutmelding maar met een leeg blokje — en uit de tekstlaag
  /// verdwijnt het zelfs helemaal, dus ook uit zoeken, kopiëren en de
  /// voorleessoftware. Een export die inhoud kwijtraakt zonder iets te zeggen is
  /// het ergste wat een export kan doen; deze lijst is wat de schil nodig heeft
  /// om het wél te zeggen.
  Set<int> unsupportedRunes(String text) {
    final missing = <int>{};
    for (final rune in text.runes) {
      if (_isCovered(rune)) continue;
      missing.add(rune);
    }
    return missing;
  }

  bool _isCovered(int rune) {
    // De standaardsneden zetten Latin-1; regelovergangen en tabs zijn geen
    // letters maar horen hier evengoed niet in de klaagzang thuis.
    if (rune < 0x100) return true;
    return fallbackCoverage.containsKey(rune);
  }
}

/// Waarmee de tekst in één ingesloten tekening gezet wordt.
///
/// Drie uitkomsten, en ze vragen alle drie iets anders van de aanroeper: laat
/// de lezer zelf kiezen, geef hem deze snede mee, of teken de tekening niet.
/// Zie [DocumentPdfFonts.svgTypesetting] voor waarom de derde bestaat.
class SvgTypesetting {
  /// De standaardsneden volstaan; de lezer kiest zelf.
  const SvgTypesetting.standard() : font = null, settable = true;

  /// Deze snede moet het doen, want de standaardsneden kunnen het niet — en
  /// deze kan de tekening helemaal zetten.
  const SvgTypesetting.withFont(pw.Font this.font) : settable = true;

  /// Geen enkele beschikbare snede kan deze tekening zetten.
  const SvgTypesetting.unsettable() : font = null, settable = false;

  /// De snede die aan `customFontLookup` meegegeven moet worden, of `null` als
  /// de lezer zijn eigen keuze mag houden.
  final pw.Font? font;

  /// Of de tekening getekend kan worden. Is dit `false`, dan hoort de aanroeper
  /// terug te vallen op de bron: `pw.SvgImage` zou pas bij `save()` werpen, en
  /// dan is het hele document weg.
  final bool settable;
}
