import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/improvement/improvement_analysis_helpers.dart';
import '../../theme/app_theme.dart';

/// Crossed Gage R&R (ANOVA) over pasted or pre-filled measurements.
class ImprovementMsaDialog extends StatefulWidget {
  const ImprovementMsaDialog({super.key, this.initialTable});

  /// Optional Part/Operator/Value table text, or null for an empty paste area.
  final String? initialTable;

  static Future<void> show(
    BuildContext context, {
    List<List<List<double>>>? initialMeasurements,
    String? initialTable,
  }) {
    String? table = initialTable;
    if (table == null && initialMeasurements != null) {
      table = _tableFromMeasurements(initialMeasurements);
    }
    return showDialog<void>(
      context: context,
      builder: (_) => ImprovementMsaDialog(initialTable: table),
    );
  }

  static String _tableFromMeasurements(List<List<List<double>>> data) {
    final buf = StringBuffer('Part\tOperator\tValue\n');
    for (var p = 0; p < data.length; p++) {
      for (var o = 0; o < data[p].length; o++) {
        for (final v in data[p][o]) {
          buf.writeln('P${p + 1}\tOp${o + 1}\t$v');
        }
      }
    }
    return buf.toString();
  }

  @override
  State<ImprovementMsaDialog> createState() => _ImprovementMsaDialogState();
}

class _ImprovementMsaDialogState extends State<ImprovementMsaDialog> {
  late final TextEditingController _table;
  late final TextEditingController _tolerance;
  String? _result;
  String? _refusal;

  @override
  void initState() {
    super.initState();
    _table = TextEditingController(text: widget.initialTable ?? '');
    _tolerance = TextEditingController();
  }

  @override
  void dispose() {
    _table.dispose();
    _tolerance.dispose();
    super.dispose();
  }

  void _run() {
    final nested = parseGageRrTable(_table.text);
    if (nested == null) {
      setState(() {
        _result = null;
        _refusal =
            'StatsRefusal: Gage R&R — could not read a balanced '
            'Part × Operator × replicate table';
      });
      return;
    }
    final tolRaw = _tolerance.text.trim().replaceAll(',', '.');
    final tolerance = tolRaw.isEmpty ? null : double.tryParse(tolRaw);
    final outcome = runGageRrAnalysis(nested, tolerance: tolerance);
    setState(() {
      _result = outcome.result == null
          ? null
          : _formatResult(outcome.result!, context.l10n);
      _refusal = outcome.refusal;
    });
  }

  String _formatResult(GageRrSummary g, AppLocalizations l10n) {
    final lines = <String>[
      '${l10n.d('% study variation')}: '
          '${g.percentStudyVariation.toStringAsFixed(1)}%',
      '${l10n.d('% contribution')}: '
          '${g.percentContribution.toStringAsFixed(1)}%',
      '${l10n.d('Distinct categories (ndc)')}: ${g.distinctCategories}',
      g.interactionPooled
          ? l10n.d('Part × Operator interaction pooled into repeatability')
          : l10n.d('Part × Operator interaction kept separate'),
    ];
    if (g.percentTolerance != null) {
      lines.add(
        '${l10n.d('% tolerance')}: ${g.percentTolerance!.toStringAsFixed(1)}%',
      );
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Gage R&R (ANOVA)')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.d(
                  'Plak Part, Operator en Value (tab of komma). Herhaal rijen voor replicaten. Minimaal 2 parts, 2 operators, 2 metingen per cel.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _table,
                decoration: InputDecoration(
                  labelText: l10n.d('Meetdata'),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 6,
                maxLines: 10,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tolerance,
                decoration: InputDecoration(
                  labelText: l10n.d('Tolerantie (optioneel)'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                Text(
                  _result!,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (_refusal != null) ...[
                const SizedBox(height: 16),
                Text(
                  _refusal!,
                  style: TextStyle(color: AppTheme.danger600, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(onPressed: _run, child: Text(l10n.d('Berekenen'))),
      ],
    );
  }
}
