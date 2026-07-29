import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/improvement/improvement_analysis_helpers.dart';
import '../../theme/app_theme.dart';

/// Hypothesis tests over pasted numbers — refuses small n via the stats engine.
class ImprovementInferenceDialog extends StatefulWidget {
  const ImprovementInferenceDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ImprovementInferenceDialog(),
    );
  }

  @override
  State<ImprovementInferenceDialog> createState() =>
      _ImprovementInferenceDialogState();
}

class _ImprovementInferenceDialogState
    extends State<ImprovementInferenceDialog> {
  InferenceTestKind _kind = InferenceTestKind.oneSampleT;
  final _data = TextEditingController();
  final _hypothesis = TextEditingController(text: '0');
  String? _result;
  String? _refusal;

  @override
  void dispose() {
    _data.dispose();
    _hypothesis.dispose();
    super.dispose();
  }

  void _run() {
    final hypRaw = _hypothesis.text.trim().replaceAll(',', '.');
    final hyp = double.tryParse(hypRaw) ?? 0.0;
    final outcome = runInferenceAnalysis(
      kind: _kind,
      dataRaw: _data.text,
      hypothesizedMean: hyp,
    );
    setState(() {
      _result = outcome.result == null ? null : _format(outcome.result!);
      _refusal = outcome.refusal;
    });
  }

  String _format(InferenceSummary s) {
    final estimate = s.estimate == null
        ? ''
        : '\nEstimate: ${s.estimate!.toStringAsFixed(4)}';
    return '${s.title}\n'
        '${s.statisticLabel} = ${s.statistic.toStringAsFixed(4)}\n'
        'df = ${s.degreesOfFreedom.toStringAsFixed(2)}\n'
        'p = ${s.pValue.toStringAsFixed(4)}$estimate';
  }

  String _dataHint(AppLocalizations l10n) => switch (_kind) {
    InferenceTestKind.oneSampleT => l10n.d(
      'Één kolom getallen (minimaal 2 waarnemingen).',
    ),
    InferenceTestKind.twoSampleT => l10n.d(
      'Twee kolommen gescheiden door een lege regel (minimaal 2 per groep).',
    ),
    InferenceTestKind.oneWayAnova => l10n.d(
      'Meerdere groepen, elke groep een kolom, gescheiden door een lege regel (minimaal 2 groepen, 2 waarnemingen per groep).',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Hypothesetoets')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<InferenceTestKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.d('Toets'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: InferenceTestKind.oneSampleT,
                    child: Text(l10n.d('Eénsteeks t-toets')),
                  ),
                  DropdownMenuItem(
                    value: InferenceTestKind.twoSampleT,
                    child: Text(l10n.d('Twee-steeks t-toets (Welch)')),
                  ),
                  DropdownMenuItem(
                    value: InferenceTestKind.oneWayAnova,
                    child: Text(l10n.d('Eenweg-ANOVA')),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _kind = v);
                },
              ),
              const SizedBox(height: 12),
              Text(
                _dataHint(l10n),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _data,
                decoration: InputDecoration(
                  labelText: l10n.d('Gegevens'),
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 6,
                maxLines: 10,
              ),
              if (_kind == InferenceTestKind.oneSampleT) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _hypothesis,
                  decoration: InputDecoration(
                    labelText: l10n.d('Hypothetisch gemiddelde'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
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
                  style: TextStyle(color: AppTheme.slate600, fontSize: 12),
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
