import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_exam_result.dart';

/// De eigen examenuitslagen van de cursist, onder de lijst met examens.
///
/// OciDeck toont wat de server zegt en rekent niets na: percentage en
/// geslaagd komen van OciServe, dat ze pas meestuurt als de organisatie de
/// uitslag heeft vrijgegeven. Tot dan staat er alleen dat hij nog komt.
class OciServeExamResultsSection extends StatelessWidget {
  const OciServeExamResultsSection({
    super.key,
    required this.results,
    required this.unavailable,
  });

  final List<OciServeExamResult> results;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (results.isEmpty && !unavailable) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          l10n.d('Mijn uitslagen'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (unavailable)
          Text(l10n.d('De uitslagen konden niet worden geladen.')),
        for (final result in results) _ResultTile(result),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.result);

  final OciServeExamResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: ListTile(
        key: ValueKey('exam-result-${result.attemptId}'),
        leading: const Icon(Icons.assignment_turned_in_outlined),
        title: Text(result.title),
        subtitle: Text(
          result.released
              ? l10n
                    .d('{goed} van {totaal} goed · {percentage}%')
                    .replaceAll('{goed}', '${result.correctItems}')
                    .replaceAll('{totaal}', '${result.totalItems}')
                    .replaceAll('{percentage}', _percentage(result.percentage))
              : l10n.d('De uitslag is nog niet vrijgegeven.'),
        ),
        trailing: _verdict(context),
      ),
    );
  }

  /// Het oordeel staat in tekst én pictogram, niet alleen in kleur.
  Widget? _verdict(BuildContext context) {
    final passed = result.passed;
    if (!result.released || passed == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final color = passed ? scheme.primary : scheme.error;
    return Chip(
      avatar: Icon(
        passed ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: color,
        size: 18,
      ),
      label: Text(
        passed ? context.l10n.d('Geslaagd') : context.l10n.d('Niet geslaagd'),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 100 en 66,7 zoals de server ze geeft, zonder een overbodige ",0".
  static String _percentage(double? value) {
    if (value == null) return '';
    final text = value.toStringAsFixed(1);
    return (text.endsWith('.0') ? text.substring(0, text.length - 2) : text)
        .replaceAll('.', ',');
  }
}
