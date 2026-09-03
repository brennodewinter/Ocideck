// Het stijlprofiel van het document, vertaald naar wat een PDF begrijpt.
//
// De app bewaart kleuren als `#RRGGBB`-tekst en de meeste maten in CSS-pixels;
// de bodylettergrootte is al een typografisch punt — dezelfde eenheid als
// `package:pdf`. Celopvulling gaat hier van px naar pt (`× 0.75`). Deze laag
// doet die omzetting één keer, zodat de renderer verderop alleen nog tekent.
//
// De typografie (koptrapjes, regelafstand, witruimte) staat hier ook, en met
// opzet als getallen bij elkaar: dat maakt de verhoudingen van het document
// zichtbaar op één plek in plaats van verspreid over tekenroutines.

import 'package:pdf/pdf.dart';

import '../../models/settings.dart' show TableBorderStyle, ThemeProfile;

/// Millimeters naar PDF-punten. Een punt is 1/72 duim, een duim 25,4 mm.
double mmToPt(double mm) => mm * PdfPageFormat.mm;

/// De opmaakregels waarmee het document wordt gezet.
class DocumentPdfStyle {
  DocumentPdfStyle({
    required this.bodyFontSize,
    required this.textColor,
    required this.accentColor,
    required this.headingColor,
    required this.subheadingColor,
    required this.codeBackground,
    required this.codeText,
    required this.tableBorderStyle,
    required this.tableBorderColor,
    required this.tableHeaderBackground,
    required this.tableHeaderText,
    required this.tableText,
    required this.tableZebra,
    required this.tableCellPadding,
    required this.headerText,
    required this.footerText,
    required this.showPageNumbers,
    required this.bandTextColor,
    required this.bandBackgroundColor,
  });

  /// Leidt de opmaak af uit het stijlprofiel van het document.
  factory DocumentPdfStyle.fromTheme(ThemeProfile theme) {
    final text = _color(theme.textColor, const PdfColor(0.13, 0.13, 0.13));
    return DocumentPdfStyle(
      bodyFontSize: theme.documentBodyFontSize,
      textColor: text,
      accentColor: _color(theme.accentColor, PdfColors.teal700),
      headingColor: _color(theme.effectiveDocumentHeadingColor, text),
      subheadingColor: _color(
        theme.effectiveDocumentSubheadingColor,
        _color(theme.accentColor, PdfColors.teal700),
      ),
      codeBackground: _color(theme.codeBackgroundColor, PdfColors.grey900),
      codeText: _color(theme.codeTextColor, PdfColors.grey300),
      tableBorderStyle: theme.tableBorderStyle,
      tableBorderColor: _color(theme.tableBorderColor, PdfColors.grey400),
      tableHeaderBackground: _color(
        theme.tableHeaderBackgroundColor,
        PdfColors.blueGrey800,
      ),
      tableHeaderText: _color(theme.tableHeaderTextColor, PdfColors.white),
      tableText: _color(theme.tableTextColor, text),
      tableZebra: theme.tableZebraStriped
          ? _color(theme.tableZebraColor, PdfColors.grey100)
          : null,
      tableCellPadding: theme.tableCellPaddingPx * 0.75,
      headerText: theme.documentHeaderText,
      footerText: theme.documentFooterText,
      showPageNumbers: theme.documentShowPageNumbers,
      bandTextColor: _color(theme.documentBandTextColor, PdfColors.grey600),
      bandBackgroundColor: theme.documentBandBackgroundColor == null
          ? null
          : _color(theme.documentBandBackgroundColor, PdfColors.grey200),
    );
  }

  /// De grootte van de lopende tekst, in punten. Alles hieronder is hiervan
  /// afgeleid, zodat het document als geheel meeschaalt.
  final double bodyFontSize;

  final PdfColor textColor;
  final PdfColor accentColor;

  /// De kleur van een hoofdstukkop en van een subkop. Zonder kopkleur in het
  /// profiel is dat de tekstkleur en het accent — dezelfde verdeling als de
  /// documentweergave in de app en de HTML-export, zodat de drie oppervlakken
  /// hetzelfde blad tonen.
  final PdfColor headingColor;
  final PdfColor subheadingColor;
  final PdfColor codeBackground;
  final PdfColor codeText;

  final TableBorderStyle tableBorderStyle;
  final PdfColor tableBorderColor;
  final PdfColor tableHeaderBackground;
  final PdfColor tableHeaderText;
  final PdfColor tableText;

  /// De kleur van de even rijen, of `null` wanneer de tabel niet zebra't.
  final PdfColor? tableZebra;

  final double tableCellPadding;

  /// De vrije tekst boven- en onderaan elke bladzijde, en of het nummer erbij
  /// staat. Leeg betekent: geen band.
  final String headerText;
  final String footerText;
  final bool showPageNumbers;
  final PdfColor bandTextColor;
  final PdfColor? bandBackgroundColor;

  /// De letterhoogte van een kop van [level] (1 t/m 6).
  ///
  /// Een klassiek trapje: elke stap ongeveer een vijfde kleiner, en vanaf niveau
  /// vijf niet kleiner dan de lopende tekst — een kop die kleiner is dan zijn
  /// eigen alinea leest niet meer als kop.
  double headingSize(int level) => switch (level) {
    1 => bodyFontSize * 1.9,
    2 => bodyFontSize * 1.5,
    3 => bodyFontSize * 1.25,
    4 => bodyFontSize * 1.1,
    _ => bodyFontSize,
  };

  /// De witruimte bóven een kop van [level]. Een kop hoort dichter bij de tekst
  /// die hij aankondigt dan bij de tekst die hij afsluit; daarom is de ruimte
  /// erboven ruimer dan die eronder.
  double headingSpaceBefore(int level) =>
      level <= 2 ? bodyFontSize * 1.4 : bodyFontSize * 1.0;

  double get headingSpaceAfter => bodyFontSize * 0.45;

  /// De witruimte onder een alinea, lijst, tabel of codeblok.
  double get blockSpacing => bodyFontSize * 0.7;

  /// De inspringing van een lijstpunt en van een citaat.
  double get indent => bodyFontSize * 1.4;

  /// De grootte van vaste-breedteletters. Courier oogt groter dan een
  /// schreefletter van dezelfde maat, dus hij gaat een tikje omlaag.
  double get monoSize => bodyFontSize * 0.9;

  /// De maat van de tekst in de band boven- en onderaan de bladzijde.
  double get bandSize => bodyFontSize * 0.75;

  /// Het vlak achter een citaat: het accent, voor een tiende, op wit papier.
  ///
  /// Dezelfde tint als de documentweergave op het scherm (`quoteBg` in
  /// `document_markdown_blocks.dart`), maar hier alvast doorgerekend tot één
  /// vaste kleur. Een PDF kán doorzichtigheid, maar alleen via een aparte
  /// grafische toestand die elke lezer anders behandelt — en het papier is hier
  /// toch wit, dus het resultaat is hetzelfde en het bestand eenvoudiger.
  PdfColor get quoteBackground => _blendOnWhite(accentColor, 0.10);

  /// De dikte van de streep langs een citaat, in punten. Gelijk aan de drie
  /// beeldpunten van het scherm.
  double get quoteBarWidth => 3;

  /// De ruimte tussen die streep en de tekst van het citaat.
  double get quotePadding => bodyFontSize * 0.75;

  static PdfColor _blendOnWhite(PdfColor color, double alpha) => PdfColor(
    color.red * alpha + (1 - alpha),
    color.green * alpha + (1 - alpha),
    color.blue * alpha + (1 - alpha),
  );

  static PdfColor _color(String? hex, PdfColor fallback) {
    if (hex == null) return fallback;
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return fallback;
    // Acht tekens betekent dat de doorzichtigheid vooraan staat; een PDF kent
    // die niet op tekst, dus alleen de kleur zelf telt.
    final rgb = cleaned.length == 8 ? value & 0xFFFFFF : value;
    return PdfColor.fromInt(0xFF000000 | rgb);
  }
}
