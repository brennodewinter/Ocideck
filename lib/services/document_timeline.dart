import 'markdown_table_codec.dart';
import 'table_sort.dart';
import '../models/document_timeline.dart';

export '../models/document_timeline.dart';

/// De draagbare markering waarmee alleen de direct volgende GFM-tabel als
/// tijdlijn wordt weergegeven. Zonder deze regel blijft exact dezelfde bron een
/// gewone tabel in iedere Markdown-lezer.
const documentTimelineMarker = '<!-- timeline -->';

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
        marker: row.isNotEmpty ? row[0] : '',
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
