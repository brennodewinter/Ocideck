import 'table_sort.dart';

/// Waarom een tabel wel of niet als tijdlijn kan worden weergegeven.
enum TimelineTableIssue { noTable, wrongColumnCount, noEvents }

/// Een gebeurtenis zoals de documentweergave hem nodig heeft.
class DocumentTimelineEvent {
  const DocumentTimelineEvent({
    required this.marker,
    required this.event,
    this.metadata,
  });

  final String marker;
  final String event;
  final String? metadata;
}

/// Een verliesvrij herkende tijdlijn: [source] blijft de gezaghebbende bron;
/// headers en gebeurtenissen zijn uitsluitend afgeleid voor de weergave.
class DocumentTimeline {
  const DocumentTimeline({
    required this.source,
    required this.headers,
    required this.events,
    required this.markerAnalysis,
  });

  final String source;
  final List<String> headers;
  final List<DocumentTimelineEvent> events;
  final TableSortAnalysis markerAnalysis;
}

/// Resultaat van de lokale, deterministische geschiktheidscontrole.
class TimelineTableAnalysis {
  const TimelineTableAnalysis._({this.timeline, this.issue});

  const TimelineTableAnalysis.usable(DocumentTimeline timeline)
    : this._(timeline: timeline);

  const TimelineTableAnalysis.unusable(TimelineTableIssue issue)
    : this._(issue: issue);

  final DocumentTimeline? timeline;
  final TimelineTableIssue? issue;

  bool get isUsable => timeline != null;
}
