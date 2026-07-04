import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../models/rehearsal.dart';
import '../../models/slide.dart';

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
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Tijden gekopieerd naar klembord.'))),
      );
    }
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
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
            const Divider(height: 24),
            Flexible(
              child: run.perSlide.isEmpty
                  ? Text(l10n.d('Geen slides gemeten.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: run.perSlide.length,
                      itemBuilder: (_, i) {
                        final t = run.perSlide[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _label(t),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _fmt(t.spent),
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
