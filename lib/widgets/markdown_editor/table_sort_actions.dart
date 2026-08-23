import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/markdown_table_codec.dart';
import '../../services/table_sort.dart';

typedef ExplicitSortChoice = ({TableSortKind kind, bool ascending});

/// De gedeelde gebruikershandeling achter sorteren in gewone tabellen en
/// tijdlijnen. Analyse, waarschuwing en bevestiging blijven daardoor op beide
/// oppervlakken gelijk; alleen de aanroeper schrijft het resultaat terug.
Future<String?> smartSortTable(
  BuildContext context,
  String gfm, {
  required int column,
  required bool ascending,
  TableSortKind kind = TableSortKind.automatic,
}) async {
  const sorter = TableSortService();
  final lines = gfm.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var analysis = sorter.analyze(lines, columnIndex: column);
  if (kind != TableSortKind.automatic) {
    analysis = sorter.analyze(lines, columnIndex: column, kind: kind);
  } else if (!analysis.canSort) {
    final chosen = await showDialog<TableSortKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.d('Hoe wil je deze kolom sorteren?')),
        content: Text(
          context.l10n.d(
            'De waarden lijken niet allemaal van hetzelfde type. Kies hoe OciDeck ze moet lezen; niet-herkende waarden blijven onderaan in hun oorspronkelijke volgorde staan.',
          ),
        ),
        actions: [
          for (final option in const [
            (TableSortKind.text, 'Tekst'),
            (TableSortKind.number, 'Getal'),
            (TableSortKind.date, 'Datum'),
            (TableSortKind.time, 'Tijd'),
          ])
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, option.$1),
              child: Text(context.l10n.d(option.$2)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.d('Annuleren')),
          ),
        ],
      ),
    );
    if (!context.mounted || chosen == null) return null;
    kind = chosen;
    analysis = sorter.analyze(lines, columnIndex: column, kind: kind);
  }
  if (!analysis.canSort) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Deze kolom bevat nog geen waarden die op deze manier gesorteerd kunnen worden.',
          ),
        ),
      ),
    );
    return null;
  }
  if (analysis.suitability ==
      TableAnalysisSuitability.suitableWithAttentionPoints) {
    final choice = await _reviewSortAttention(context, lines, analysis, column);
    if (!context.mounted || choice != _SortAttentionChoice.apply) return null;
  }
  final result = sorter.sortSource(
    gfm,
    columnIndex: column,
    kind: kind,
    direction: ascending
        ? TableSortDirection.ascending
        : TableSortDirection.descending,
  );
  return result.changed ? result.source : null;
}

Future<ExplicitSortChoice?> chooseExplicitSort(BuildContext context) {
  var selected = TableSortKind.automatic;
  return showDialog<ExplicitSortChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.d('Sorteren als…')),
        content: RadioGroup<TableSortKind>(
          groupValue: selected,
          onChanged: (value) => setDialogState(() => selected = value!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in const [
                (TableSortKind.automatic, 'Automatisch'),
                (TableSortKind.text, 'Tekst'),
                (TableSortKind.number, 'Getal'),
                (TableSortKind.date, 'Datum'),
                (TableSortKind.time, 'Tijd'),
              ])
                RadioListTile<TableSortKind>(
                  value: option.$1,
                  title: Text(context.l10n.d(option.$2)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, (kind: selected, ascending: true)),
            child: Text(context.l10n.d('Oplopend')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              kind: selected,
              ascending: false,
            )),
            child: Text(context.l10n.d('Aflopend')),
          ),
        ],
      ),
    ),
  );
}

enum _SortAttentionChoice { review, apply }

Future<_SortAttentionChoice?> _reviewSortAttention(
  BuildContext context,
  List<String> lines,
  TableSortAnalysis analysis,
  int column,
) async {
  while (true) {
    if (!context.mounted) return null;
    final l10n = context.l10n;
    final profile = analysis.profile;
    final choice = await showDialog<_SortAttentionChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Sorteren met aandachtspunten?')),
        content: Text(
          '${profile.parsedRowIndices.length} ${l10n.d('waarden herkend.')}\n'
          '${profile.unparsedRowIndices.length} ${l10n.d('waarden niet herkend. Die rijen blijven onderaan in hun huidige volgorde.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SortAttentionChoice.review),
            child: Text(l10n.d('Waarden bekijken')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SortAttentionChoice.apply),
            child: Text(l10n.d('Sorteren toepassen')),
          ),
        ],
      ),
    );
    if (!context.mounted || choice != _SortAttentionChoice.review) {
      return choice;
    }
    final rows = decodeMarkdownTableRows(lines).skip(1).toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Niet-herkende waarden')),
        content: SingleChildScrollView(
          child: SelectableText(
            profile.unparsedRowIndices
                .map(
                  (index) =>
                      '${l10n.d('Rij')} ${index + 1}: ${index < rows.length && column < rows[index].length ? rows[index][column] : ''}',
                )
                .join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.d('Sluiten')),
          ),
        ],
      ),
    );
  }
}
