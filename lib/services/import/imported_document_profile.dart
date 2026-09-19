// Van de huisstijl van een brondocument naar een stijlprofiel (#2119).
//
// De tegenhanger van `importedLogoProfile` in `logo_detection.dart`, maar
// voor documenten: letters krijgen een plaatsvervanger op het scherm en
// bewaren hun eigen naam voor de export, kleuren gaan door de kleurpoort, en
// het logo krijgt de plek en maat waarop het in de bron stond. Alles landt
// via `ThemeProfile.fromJson`, zodat een brondocument geen onbekende letter of
// ongeldige kleur in de renderer kan brengen.
//
// Headless: geen Flutter, geen IO. Het pad naar het logo is al door de
// aanroeper bepaald (op schijf of in de webopslag).

import '../../models/settings.dart';
import '../font_substitution.dart';
import 'models/source_document_style.dart';

/// Beeldpunten per millimeter op de bladzijde — dezelfde 96 dpi als
/// `kPxPerMm` in de paginaweergave, hier zonder Flutter-import.
const _pxPerMm = 96 / 25.4;

/// De breedte in beeldpunten waarop een logo van [widthMm] op het blad
/// getekend wordt, binnen de grenzen van `documentLogoSize`.
int documentLogoSizeForWidthMm(double widthMm) =>
    (widthMm * _pxPerMm).round().clamp(32, 480);

/// Bouwt het profiel voor een geïmporteerd document.
///
/// [base] is het profiel waarvan al het overige overgenomen wordt (de
/// tabelstijl, de codekleuren, de ernstkleuren); wat de bron zegt, wint.
/// [logoPath] en [logo] horen bij elkaar: het pad waar de aanroeper het
/// gekozen beeld heeft gezet, en de kandidaat met zijn plek en maat. Zonder
/// logo krijgt het document er bewust géén — ook niet dat van [base], want
/// een geïmporteerde huisstijl is niet die van een ander profiel.
ThemeProfile buildImportedDocumentProfile({
  required SourceDocumentStyle style,
  required ThemeProfile base,
  required String name,
  String? logoPath,
  DocumentLogoCandidate? logo,
}) {
  final json = <String, Object?>{...base.toJson(), 'name': name};

  final body = style.bodyFontFamily;
  final bodyStandIn = body == null
      ? base.fontFamily
      : nearestAvailableFont(body);
  json['fontFamily'] = bodyStandIn;
  json['preferredFontFamily'] = body != null && !_sameFont(body, bodyStandIn)
      ? body
      : null;

  final heading = style.headingFontFamily;
  json['documentHeadingFontFamily'] = null;
  json['preferredDocumentHeadingFontFamily'] = null;
  if (heading != null && (body == null || !_sameFont(heading, body))) {
    final headingStandIn = nearestAvailableFont(heading);
    if (!_sameFont(headingStandIn, bodyStandIn)) {
      json['documentHeadingFontFamily'] = headingStandIn;
    }
    if (!_sameFont(heading, headingStandIn)) {
      json['preferredDocumentHeadingFontFamily'] = heading;
    }
  }

  // Kleuren: wat de bron zet, wint; de afgeleide velden (tabelkop,
  // vinkjes) vallen dan terug op de nieuwe waarde in plaats van op die van
  // het basisprofiel.
  if (style.textColor != null) {
    json['textColor'] = style.textColor;
    json.remove('tableTextColor');
  }
  if (style.accentColor != null) {
    json['accentColor'] = style.accentColor;
    json.remove('tableHeaderBackgroundColor');
    json.remove('checklistCheckedColor');
  }
  json['documentHeadingColor'] = style.headingColor;

  json['documentHeaderText'] = style.headerText ?? '';
  json['documentFooterText'] = style.footerText ?? '';
  json['documentShowPageNumbers'] = style.showPageNumbers;

  json['logoPath'] = null;
  json['logoDarkPath'] = null;
  json['brandStripPath'] = null;
  json['brandStripHeight'] = 0;
  json['titleSubtitleInBrandStrip'] = false;
  if (logoPath != null && logo != null) {
    json['documentLogoPath'] = logoPath;
    json['documentLogoPosition'] = logo.position;
    json['documentLogoSize'] = documentLogoSizeForWidthMm(logo.widthMm);
  } else {
    // Een lege string is "bewust geen documentlogo" (FILE_FORMAT §3.2).
    json['documentLogoPath'] = '';
    json['documentLogoSize'] = null;
  }

  return ThemeProfile.fromJson(json);
}

bool _sameFont(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Of [profile] al de stijl van [style] is — dezelfde letters (op naam, zoals
/// een export ze noemt), dezelfde kleuren, dezelfde kop- en voettekst. Het
/// logo wordt hier niet vergeleken; dat doet de aanroeper op de bytes.
///
/// Alleen wat de bron zégt telt mee: een bron zonder kopkleur past bij een
/// profiel met en zonder. Zo herkent een tweede import van hetzelfde sjabloon
/// zijn eigen profiel en komt er geen "Stijl van X (2)" bij.
bool documentStyleMatchesProfile(
  SourceDocumentStyle style,
  ThemeProfile profile,
) {
  bool same(String? source, String? candidate) =>
      source == null || (candidate != null && _sameFont(source, candidate));
  bool sameColor(String? source, String? candidate) =>
      source == null || source.toUpperCase() == candidate?.toUpperCase();

  return same(style.bodyFontFamily, profile.exportFontFamily) &&
      same(style.headingFontFamily, profile.exportDocumentHeadingFontFamily) &&
      sameColor(style.textColor, profile.textColor) &&
      sameColor(style.accentColor, profile.accentColor) &&
      sameColor(style.headingColor, profile.documentHeadingColor) &&
      (style.footerText ?? '') == profile.documentFooterText &&
      (style.headerText ?? '') == profile.documentHeaderText &&
      style.showPageNumbers == profile.documentShowPageNumbers;
}
