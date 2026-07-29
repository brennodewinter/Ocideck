part of 'openkat_report_composer.dart';

typedef _OpenKatBoundedValues<T> = ({List<T> values, bool omitted, int limit});

/// Gedeelde, smalle rendercontext voor zelfstandige rapportblokrenderers.
///
/// De blokklassen bezitten hun eigen compositielogica; deze context geeft ze
/// alleen toegang tot de uniforme dia-opbouw en tekstnormalisatie.
abstract class _OpenKatRenderer {
  final OpenKatReportComposer composer;

  const _OpenKatRenderer(this.composer);

  OpenKatReportFacts get facts => composer.facts;
  bool get _english => composer._english;

  String _text(String dutch, String english) => composer._text(dutch, english);
  String _literal(String value) => composer._literal(value);
  String _inline(String value) => composer._inline(value);
  String _iso(DateTime value) => composer._iso(value);
  String _severityLabel(String band) => composer._severityLabel(band);
  String _controlLabel(String value) => composer._controlLabel(value);
  String _percent(double value) => composer._percent(value);
  String _id(String seed) => composer._id(seed);

  Slide _slide({
    required String id,
    required SlideType type,
    String title = '',
    String subtitle = '',
    List<String> bullets = const [],
    List<List<String>> tableRows = const [],
    String customMarkdown = '',
    DisplayWindowSpec? viewLimit,
    String notes = '',
    PrivacyDisposition? privacy,
  }) => composer._slide(
    id: id,
    type: type,
    title: title,
    subtitle: subtitle,
    bullets: bullets,
    tableRows: tableRows,
    customMarkdown: customMarkdown,
    viewLimit: viewLimit,
    notes: notes,
    privacy: privacy,
  );

  Slide _scorecardSlide({
    required String id,
    required String title,
    required List<ScorecardEntry> entries,
    required String view,
  }) => composer._scorecardSlide(
    id: id,
    title: title,
    entries: entries,
    view: view,
  );

  ScorecardEntry _severityEntry(
    String band,
    Map<String, int> current,
    Map<String, int>? previous,
  ) => composer._severityEntry(band, current, previous);

  String _observationLabel(
    OpenKatFindingObservation observation, {
    required bool english,
  }) => composer._observationLabel(observation, english: english);

  List<String> _omittedRow({
    required int columns,
    required bool english,
    required int shown,
  }) => composer._omittedRow(columns: columns, english: english, shown: shown);

  List<String> _emptyResultRow({required int columns}) =>
      composer._emptyResultRow(columns: columns);

  int _constructionLimit(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) => math.min(
    request.policy.tableRowLimit,
    block.preconditions.constructionBudget,
  );

  _OpenKatBoundedValues<T> _bounded<T>(
    Iterable<T> values,
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final limit = _constructionLimit(request, block);
    final probed = values.take(limit + 1).toList(growable: false);
    return (
      values: probed.take(limit).toList(growable: false),
      omitted: probed.length > limit,
      limit: limit,
    );
  }

  DisplayWindowSpec? _tableViewLimit<T>(
    OpenKatReportBlock block,
    _OpenKatBoundedValues<T> bounded,
  ) => bounded.omitted
      ? null
      : DisplayWindowSpec(limit: block.preconditions.viewLimit);

  String _blockView(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
    String view,
  ) => 'report.${request.scenarioId}.${block.id}.$view';

  String _blockNotes(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
    String view, {
    String extra = '',
  }) =>
      '<!-- ocideck_openkat_view: ${_blockView(request, block, view)} -->'
      '${extra.isEmpty ? '' : '\n$extra'}';

  String _blockId(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
    String view,
  ) => _id('openkat-${request.scenarioId}-${block.id}-$view');
}
