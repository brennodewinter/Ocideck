// Part of the document_editor_screen library — see ../document_editor_screen.dart.
// De pure bronbewerkingen van de documenteditor: invoegen en terugschrijven van
// blokken, en de bestandsnaam-veilige exportnaam. Hier apart zodat het
// bewerkscherm zelf onder zijn regelplafond blijft. Alle imports leven in het
// hoofdbestand.
part of '../document_editor_screen.dart';

/// Voeg [block] in [source] in op het bereik [selStart]–[selEnd] (een negatieve
/// start betekent 'geen cursor' → achteraan), omgeven door precies genoeg lege
/// regels om een eigen alinea te vormen zonder er ooit meer dan één dubbele
/// witregel van te maken. Geeft de nieuwe bron én de cursorpositie ná het
/// ingevoegde blok terug. Top-level en puur, zodat de invoeglogica los toetsbaar
/// is van het editor-scherm — net als de terugschrijf-helpers hierboven.
(String, int) insertBlockIntoSource(
  String source,
  int selStart,
  int selEnd,
  String block,
) {
  final start = selStart < 0 ? source.length : math.min(selStart, selEnd);
  final end = selEnd < 0 ? source.length : math.max(selStart, selEnd);
  final before = source.substring(0, start);
  final after = source.substring(end);
  final lead = before.isEmpty
      ? ''
      : before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trail = after.isEmpty
      ? '\n'
      : after.startsWith('\n')
      ? ''
      : '\n\n';
  final insertion = '$lead$block$trail';
  return ('$before$insertion$after', before.length + insertion.length);
}

/// Een bestandsnaam-veilige vorm van [title] voor de voorgestelde exportnaam:
/// alles wat geen letter/cijfer/koppelteken is wordt een koppelteken, samengedrukt
/// en getrimd. Top-level en puur, los toetsbaar van het editor-scherm.
String _safeExportName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^\w\- ]+'), '')
      .trim()
      .replaceAll(RegExp(r'[\s]+'), '-');
  return cleaned.isEmpty ? 'document' : cleaned;
}

/// Vervang de inhoud van het `chartOrdinal`-de ```chart-blok (vanaf 0) in
/// [source] door [newContent] (de kale spec-tekst, zonder fence). Andere blokken
/// — en alle tekst eromheen — blijven byte-getrouw staan; een `chartOrdinal`
/// buiten bereik laat de bron ongemoeid. Top-level en puur, zodat de
/// terugschrijf-logica los toetsbaar is van het editor-scherm.
String replaceNthChartBlock(
  String source,
  int chartOrdinal,
  String newContent,
) {
  var seen = 0;
  return source.replaceAllMapped(chartFencePattern, (m) {
    if (seen++ != chartOrdinal) return m.group(0)!;
    return '```chart\n$newContent\n```';
  });
}

/// Vervang het `tableOrdinal`-de GFM-tabelblok (vanaf 0) in [source] door
/// [newGfm], en laat elke andere byte staan. De regel-reikwijdte komt van
/// [DocumentMarkdownView.nthTableBlockRange], zodat de telling exact die van de
/// weergave volgt; een ordinaal buiten bereik laat de bron ongemoeid. Top-level
/// en puur, zodat de terugschrijf-logica los toetsbaar is.
String replaceNthTableBlock(String source, int tableOrdinal, String newGfm) {
  final range = DocumentMarkdownView.nthTableBlockRange(source, tableOrdinal);
  if (range == null) return source;
  final lines = source.split('\n');
  lines.replaceRange(range[0], range[1], newGfm.split('\n'));
  return lines.join('\n');
}
