import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/improvement/improvement_analysis_helpers.dart';
import '../../theme/app_theme.dart';

/// Simple linear regression: paste X and Y columns, read slope/intercept/R².
class ImprovementRegressionDialog extends StatefulWidget {
  const ImprovementRegressionDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ImprovementRegressionDialog(),
    );
  }

  @override
  State<ImprovementRegressionDialog> createState() =>
      _ImprovementRegressionDialogState();
}

class _ImprovementRegressionDialogState
    extends State<ImprovementRegressionDialog> {
  final _x = TextEditingController();
  final _y = TextEditingController();
  String? _result;
  String? _refusal;

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _run() {
    final outcome = runRegressionAnalysis(xRaw: _x.text, yRaw: _y.text);
    setState(() {
      _result = outcome.result == null
          ? null
          : _format(outcome.result!, context.l10n);
      _refusal = outcome.refusal;
    });
  }

  String _format(RegressionSummary s, AppLocalizations l10n) {
    return '${l10n.d('Intercept')}: ${s.intercept.toStringAsFixed(4)}\n'
        '${l10n.d('Hellingscoëfficiënt')}: ${s.slope.toStringAsFixed(4)}\n'
        'R²: ${s.rSquared.toStringAsFixed(4)}\n'
        'n = ${s.observationCount}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Lineaire regressie')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.d(
                  'Plak X en Y (één getal per regel). Minimaal 3 paren; de engine weigert bij te weinig waarnemingen.',
                ),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _x,
                decoration: InputDecoration(
                  labelText: 'X',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 5,
                maxLines: 8,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _y,
                decoration: InputDecoration(
                  labelText: 'Y',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                minLines: 5,
                maxLines: 8,
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
