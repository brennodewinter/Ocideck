import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../models/rehearsal.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';

/// Toon de samenvatting van een oefenrun (sessie-only). Beschrijvend: totale
/// tijd, doeltijd en de tijd per slide — geen pacing-oordeel.
Future<void> showRehearsalSummary(
  BuildContext context, {
  required RehearsalRun run,
  required List<Slide> slides,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RehearsalSummaryDialog(run: run, slides: slides),
  );
}

String _fmt(Duration d) {
  final neg = d.isNegative;
  final a = d.abs();
  final mm = (a.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (a.inSeconds % 60).toString().padLeft(2, '0');
  final body = a.inHours > 0 ? '${a.inHours}:$mm:$ss' : '$mm:$ss';
  return neg ? '-$body' : body;
}

class _RehearsalSummaryDialog extends StatelessWidget {
  final RehearsalRun run;
  final List<Slide> slides;

  const _RehearsalSummaryDialog({required this.run, required this.slides});

  String _label(SlideTiming t) {
    final slide = slides.firstWhere(
      (s) => s.id == t.slideId,
      orElse: () => slides.isNotEmpty ? slides.first : (throw StateError('')),
    );
    final title = slide.title.trim();
    return title.isEmpty ? '${t.index + 1}.' : '${t.index + 1}. $title';
  }

  /// Het label van een vraagpoging: de slidetitel met daarachter het
  /// hoeveelste antwoord op díe vraag het was.
  String _questionLabel(QuestionAttempt a, int attemptNumber) {
    final slide = slides.firstWhere(
      (s) => s.id == a.slideId,
      orElse: () => slides.isNotEmpty ? slides.first : (throw StateError('')),
    );
    final title = slide.title.trim();
    final head = title.isEmpty ? '${a.index + 1}.' : '${a.index + 1}. $title';
    return attemptNumber > 1 ? '$head  ($attemptNumber)' : head;
  }

  /// De pogingen met per stuk hun volgnummer binnen dezelfde vraag, zodat een
  /// tweede en derde poging als zodanig te herkennen zijn.
  List<(QuestionAttempt, int)> get _numberedAttempts {
    final seen = <String, int>{};
    return [
      for (final a in run.questionAttempts)
        (a, seen[a.slideId] = (seen[a.slideId] ?? 0) + 1),
    ];
  }

  Future<void> _copy(BuildContext context) async {
    final l10n = context.l10n;
    final buf = StringBuffer()
      ..writeln('${l10n.d('Totaal')}: ${_fmt(run.total)}');
    if (run.target != null) {
      buf.writeln('${l10n.d('Doeltijd')}: ${_fmt(run.target!)}');
    }
    buf.writeln('');
    for (final t in run.perSlide) {
      buf.writeln('${_label(t)}\t${_fmt(t.spent)}');
    }
    final attempts = _numberedAttempts;
    if (attempts.isNotEmpty) {
      buf.writeln('');
      buf.writeln(l10n.d('Vragen'));
      for (final (a, n) in attempts) {
        final verdict = a.correct ? l10n.d('goed') : l10n.d('fout');
        buf.writeln('${_questionLabel(a, n)}\t${_fmt(a.spent)}\t$verdict');
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Tijden gekopieerd naar klembord.'))),
      );
    }
  }

  /// Eén regel: omschrijving links, tijd rechts.
  Widget _row(String label, String time, {Widget? leading}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 6)],
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        Text(
          time,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    ),
  );

  /// Het vragenblok onder het slide-overzicht. Leeg wanneer er geen vraag
  /// beantwoord is — dan hoort er ook geen kopje te staan.
  List<Widget> _questionSection(BuildContext context) {
    final attempts = _numberedAttempts;
    if (attempts.isEmpty) return const [];
    final l10n = context.l10n;
    return [
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          l10n.d('Vragen'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      for (final (a, n) in attempts)
        _row(
          _questionLabel(a, n),
          _fmt(a.spent),
          leading: Icon(
            a.correct ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: a.correct ? AppTheme.successFg : AppTheme.dangerFg,
            semanticLabel: a.correct ? l10n.d('goed') : l10n.d('fout'),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final delta = run.delta;
    return AlertDialog(
      title: Text(l10n.d('Oefenrun')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Totaal vs. doeltijd.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    l10n.d('Totale tijd'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _fmt(run.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (run.target != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      l10n.d('Doeltijd'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _fmt(run.target!),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              if (delta != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        delta.isNegative
                            ? l10n.d('Binnen de tijd')
                            : l10n.d('Over de tijd'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fmt(delta),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: delta.isNegative
                            ? AppTheme.successFg
                            : AppTheme.dangerFg,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const Divider(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (run.perSlide.isEmpty)
                      Text(l10n.d('Geen slides gemeten.'))
                    else
                      for (final t in run.perSlide)
                        _row(_label(t), _fmt(t.spent)),
                    // De vragen staan onder het slide-overzicht: elke keer dat
                    // een vraag beantwoord is, met de tijd van díe poging.
                    ..._questionSection(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _copy(context),
          child: Text(l10n.d('Kopieer')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    );
  }
}
