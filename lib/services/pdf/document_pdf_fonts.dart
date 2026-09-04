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
    this.fallbackCoverage = const {},
    this.primaryCoverage = const {},
  });

  final pw.Font base;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final pw.Font mono;

  /// De fonts waar een teken op terugvalt dat de standaardsnede niet kent.
  final List<pw.Font> fallback;

  /// Welke tekens die terugvalfonts dekken. Rechtstreeks uit de `cmap`-tabel
  /// van het TTF-bestand: geen aanname over welke schriften erin zitten, maar
  /// de tabel zelf.
  final Map<int, int> fallbackCoverage;

  /// De dekking van alleen het primaire terugvalfont (Roboto). [svgTypesetting]
  /// gebruikt dit om te beslissen of het symbolen-font nodig is — de SVG-lezer
  /// kiest één font, en als het primaire font een teken niet kent, is het
  /// symbolen-font de enige hoop (#1968).
  final Map<int, int> primaryCoverage;

  /// Bouwt de sneden voor een document met een *schreefloze* of *schreef*-letter,
  /// afgeleid van [fontFamily] van het stijlprofiel.
  ///
  /// De exacte letter reist niet mee (zie de kop van dit bestand), maar het
  /// *karakter* wel: wie zijn document in EB Garamond of Lora schrijft, krijgt
  /// een PDF met schreef; wie Arial of Inter koos, krijgt er een zonder. Dat
  /// kost niets en scheelt de lezer een document dat niet lijkt op wat hij zag.
  ///
  /// [fallbackFont] zijn de bytes van een Unicode-rijk TTF-bestand (in OciDeck
  /// het gebundelde Roboto). Ontbreekt het, dan blijft de export bij Latin-1 —
  /// [unsupportedRunes] meldt dan navenant meer.
  ///
  /// [symbolFont] is een aanvullend terugvalfont voor tekens die [fallbackFont]
  /// niet dekt — pijlen (U+2192), wiskundige operatoren (U+2264), en meer. De
  /// `fallback`-lijst is al een lijst, dus dit font komt erachter te staan en
  /// de `pdf`-bibliotheek probeert ze in volgorde (#1968).
  factory DocumentPdfFonts.forFamily(
    String fontFamily, {
    ByteData? fallbackFont,
    ByteData? symbolFont,
  }) {
    final serif = _serifFamilies.contains(fontFamily.toLowerCase().trim());
    final fallbacks = <pw.Font>[];
    var coverage = const <int, int>{};
    var primaryCov = const <int, int>{};
    if (fallbackFont != null) {
      fallbacks.add(pw.Font.ttf(fallbackFont));
      primaryCov = TtfParser(fallbackFont).charToGlyphIndexMap;
      coverage = primaryCov;
    }
    if (symbolFont != null) {
      fallbacks.add(pw.Font.ttf(symbolFont));
      coverage = {...coverage, ...TtfParser(symbolFont).charToGlyphIndexMap};
    }
    return DocumentPdfFonts(
      base: serif ? pw.Font.times() : pw.Font.helvetica(),
      bold: serif ? pw.Font.timesBold() : pw.Font.helveticaBold(),
      italic: serif ? pw.Font.timesItalic() : pw.Font.helveticaOblique(),
      boldItalic: serif
          ? pw.Font.timesBoldItalic()
          : pw.Font.helveticaBoldOblique(),
      mono: pw.Font.courier(),
      fallback: fallbacks,
      fallbackCoverage: coverage,
      primaryCoverage: primaryCov,
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
  /// door het thema hierboven maar door de SVG-lezer van `package:pdf`, en die
  /// kiest voor elke `<text>` hardgecodeerd een van de veertien
  /// standaardsneden (`src/svg/painter.dart`) — zonder terugvallijst. Die
  /// sneden reiken tot Latin-1, en `stringMetrics` *werpt* op alles daarboven,
  /// vanuit `SvgImage.paint`. Dat is tijdens `document.save()`, dus buiten elke
  /// `try` rond de tekening zelf: één gedachtestreepje in een grafiektitel
  /// kostte zo het hele document (#1942).
  ///
  /// Er wordt naar de héle SVG gekeken en niet alleen naar de tekstknopen. Dat
  /// is met opzet ruimer dan nodig: een scan die één plek mist waar tekst kan
  /// staan (een `<text>` in een `<symbol>` die via `<use>` wordt aangeroepen,
  /// bijvoorbeeld) zet de afbreker terug. De prijs is dat een tekening die zo'n
  /// teken alleen buiten haar tekst draagt onnodig op het terugvalfont komt —
  /// een tekening die dan nog steeds klopt.
  SvgTypesetting svgTypesetting(String svg) {
    if (!svg.runes.any((rune) => rune > 0xFF)) {
      return const SvgTypesetting.standard();
    }
    // De SVG-lezer van `package:pdf` kiest één font voor alle `<text>`-knopen,
    // zonder terugvallijst. Roboto dekt Latijns, Grieks, Cyrillisch — maar geen
    // pijlen of wiskundetekens. Bevat de SVG zulke tekens, dan kiest het
    // symbolen-font: een pijl die er wél is maar in de verkeerde snede staat is
    // beter dan een leeg blokje in de juiste snede (#1968).
    final hasUncoveredByPrimary = svg.runes.any(
      (rune) => rune > 0xFF && !primaryCoverage.containsKey(rune),
    );
    final font = hasUncoveredByPrimary && fallback.length > 1
        ? fallback[1]
        : unicode;
    return font == null
        ? const SvgTypesetting.unsettable()
        : SvgTypesetting.withFont(font);
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

  /// Deze snede moet het doen, want de standaardsneden kunnen het niet.
  const SvgTypesetting.withFont(pw.Font this.font) : settable = true;

  /// Geen enkele beschikbare snede kan deze tekening zetten.
  const SvgTypesetting.unsettable() : font = null, settable = false;

  /// De snede die aan `customFontLookup` meegegeven moet worden, of `null` als
  /// de lezer zijn eigen keuze mag houden.
  final pw.Font? font;

  /// Of de tekening überhaupt getekend kan worden. Is dit `false`, dan hoort de
  /// aanroeper terug te vallen op de bron: `pw.SvgImage` zou pas bij `save()`
  /// werpen, en dan is het hele document weg.
  final bool settable;
}
