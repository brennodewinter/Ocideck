import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/question.dart';
import '../../theme/app_theme.dart';

/// Samengevouwen sectie voor scoring, feedback, pogingen en metadata
/// (#2003, #2004, #2005, #2008). Default ingeklapt — de meeste vragen
/// hebben alleen de defaults.
///
/// De widget is stateless: alle waarden en callbacks komen van de parent,
/// die de [QuestionSpec] bijhoudt en _emit aanroept bij wijziging.
class QuestionAdvancedFields extends StatefulWidget {
  final int points;
  final QuestionScoring scoring;
  final int penalty;
  final int maxAttempts;
  final QuestionFeedback feedback;
  final List<String> hints;
  final String remediation;
  final List<String> objectiveRefs;
  final QuestionMetadata metadata;
  final bool initiallyExpanded;

  final ValueChanged<int> onPointsChanged;
  final ValueChanged<QuestionScoring> onScoringChanged;
  final ValueChanged<int> onPenaltyChanged;
  final ValueChanged<int> onMaxAttemptsChanged;
  final ValueChanged<QuestionFeedback> onFeedbackChanged;
  final ValueChanged<List<String>> onHintsChanged;
  final ValueChanged<String> onRemediationChanged;
  final ValueChanged<List<String>> onObjectiveRefsChanged;
  final ValueChanged<QuestionMetadata> onMetadataChanged;
  final ValueChanged<bool> onExpansionChanged;

  const QuestionAdvancedFields({
    super.key,
    required this.points,
    required this.scoring,
    required this.penalty,
    required this.maxAttempts,
    required this.feedback,
    required this.hints,
    required this.remediation,
    required this.objectiveRefs,
    required this.metadata,
    this.initiallyExpanded = false,
    required this.onPointsChanged,
    required this.onScoringChanged,
    required this.onPenaltyChanged,
    required this.onMaxAttemptsChanged,
    required this.onFeedbackChanged,
    required this.onHintsChanged,
    required this.onRemediationChanged,
    required this.onObjectiveRefsChanged,
    required this.onMetadataChanged,
    required this.onExpansionChanged,
  });

  @override
  State<QuestionAdvancedFields> createState() => _QuestionAdvancedFieldsState();
}

class _QuestionAdvancedFieldsState extends State<QuestionAdvancedFields> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExpansionTile(
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) {
        setState(() => _expanded = v);
        widget.onExpansionChanged(v);
      },
      tilePadding: EdgeInsets.zero,
      title: Text(
        l10n.d('Scoring, feedback en metadata'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        l10n.d(
          'Punten, scoringstrategie, feedback, hints, pogingen en leerdoelkoppelingen.',
        ),
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      ),
      children: [
        const SizedBox(height: 8),
        _pointsRow(l10n),
        const SizedBox(height: 12),
        _scoringRow(l10n),
        const SizedBox(height: 12),
        _penaltyRow(l10n),
        const SizedBox(height: 16),
        _maxAttemptsField(l10n),
        const SizedBox(height: 16),
        _feedbackFields(l10n),
        const SizedBox(height: 16),
        _hintsField(l10n),
        const SizedBox(height: 16),
        _labeledTextField(
          l10n.d('Remediation — slide-anchor naar feedback-slide'),
          widget.remediation,
          l10n.d('bijv. slide:3'),
          (v) => widget.onRemediationChanged(v.trim()),
        ),
        const SizedBox(height: 16),
        _objectiveRefsField(l10n),
        const SizedBox(height: 16),
        _metadataFields(l10n),
      ],
    );
  }

  Widget _pointsRow(AppLocalizations l10n) {
    return Row(
      children: [
        Text(l10n.d('Punten'), style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: '${widget.points}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: '1',
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim()) ?? 1;
              widget.onPointsChanged(n.clamp(0, 1000));
            },
          ),
        ),
      ],
    );
  }

  Widget _scoringRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Scoringstrategie'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        SegmentedButton<QuestionScoring>(
          segments: [
            ButtonSegment(
              value: QuestionScoring.allOrNothing,
              label: Text(l10n.d('Alles of niets')),
            ),
            ButtonSegment(
              value: QuestionScoring.partialPerCorrect,
              label: Text(l10n.d('Deels')),
            ),
            ButtonSegment(
              value: QuestionScoring.partialPerPair,
              label: Text(l10n.d('Per paar')),
            ),
            ButtonSegment(
              value: QuestionScoring.partialPerAnswer,
              label: Text(l10n.d('Per item')),
            ),
          ],
          selected: {widget.scoring},
          showSelectedIcon: false,
          onSelectionChanged: (s) => widget.onScoringChanged(s.first),
        ),
      ],
    );
  }

  Widget _penaltyRow(AppLocalizations l10n) {
    return Row(
      children: [
        Text(
          l10n.d('Puntenaftrek per fout'),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: '${widget.penalty}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: '0',
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim()) ?? 0;
              widget.onPenaltyChanged(n.clamp(0, 1000));
            },
          ),
        ),
      ],
    );
  }

  Widget _maxAttemptsField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Maximum pogingen (0 = onbeperkt)'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: '${widget.maxAttempts}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: '1',
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim()) ?? 1;
              widget.onMaxAttemptsChanged(n.clamp(0, 100));
            },
          ),
        ),
      ],
    );
  }

  Widget _feedbackFields(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Feedback per uitkomst'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        _labeledTextField(
          l10n.d('Bij goed antwoord'),
          widget.feedback.correct,
          '',
          (v) {
            widget.onFeedbackChanged(widget.feedback.copyWith(correct: v));
          },
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        _labeledTextField(
          l10n.d('Bij fout antwoord'),
          widget.feedback.wrong,
          '',
          (v) {
            widget.onFeedbackChanged(widget.feedback.copyWith(wrong: v));
          },
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        _labeledTextField(
          l10n.d('Bij deels goed'),
          widget.feedback.partial,
          '',
          (v) {
            widget.onFeedbackChanged(widget.feedback.copyWith(partial: v));
          },
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        _labeledTextField(l10n.d('Bij timeout'), widget.feedback.timeout, '', (
          v,
        ) {
          widget.onFeedbackChanged(widget.feedback.copyWith(timeout: v));
        }, maxLines: 2),
      ],
    );
  }

  Widget _hintsField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Hints (één per regel, progressief)'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: widget.hints.join('\n'),
          maxLines: 3,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: l10n.d('Eerste hint\nTweede hint'),
          ),
          onChanged: (v) {
            final lines = v
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .toList();
            widget.onHintsChanged(lines);
          },
        ),
      ],
    );
  }

  Widget _objectiveRefsField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Leerdoelverwijzingen (slide-anchors, één per regel)'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: widget.objectiveRefs.join('\n'),
          maxLines: 2,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: l10n.d('slide:0\nslide:5'),
          ),
          onChanged: (v) {
            final refs = v
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .toList();
            widget.onObjectiveRefsChanged(refs);
          },
        ),
      ],
    );
  }

  Widget _metadataFields(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Metadata'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        _labeledTextField(l10n.d('Titel'), widget.metadata.title, '', (v) {
          widget.onMetadataChanged(widget.metadata.copyWith(title: v.trim()));
        }),
        const SizedBox(height: 8),
        _labeledTextField(
          l10n.d('Vak/onderwerp'),
          widget.metadata.subject,
          '',
          (v) {
            widget.onMetadataChanged(
              widget.metadata.copyWith(subject: v.trim()),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(l10n.d('Moeilijkheid'), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: widget.metadata.difficulty.isEmpty
                  ? 'unset'
                  : widget.metadata.difficulty,
              items: [
                DropdownMenuItem(
                  value: 'unset',
                  child: Text(l10n.d('— geen —')),
                ),
                DropdownMenuItem(
                  value: 'easy',
                  child: Text(l10n.d('Makkelijk')),
                ),
                DropdownMenuItem(
                  value: 'medium',
                  child: Text(l10n.d('Gemiddeld')),
                ),
                DropdownMenuItem(
                  value: 'hard',
                  child: Text(l10n.d('Moeilijk')),
                ),
              ],
              onChanged: (d) {
                final v = d == 'unset' ? '' : (d ?? '');
                widget.onMetadataChanged(
                  widget.metadata.copyWith(difficulty: v),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _labeledTextField(
          l10n.d('Geschatte duur in seconden'),
          widget.metadata.estimatedDurationSeconds > 0
              ? '${widget.metadata.estimatedDurationSeconds}'
              : '',
          '0',
          (v) {
            final n = int.tryParse(v.trim()) ?? 0;
            widget.onMetadataChanged(
              widget.metadata.copyWith(estimatedDurationSeconds: n),
            );
          },
        ),
        const SizedBox(height: 8),
        _labeledTextField(
          l10n.d('Tags (komma-gescheiden)'),
          widget.metadata.tags.join(', '),
          '',
          (v) {
            final tags = v
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList();
            widget.onMetadataChanged(widget.metadata.copyWith(tags: tags));
          },
        ),
      ],
    );
  }

  /// Een label + TextFormField in één, voor velden die direct een callback
  /// aanroepen bij wijziging (geen persistente controller nodig).
  Widget _labeledTextField(
    String label,
    String initial,
    String hint,
    ValueChanged<String> onChanged, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: initial,
          maxLines: maxLines,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
