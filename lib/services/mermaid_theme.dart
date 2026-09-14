import 'dart:convert';

import '../models/settings.dart';
import '../utils/color_contrast.dart';

/// Mermaid `themeVariables` afgeleid uit een [ThemeProfile], zodat diagrammen
/// (vooral gantt) de kleuren van de gekozen stijl volgen in plaats van het
/// vaste `neutral`-thema uit [kMermaidInitConfig]. `theme` en `themeVariables`
/// staan bewust niet in de `secure`-lijst, dus een per-diagram `%%{init}%%`-
/// directive mag ze overschrijven.
///
/// De mapping dekt zowel algemene diagrammen (flowchart, sequence, …) als
/// gantt-specifieke variabelen. Tekst op een accentkleurige balk krijgt een
/// contrastkleur via [nearestContrastingHex], zodat de balk leesbaar blijft
/// ongeacht of het accent donker of licht is.
///
/// `ponytail:` ceiling — `primaryTextColor`/`taskTextColor` vertrekken vanuit
/// de slide-achtergrondkleur en schuiven naar zwart/wit tot WCAG-large (3:1)
/// haalbaar is. Bij een accent dat zelf al op de slide-achtergrond lijkt
/// (bv. beide wit) kan de tekst op de balk daardoor op de achtergrond van de
/// balk zelf vallen — oplossing: een expliciet donkerder accent in het profiel.
Map<String, String> mermaidThemeVariablesFor(ThemeProfile p) {
  final onAccent = nearestContrastingHex(
    p.slideBackgroundColor,
    p.accentColor,
    minRatio: 3.0,
  );
  return {
    // Algemeen: knopen en lijnen.
    'primaryColor': p.accentColor,
    'primaryBorderColor': p.accentColor,
    'primaryTextColor': onAccent,
    'secondaryColor': p.titleBackgroundColor,
    'secondaryBorderColor': p.titleBackgroundColor,
    'secondaryTextColor': p.titleTextColor,
    'tertiaryColor': p.sectionBackgroundColor,
    'tertiaryBorderColor': p.sectionBackgroundColor,
    'tertiaryTextColor': p.textColor,
    'lineColor': p.textColor,
    'textColor': p.textColor,
    // Gantt: balken, statussen, rooster.
    'taskBkgColor': p.accentColor,
    'taskBorderColor': p.accentColor,
    'taskTextColor': onAccent,
    'taskTextDarkColor': onAccent,
    'taskTextLightColor': p.textColor,
    'taskTextOutsideColor': p.textColor,
    'activeTaskBkgColor': p.accentColor,
    'activeTaskBorderColor': p.textColor,
    'doneTaskBkgColor': p.checklistUncheckedColor,
    'doneTaskBorderColor': p.checklistUncheckedColor,
    'critBkgColor': p.severityCriticalColor,
    'critBorderColor': p.severityCriticalColor,
    'todayLineColor': p.severityCriticalColor,
    'sectionBkgColor': p.tableZebraColor,
    'altSectionBkgColor': p.slideBackgroundColor,
    'gridColor': p.tableBorderColor,
  };
}

/// Injecteert een `%%{init: {"themeVariables": …}}%%`-directive in [source]
/// met de kleuren van [profile]. Bestaande `%%{init}%%`-directives worden
/// gemerged (themeVariables toegevoegd of overschreven); YAML-frontmatter
/// blijft eerst staan. De cache van [MermaidRenderService] sleutelt op de
/// bron, dus een gewijzigd profiel rendert opnieuw in plaats van de oude SVG
/// te hergebruiken.
String mermaidWithThemeColors(String source, ThemeProfile profile) {
  final vars = mermaidThemeVariablesFor(profile);
  final directive = '%%{init: ${jsonEncode({'themeVariables': vars})}}%%';
  final trimmed = source.trimLeft();
  // YAML-frontmatter moet de eerste regel blijven; directive na sluitende ---.
  if (trimmed.startsWith('---')) {
    final fm = RegExp(
      r'^---[ \t]*\r?\n.*?\r?\n---[ \t]*\r?\n?',
      dotAll: true,
    ).firstMatch(source);
    if (fm != null) {
      final after = source.substring(fm.end);
      final merged = injectIntoMermaidInit(after, {'themeVariables': vars});
      return merged != null
          ? '${source.substring(0, fm.end)}$merged'
          : '${source.substring(0, fm.end)}$directive\n$after';
    }
  }
  return injectIntoMermaidInit(source, {'themeVariables': vars}) ??
      '$directive\n$source';
}

/// Voegt [overrides] toe aan de JSON van de eerste `%%{init: {…}}%%`-directive
/// in [source] (bestaande sleutels behouden, nieuwe toegevoegd/overschreven).
/// Geeft `null` terug wanneer er geen parseerbare directive is — de aanroeper
/// zet de directive er dan zelf voor. Gebruikt door [mermaidWithThemeColors]
/// en door de donkere lezermodus (`mermaidWithDarkTheme`).
String? injectIntoMermaidInit(String source, Map<String, dynamic> overrides) {
  final idx = source.indexOf('%%{init:');
  if (idx < 0) return null;
  final jsonStart = source.indexOf('{', idx + 8);
  if (jsonStart < 0) return null;
  var depth = 0;
  var i = jsonStart;
  for (; i < source.length; i++) {
    if (source[i] == '{') {
      depth++;
    } else if (source[i] == '}') {
      if (--depth == 0) {
        i++;
        break;
      }
    }
  }
  if (depth != 0) return null;
  var j = i;
  while (j < source.length && source[j] == ' ') {
    j++;
  }
  if (!source.startsWith('}%%', j)) return null;
  try {
    final config =
        jsonDecode(source.substring(jsonStart, i)) as Map<String, dynamic>;
    config.addAll(overrides);
    return '${source.substring(0, idx)}%%{init: ${jsonEncode(config)}}%%${source.substring(j + 3)}';
  } on FormatException {
    return null;
  }
}
