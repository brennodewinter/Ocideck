// Part of the document_editor_screen library — see ../document_editor_screen.dart.
// De bronbewerkingen van de documenteditor: invoegen en terugschrijven van
// blokken, de hoofdstukafbrekingen over het hele document, en de bestandsnaam-
// veilige exportnaam. Op één na allemaal puur; de uitzondering
// ([applyChapterBreaksToDocument]) dient de pure bewerking bij de notifier in.
// Hier apart zodat het
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

/// Zet in [body] een `---` vóór elke hoofdstukkop (`H1`) behalve de eerste, en
/// geef de nieuwe body terug. Dat is de draagbare vorm van "nieuw hoofdstuk op
/// een nieuwe pagina" (FILE_FORMAT.md §14.6): een `---` vóór een `H1` is een
/// pagina-einde dat élke lezer honoreert — OciDeck, Pandoc, en de printer van de
/// ontvanger — in plaats van een instelling die alleen in deze app bestaat en
/// niet met het bestand meereist.
///
/// De eerste kop krijgt er nooit een: een breuk vóór de eerste regel zou een
/// leeg eerste vel opleveren — dezelfde regel die
/// [DocumentMarkdownView.forcedPageBreaks] bij de weergave hanteert.
///
/// Idempotent: staat er al een thematische breuk vóór de kop (met hoogstens lege
/// regels ertussen), dan blijft die body byte-getrouw. Twee keer toepassen geeft
/// dus geen dubbele `---`.
///
/// Verwacht de *body*, niet de hele bron: de frontmatter blijft buiten schot
/// omdat de editor hem er pas bij de terugschrijf weer vóór zet. Koppen binnen
/// een fenced blok tellen niet mee — de telling komt van
/// [DocumentMarkdownView.chapterHeadingLines], dezelfde grammatica als de
/// weergave. Top-level en puur, los toetsbaar van het editor-scherm.
String applyChapterPageBreaks(String body) {
  final headings = DocumentMarkdownView.chapterHeadingLines(body);
  if (headings.length < 2) return body;
  final lines = body.split('\n');
  // Van achter naar voren, zodat de nog te behandelen regelnummers geldig
  // blijven terwijl we regels invoegen.
  for (final line in headings.skip(1).toList().reversed) {
    if (_hasThematicBreakBefore(lines, line)) continue;
    // Een `---` direct ónder een tekstregel is in Markdown geen breuk maar een
    // setext-H2 van die regel; daarom altijd een lege regel ervoor als er nog
    // tekst staat.
    final needsBlankBefore = line > 0 && lines[line - 1].trim().isNotEmpty;
    lines.insertAll(line, [if (needsBlankBefore) '', '---', '']);
  }
  return lines.join('\n');
}

/// Laat elk hoofdstuk (`H1`) van het geopende document op een nieuwe pagina
/// beginnen, en zeg wat er gebeurde. De bewerking loopt via dezelfde route als
/// elke andere bronbewerking (`documentProvider.edit`, een eigen stap), dus je
/// ziet het in de bron staan en ongedaan maken brengt het terug. Stond alles al
/// goed, dan verandert er niets — en zegt de melding dat eerlijk in plaats van
/// te doen alsof.
///
/// Top-level en niet op de schermstaat, zoals [_choosePageSetupScope]: de
/// klasse zat op haar plafond.
void applyChapterBreaksToDocument(BuildContext context, WidgetRef ref) {
  final doc = ref.read(documentProvider).document;
  if (doc == null) return;
  final next = applyChapterPageBreaks(doc.body);
  final changed = next != doc.body;
  if (changed) _commitDocumentBody(ref, next, coalesceKey: null);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        changed
            ? context.l10n.d('Elk hoofdstuk begint nu op een nieuwe pagina')
            : context.l10n.d('Elk hoofdstuk begon al op een nieuwe pagina'),
      ),
    ),
  );
}

/// Of er boven regel [line] al een thematische breuk staat, met hoogstens lege
/// regels ertussen. De breuk hoeft niet op fenced blokken te toetsen: een `---`
/// binnen een fence kan alleen de direct voorafgaande niet-lege regel zijn als
/// die fence nog openstaat, en dan zou de kop zelf ook in de fence liggen en
/// [DocumentMarkdownView.chapterHeadingLines] niet hebben gehaald.
bool _hasThematicBreakBefore(List<String> lines, int line) {
  for (var i = line - 1; i >= 0; i--) {
    if (lines[i].trim().isEmpty) continue;
    return DocumentMarkdownView.isThematicBreakLine(lines[i]);
  }
  return false;
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
