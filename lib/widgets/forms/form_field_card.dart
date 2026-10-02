// Eén veld van een formulier op de invulpagina: het label, het invoerveld, de
// tellers en wat er mis is (FORM_INTAKE.md §8).
//
// De kaart bewaart het *concept* van het antwoord. Tijdens het typen is dat de
// waarheid; het document kent alleen de opgeschoonde vorm. Elke wijziging gaat
// via [onCommit] naar het document, en komt het antwoord daar anders terug — een
// wijziging van buitenaf, zoals ongedaan maken — dan neemt het concept dat over.
// Is een wijziging geweigerd (de tekst zou het formulier zelf veranderen), dan
// blijft het concept staan en staat er bij waarom: de invuller verliest zijn
// tekst niet.

import 'package:material_ui/material_ui.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/form_count_localization.dart';
import '../../l10n/form_issue_localization.dart';
import '../markdown_editor/markdown_editor_theme.dart' show DocumentStyleScope;
import '../reader/document_markdown_view.dart';
import 'form_answer_editors.dart';
import 'form_text_helpers.dart';

class FormFieldCard extends StatefulWidget {
  const FormFieldCard({
    super.key,
    required this.fill,
    required this.fieldId,
    required this.showRequired,
    required this.onCommit,
    this.onAddImages,
  });

  final FormFill fill;
  final String fieldId;

  /// Of "dit veld is verplicht" al getoond mag worden: pas nadat de invuller het
  /// veld heeft aangeraakt of heeft geprobeerd te versturen. Een leeg verplicht
  /// veld direct na het openen rood tonen is een formulier dat schreeuwt.
  final bool showRequired;

  /// Zet het antwoord in het document en zegt hoe dat afliep.
  final FormFillStep Function(String fieldId, FormAnswerValue value) onCommit;

  /// Zie [FormAnswerEditor.onAddImages].
  final Future<List<FormImageRef>> Function()? onAddImages;

  @override
  State<FormFieldCard> createState() => _FormFieldCardState();
}

class _FormFieldCardState extends State<FormFieldCard> {
  late FormAnswerValue _draft = widget.fill.answerOf(widget.fieldId).value;
  FormProblem? _refusal;

  FormFieldSpec get _field => widget.fill.fieldOf(widget.fieldId);

  @override
  void didUpdateWidget(FormFieldCard old) {
    super.didUpdateWidget(old);
    // Een geweigerde tekst blijft staan tot de invuller hem zelf aanpast.
    if (_refusal != null) return;
    final current = widget.fill.answerOf(widget.fieldId).value;
    if (current != normalizeAnswerValue(_field, _draft)) _draft = current;
  }

  void _change(FormAnswerValue value) {
    final step = widget.onCommit(widget.fieldId, value);
    setState(() {
      _draft = value;
      _refusal = step is FormFillRefused ? step.problem : null;
    });
  }

  /// Het label van het veld als Markdown: wat de auteur tussen de markers zette.
  String get _labelMarkdown {
    final region = _field.label;
    return widget.fill.text.substring(region.start, region.end).trim();
  }

  Widget _label(BuildContext context) => DocumentMarkdownView(
    _labelMarkdown,
    maxTextWidth: null,
    themeProfile: DocumentStyleScope.maybeOf(context),
    chartTheme: DocumentStyleScope.maybeOf(context),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final field = _field;
    final title = formFieldTitle(_labelMarkdown, field.id);
    final problems = [
      ?_refusal,
      for (final p in widget.fill.problemsOf(widget.fieldId))
        if (p.code != FormIssueCode.requiredEmpty || widget.showRequired) p,
    ];
    final hasError = problems.any((p) => p.severity == FormSeverity.error);
    final counts = formCounts(field, _draft);
    final consent = field.type == 'consent';

    // Een Material en geen Container met een achtergrond: de keuzevakjes en
    // radioknoppen erin tekenen hun inkt op het dichtstbijzijnde Material, en een
    // DecoratedBox ertussen verbergt dat.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: hasError ? scheme.error : scheme.outlineVariant,
            width: hasError ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!consent) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _label(context)),
                    if (field.required)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(
                          l10n.d('Verplicht'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              FormAnswerEditor(
                field: field,
                value: _draft,
                onChanged: _change,
                label: title,
                labelBuilder: consent ? _label : null,
                onAddImages: widget.onAddImages,
              ),
              for (final count in counts)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    formCountLabel(l10n, count),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: count.met ? scheme.onSurfaceVariant : scheme.error,
                    ),
                  ),
                ),
              for (final problem in problems)
                _ProblemLine(
                  message: formIssueMessage(l10n, problem),
                  problem: problem,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eén melding bij een veld. Een pictogram naast de kleur: wie rood niet van
/// grijs onderscheidt, ziet toch een fout.
class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.message, required this.problem});

  final String message;
  final FormProblem problem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (problem.severity) {
      FormSeverity.error => (Icons.error_outline, scheme.error),
      FormSeverity.warning => (Icons.warning_amber_rounded, scheme.tertiary),
      FormSeverity.info => (Icons.info_outline, scheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
