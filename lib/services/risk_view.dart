/// De gekoppelde tabelweergaven uit #2489 en RISK_FORMAT §3.6: een `view`-
/// marker toont een materialisatie van een brontabel in hetzelfde bestand.
///
/// De ene waarheid is de brontabel; een weergave is een *afgeschreven
/// momentopname die OciDeck kan herbouwen*. Deze module bouwt die
/// momentopname (`ociViewMaterialize`/`regenerateOciView`) en toetst of de
/// afschrijving nog met de bron klopt (`checkOciView`) — want een handedit
/// in een weergave is een discrepantie om te tonen, nooit stil te
/// overschrijven (D2, §8).
library;

import '../models/risk_dossier.dart';
import 'markdown_table_codec.dart';
import 'ocideck_marked_table.dart';
import 'ocideck_markers.dart';
import 'risk_dossier.dart';
import 'risk_dossier_scaffold.dart';
import 'table_sort.dart';

/// Afgeleide kolomsleutels die een weergave mag noemen — geen contractkeys
/// in de bron, wel materialiseerbaar als zichtbare waarde (§3.3).
const _derivedKeys = {'rpn', 'rpn_b', 'rpn_n', 'score', 'score_b', 'score_n'};

/// De benoemde projecties uit §3.6, per methode opgelost naar
/// contractkolommen. `null` = de naam is geen projectie — dan geldt `cols=`
/// letterlijk.
List<String>? ociViewProjectionCols(
  String projection,
  RiskMethod method,
) => switch ((projection, method)) {
  ('bruto', RiskMethod.fmea) => const ['id', 'failure', 's_b', 'o_b', 'd_b'],
  ('netto', RiskMethod.fmea) => const ['id', 'failure', 's_n', 'o_n', 'd_n'],
  ('overview', RiskMethod.fmea) => const [
    'id',
    'failure',
    's_b',
    'o_b',
    'd_b',
    's_n',
    'o_n',
    'd_n',
  ],
  ('bruto', RiskMethod.likelihoodImpact) => const ['id', 'event', 'l_b', 'i_b'],
  ('netto', RiskMethod.likelihoodImpact) => const ['id', 'event', 'l_n', 'i_n'],
  ('overview', RiskMethod.likelihoodImpact) => const [
    'id',
    'event',
    'l_b',
    'i_b',
    'l_n',
    'i_n',
  ],
  _ => null,
};

/// Het uitgewerkte projectieverzoek van een `view`-marker.
class OciViewPlan {
  /// De contractkolommen die de weergave toont (na projectie-uitwerking).
  final List<String> cols;

  /// `sort=`: de sleutel en de richting; `null` = bronvolgorde.
  final String? sortKey;
  final bool sortDescending;

  /// `filter=key:value`: alleen rijen waarvan die contractkolom exact
  /// [filterValue] draagt. `null` = alle rijen.
  final String? filterKey;
  final String? filterValue;

  const OciViewPlan({
    required this.cols,
    this.sortKey,
    this.sortDescending = false,
    this.filterKey,
    this.filterValue,
  });
}

/// Leest de `cols=`/`projection=`/`sort=`/`filter=`-attributen van [view] uit
/// en lost de benoemde projectie op tegen de methode van de brontabel.
OciViewPlan ociViewPlan(OciMarkedTable view, RiskMethod method) {
  final marker = view.marker;
  final projection = marker?.attr('projection');
  var cols = view.cols;
  if (projection != null && projection.isNotEmpty) {
    final named = ociViewProjectionCols(projection, method);
    // Een `cols=` bij een projectie verfijnt de benoemde set verder niet —
    // de projectie is een keuze, geen filter op de keuze.
    cols = named ?? cols;
  }
  String? sortKey;
  var desc = false;
  final sort = marker?.attr('sort');
  if (sort != null && sort.isNotEmpty) {
    final parts = sort.split(':');
    sortKey = parts.first.trim();
    desc = parts.length > 1 && parts[1].trim() == 'desc';
  }
  String? filterKey, filterValue;
  final filter = marker?.attr('filter');
  if (filter != null && filter.contains(':')) {
    final split = filter.split(':');
    filterKey = split.first.trim();
    filterValue = split.sublist(1).join(':').trim();
  }
  return OciViewPlan(
    cols: cols,
    sortKey: sortKey,
    sortDescending: desc,
    filterKey: filterKey,
    filterValue: filterValue,
  );
}

/// De waarde die contract- of afgeleide sleutel [key] voor [record] oplevert.
/// Onberekenbare afgeleiden renderen `—` (§3.7: "onbekend" is nooit `0`).
String _viewCell(RiskRecord record, String key) {
  final derived = switch (key) {
    'rpn' => record.rpnBruto ?? record.scoreBruto,
    'rpn_b' => record.rpnBruto,
    'rpn_n' => record.rpnNetto,
    'score' => record.scoreBruto ?? record.rpnBruto,
    'score_b' => record.scoreBruto,
    'score_n' => record.scoreNetto,
    _ => null,
  };
  if (_derivedKeys.contains(key)) {
    return derived == null ? '—' : '$derived';
  }
  return record.cells[key]?.trim() ?? '';
}

/// Bouwt de gematerialiseerde rijen van [view] uit de brontabel in
/// [dossier]: koppen (uit de contractlabels) + een rij per bronrecord,
/// gefilterd en gesorteerd volgens de marker. `null` als de marker geen
/// `source=` draagt of de bron niet bestaat — dat is een
/// kwaliteitsbevinding, geen render.
List<List<String>>? ociViewMaterialize(
  RiskDossier dossier,
  OciMarkedTable view,
) {
  final sourceId = view.marker?.attr('source');
  if (sourceId == null || sourceId.isEmpty) return null;
  final sourceTable = dossier.tableById(sourceId);
  if (sourceTable == null) return null;
  final method =
      RiskMethod.parse(sourceTable.marker?.attr('method') ?? '') ??
      RiskMethod.fmea;
  final plan = ociViewPlan(view, method);
  var rows = [for (final row in sourceTable.contractRows) RiskRecord(row)];
  if (plan.filterKey != null) {
    rows = [
      for (final r in rows)
        if ((r.cells[plan.filterKey!] ?? '').trim() == plan.filterValue) r,
    ];
  }
  var materialized = [
    for (final r in rows) [for (final key in plan.cols) _viewCell(r, key)],
  ];
  if (plan.sortKey != null) {
    final sortCol = plan.cols.indexOf(plan.sortKey!);
    if (sortCol >= 0) {
      // Dezelfde sortering als elke tabelsortering: leeg onderaan,
      // getallen numeriek — via de gedeelde service, geen eigen
      // vergelijker.
      final lines = encodeMarkdownTable([
        [for (final key in plan.cols) key],
        ...materialized,
      ]).split('\n');
      final result = const TableSortService().sort(
        lines,
        columnIndex: sortCol,
        direction: plan.sortDescending
            ? TableSortDirection.descending
            : TableSortDirection.ascending,
      );
      if (result.outcome == TableSortOutcome.applied) {
        materialized = decodeMarkdownTableRows(result.lines).skip(1).toList();
      }
    }
  }
  return [
    [
      for (final key in plan.cols)
        ociContractHeaderLabels[key] ?? (key.startsWith('x-') ? key : key),
    ],
    ...materialized,
  ];
}

/// Bouwt het blok van een nieuwe gekoppelde weergave op [sourceId]:
/// `view`-marker (met `gen=` op de huidige bron-`rev`) plus de meteen
/// gematerialiseerde tabel. [projection] is `bruto`/`netto`/`overview` —
/// wie een eigen kolomset wil, schrijft die later in `cols=` bij.
///
/// `null` als de brontabel niet bestaat of geen methode kent.
String? createOciViewBlock(
  RiskDossier dossier,
  String sourceId,
  String projection,
) {
  final sourceTable = dossier.tableById(sourceId);
  if (sourceTable == null) return null;
  final method = RiskMethod.parse(sourceTable.marker?.attr('method') ?? '');
  if (method == null || ociViewProjectionCols(projection, method) == null) {
    return null;
  }
  final rev = sourceTable.rev;
  final marker = OciTableMarker(
    kind: OciMarkerKinds.view,
    version: 1,
    attrs: {
      'source': sourceId,
      'projection': projection,
      if (rev != null) 'gen': '$rev',
      'cols': ociViewProjectionCols(projection, method)!.join(','),
    },
  );
  // Materialiseer direct — het blok dat terugkomt is meteen een bruikbare,
  // leesbare momentopname voor élke Markdown-lezer (D2).
  final probe = OciMarkedTable(
    blockStart: 0,
    markerEnd: 1,
    tableStart: 1,
    tableEnd: 2,
    markerLines: const [],
    markers: [marker],
    tableLines: const [],
  );
  final rows = ociViewMaterialize(dossier, probe);
  if (rows == null) return null;
  return '${marker.toComment()}\n${encodeMarkdownTable(rows)}';
}

/// Werkt [view] in [source] bij naar de huidige brontabel: nieuwe body-rijen
/// plus `gen=` op de bron-`rev`. Alleen aanroepen bij een expliciete
/// "verversen"-keuze of een eigen schrijf moment (export), nooit stil —
/// een handedit van de gebruiker in de weergave mag niet ongemerkt
/// verdwijnen (D2).
///
/// `null` als de weergave geen aansluitbare bron heeft.
String? regenerateOciView(String source, OciMarkedTable view) {
  final dossier = RiskDossier.read(source);
  final rows = ociViewMaterialize(dossier, view);
  if (rows == null) return null;
  final sourceTable = dossier.tableById(view.marker!.attr('source')!)!;
  final rev = sourceTable.rev;
  final carrier = view.marker!;
  final markers = [
    for (final m in view.markers)
      identical(m, carrier)
          ? carrier.withAttr('gen', rev == null ? null : '$rev')
          : m,
  ];
  final lines = source.split('\n');
  final replacement = <String>[
    for (final m in markers) m.toComment(),
    ...lines.sublist(view.markerEnd, view.tableStart),
    ...encodeMarkdownTable(rows).split('\n'),
  ];
  lines.replaceRange(view.blockStart, view.tableEnd, replacement);
  return lines.join('\n');
}

/// Wat [checkOciView] op een weergave vindt.
class OciViewCheck {
  /// De brontabel ontbreekt of draagt geen `rev` om mee te vergelijken.
  final bool sourceMissing;

  /// `gen=` loopt achter op de bron-`rev` — een hint, nooit het bewijs:
  /// de echte toets is [mismatches] (§3.6).
  final bool staleGen;

  /// Cellen die in het bestand anders staan dan de materialisatie — handedit
  /// of verlopen afschrijving, in `rij N kolom K: 'x' → 'y'` regels.
  final List<String> mismatches;

  const OciViewCheck({
    required this.sourceMissing,
    required this.staleGen,
    required this.mismatches,
  });

  bool get consistent => !sourceMissing && mismatches.isEmpty;
}

/// Vergelijkt de opgeslagen weergave met wat de bron nu zou materialiseren.
/// De `gen`-hint is bijzaak; de celvergelijking is de waarheid (§3.6).
OciViewCheck checkOciView(String source, OciMarkedTable view) {
  final dossier = RiskDossier.read(source);
  final sourceId = view.marker?.attr('source') ?? '';
  final sourceTable = sourceId.isEmpty ? null : dossier.tableById(sourceId);
  if (sourceTable == null) {
    return const OciViewCheck(
      sourceMissing: true,
      staleGen: false,
      mismatches: [],
    );
  }
  final materialized = ociViewMaterialize(dossier, view);
  final mismatches = <String>[];
  if (materialized != null) {
    final stored = view.bodyRows;
    final computed = materialized.skip(1).toList();
    final count = stored.length > computed.length
        ? stored.length
        : computed.length;
    for (var r = 0; r < count; r++) {
      final sRow = r < stored.length ? stored[r] : const <String>[];
      final cRow = r < computed.length ? computed[r] : const <String>[];
      final cols = sRow.length > cRow.length ? sRow.length : cRow.length;
      for (var c = 0; c < cols; c++) {
        final s = c < sRow.length ? sRow[c] : '';
        final computed_ = c < cRow.length ? cRow[c] : '';
        if (s.trim() != computed_.trim()) {
          mismatches.add('rij ${r + 1} kolom ${c + 1}: "$s" → "$computed_"');
        }
      }
    }
  }
  final gen = view.marker?.intAttr('gen');
  final rev = sourceTable.rev;
  return OciViewCheck(
    sourceMissing: false,
    staleGen: gen != null && rev != null && gen < rev,
    mismatches: mismatches,
  );
}
