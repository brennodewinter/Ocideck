import 'markdown_table_codec.dart';
import 'table_sort.dart';
import '../models/document_timeline.dart';

export '../models/document_timeline.dart';

/// De draagbare markering waarmee alleen de direct volgende GFM-tabel als
/// tijdlijn wordt weergegeven. Zonder deze regel blijft exact dezelfde bron een
/// gewone tabel in iedere Markdown-lezer.
const documentTimelineMarker = '<!-- timeline -->';

final RegExp _dateOnlyMarker = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _zonedInstantMarker = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})$',
  caseSensitive: false,
);

/// Schrijft een kalenderdatum zonder tijd of tijdzone. Zo'n datum is geen
/// moment op de UTC-tijdlijn en mag bij openen in een andere zone nooit een
/// dag opschuiven.
String canonicalDocumentTimelineDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Schrijft een echt tijdstip canoniek als ISO-8601 UTC.
String canonicalDocumentTimelineInstant(DateTime instant) =>
    instant.toUtc().toIso8601String();

/// Menselijk, maar ondubbelzinnig label voor een UTC-offset.
String formatDocumentTimelineUtcOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes < 0 ? '-' : '+';
  final absolute = totalMinutes.abs();
  final hours = (absolute ~/ 60).toString().padLeft(2, '0');
  final minutes = (absolute % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}

/// Projecteert alleen expliciet gezoneerde ISO-tijdstippen naar de lokale
/// klok. Datum-zonder-tijd en oude vrije markeringen blijven bytegetrouw.
/// [toLocal] maakt de tijdzone in tests en andere projecties injecteerbaar.
String formatDocumentTimelineMarker(
  String source, {
  DateTime Function(DateTime utc)? toLocal,
}) {
  final value = source.trim();
  if (_dateOnlyMarker.hasMatch(value)) return source;
  if (!_zonedInstantMarker.hasMatch(value)) return source;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return source;
  final local = (toLocal ?? (utc) => utc.toLocal())(parsed.toUtc());
  final date = canonicalDocumentTimelineDate(local);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute '
      '${formatDocumentTimelineUtcOffset(local.timeZoneOffset)}';
}

/// Geeft alle echte momenten terug die bij een lokale wandklok passen.
///
/// Normale tijden leveren één kandidaat, een zomertijdgat geen en een
/// teruggezette klok twee. Daardoor hoeft de invoer geen niet-bestaande tijd te
/// normaliseren of bij een dubbel uur stil één van beide te raden.
List<DateTime> documentTimelineInstantCandidates(
  DateTime wallClock, {
  DateTime Function(DateTime utc)? toLocal,
}) {
  final project = toLocal ?? (utc) => utc.toLocal();
  // [wallClock] draagt kalendercomponenten, geen tijdzone. UTC voorkomt dat de
  // DateTime-constructor een niet-bestaand lokaal zomertijduur al normaliseert
  // vóór wij het kunnen afwijzen.
  final seed = DateTime.utc(
    wallClock.year,
    wallClock.month,
    wallClock.day,
    wallClock.hour,
    wallClock.minute,
  );
  bool sameWallClock(DateTime value) =>
      value.year == wallClock.year &&
      value.month == wallClock.month &&
      value.day == wallClock.day &&
      value.hour == wallClock.hour &&
      value.minute == wallClock.minute;
  final candidates = <DateTime>[];
  // UTC−12…UTC+14 vallen ruim binnen dit venster, ook wanneer tests of een
  // import een andere zone projecteren dan de zone van dit apparaat.
  for (var minutes = -1080; minutes <= 1080; minutes++) {
    final instant = seed.add(Duration(minutes: minutes));
    if (!sameWallClock(project(instant))) continue;
    if (candidates.every((candidate) => candidate != instant)) {
      candidates.add(instant);
    }
  }
  candidates.sort();
  return candidates;
}

/// Of drie opeenvolgende regels de draagbare tijdlijn-envelop openen.
///
/// Dit zegt alleen dat marker en GFM-tabel atomair bij elkaar horen. Of de
/// tabel ook twee of drie kolommen en gebeurtenissen heeft, is een afzonderlijk
/// geschiktheidsoordeel van [analyzeMarkedTimeline].
bool isDocumentTimelineEnvelope(
  String markerLine,
  String? headerLine,
  String? delimiterLine,
) =>
    markerLine.trim() == documentTimelineMarker &&
    headerLine != null &&
    delimiterLine != null &&
    isMarkdownTableLine(headerLine) &&
    isMarkdownTableDelimiterRow(delimiterLine);

/// Of [source] daadwerkelijk met marker, kop en scheidingsrij opent.
///
/// Eén gedeelde broncontrole voor bridge en privacylaag voorkomt zowel
/// grammaticadrift als herhaald scannen van lange, gewone Markdownvelden.
bool startsWithDocumentTimelineEnvelope(String source) {
  final markerEnd = source.indexOf('\n');
  if (markerEnd < 0) return false;
  final headerEnd = source.indexOf('\n', markerEnd + 1);
  if (headerEnd < 0) return false;
  final delimiterEnd = source.indexOf('\n', headerEnd + 1);
  if (delimiterEnd < 0) return false;
  return isDocumentTimelineEnvelope(
    source.substring(0, markerEnd),
    source.substring(markerEnd + 1, headerEnd),
    source.substring(headerEnd + 1, delimiterEnd),
  );
}

/// Analyseert een kale GFM-tabel voor de tijdlijnweergave.
///
/// Twee kolommen betekenen marker + gebeurtenis; een derde blijft als neutrale
/// metadata zichtbaar. Namen of waarden krijgen bewust geen semantische kleur:
/// `Status`, `Bron` en `Eigenaar` zijn in verschillende documenten allemaal
/// geldige derde kolommen en OciDeck hoort hun betekenis niet te verzinnen.
TimelineTableAnalysis analyzeTimelineTable(String tableSource) {
  final lines = tableSource.trimRight().split('\n');
  if (lines.length < 2 ||
      !isMarkdownTableLine(lines.first) ||
      !isMarkdownTableDelimiterRow(lines[1])) {
    return const TimelineTableAnalysis.unusable(TimelineTableIssue.noTable);
  }
  final decoded = decodeMarkdownTableRows(lines);
  if (decoded.isEmpty) {
    return const TimelineTableAnalysis.unusable(TimelineTableIssue.noTable);
  }
  final columns = decoded.first.length;
  if (columns != 2 && columns != 3) {
    return const TimelineTableAnalysis.unusable(
      TimelineTableIssue.wrongColumnCount,
    );
  }
  final body = decoded.skip(1);
  if (body.isEmpty) {
    return const TimelineTableAnalysis.unusable(TimelineTableIssue.noEvents);
  }
  final events = [
    for (final row in body)
      DocumentTimelineEvent(
        sourceMarker: row.isNotEmpty ? row[0] : '',
        marker: row.isNotEmpty ? formatDocumentTimelineMarker(row[0]) : '',
        event: row.length > 1 ? row[1] : '',
        metadata: columns == 3 && row.length > 2 ? row[2] : null,
      ),
  ];
  return TimelineTableAnalysis.usable(
    DocumentTimeline(
      source: tableSource,
      headers: decoded.first,
      events: events,
      markerAnalysis: const TableSortService().analyze(lines, columnIndex: 0),
    ),
  );
}

/// Leest het atomaire schijfcontract. De marker moet direct boven de tabel
/// staan; een lege regel ertussen maakt hem gewone, betekenisloze HTML-comment.
TimelineTableAnalysis analyzeMarkedTimeline(String source) {
  final newline = source.indexOf('\n');
  if (newline < 0 ||
      source.substring(0, newline).trimRight().trim() !=
          documentTimelineMarker) {
    return const TimelineTableAnalysis.unusable(TimelineTableIssue.noTable);
  }
  return analyzeTimelineTable(source.substring(newline + 1));
}

String markTableAsTimeline(String tableSource) =>
    '$documentTimelineMarker\n$tableSource';

/// Verwijdert uitsluitend de eerste, contractuele marker. De tabelbytes worden
/// niet geparseerd of opnieuw geschreven.
String unmarkTimeline(String source) {
  final newline = source.indexOf('\n');
  if (newline < 0 ||
      source.substring(0, newline).trim() != documentTimelineMarker) {
    return source;
  }
  return source.substring(newline + 1);
}

/// Loopt [source] regel voor regel, detecteert gemarkeerde tijdlijntabellen,
/// en roept [render] aan voor elke gevonden tijdlijn. De teruggegeven bron
/// bevat `OCIDECKTIMELINE{n}END`-sentinels op de plek van elke tabel; de
/// gerenderde fragmenten staan in de teruggegeven lijst. De vijf
/// formaat-converters (DOCX, ODT, EPUB, LaTeX, PDF) delen deze detectielus;
/// alleen de render-callback verschilt per formaat.
({String source, List<T> rendered}) protectTimelines<T>(
  String source,
  T Function(DocumentTimeline timeline) render,
) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final output = <String>[];
  final rendered = <T>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].trim() != documentTimelineMarker ||
        index + 2 >= lines.length ||
        !isMarkdownTableLine(lines[index + 1]) ||
        !isMarkdownTableDelimiterRow(lines[index + 2])) {
      output.add(lines[index++]);
      continue;
    }
    var end = index + 3;
    while (end < lines.length && isMarkdownTableLine(lines[end])) {
      end++;
    }
    final marked = lines.sublist(index, end).join('\n');
    final timeline = analyzeMarkedTimeline(marked).timeline;
    if (timeline == null) {
      output.add(lines[index++]);
      continue;
    }
    output.add('OCIDECKTIMELINE${rendered.length}END');
    rendered.add(render(timeline));
    index = end;
  }
  return (source: output.join('\n'), rendered: rendered);
}
