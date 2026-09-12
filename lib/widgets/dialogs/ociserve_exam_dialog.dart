import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_exam.dart';
import '../../state/ociserve_exam_provider.dart';

class OciServeExamDialog extends StatelessWidget {
  const OciServeExamDialog({super.key, required this.organizationId});

  final String organizationId;

  static Future<void> show(
    BuildContext context, {
    required String organizationId,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OciServeExamDialog(organizationId: organizationId),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(ociServeExamProvider(organizationId));
          final notifier = ref.read(
            ociServeExamProvider(organizationId).notifier,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, state),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: _body(context, state, notifier),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _header(BuildContext context, OciServeExamState state) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 22, 16, 18),
    child: Row(
      children: [
        const Icon(Icons.assignment_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.d('Mijn examens'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        IconButton(
          tooltip: context.l10n.t('close'),
          onPressed:
              state.phase == OciServeExamPhase.sending ||
                  state.phase == OciServeExamPhase.submitting
              ? null
              : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _body(
    BuildContext context,
    OciServeExamState state,
    OciServeExamNotifier notifier,
  ) {
    final l10n = context.l10n;
    switch (state.phase) {
      case OciServeExamPhase.loading:
      case OciServeExamPhase.starting:
      case OciServeExamPhase.sending:
      case OciServeExamPhase.submitting:
        return const Center(child: CircularProgressIndicator());
      case OciServeExamPhase.sessions:
        return _sessions(context, state, notifier);
      case OciServeExamPhase.question:
        return _ExamQuestion(
          key: ValueKey(state.item!.attemptItemId),
          item: state.item!,
          onAnswer: notifier.answer,
        );
      case OciServeExamPhase.readyToSubmit:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.task_alt, size: 52),
              const SizedBox(height: 16),
              Text(l10n.d('Alle vragen zijn beantwoord.')),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _confirmSubmit(context, notifier),
                child: Text(l10n.d('Examen inleveren')),
              ),
            ],
          ),
        );
      case OciServeExamPhase.submitted:
        return Center(
          child: Text(
            l10n.d('Uw examen is ingeleverd.'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        );
      case OciServeExamPhase.failed:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.d('De examenhandeling is niet gelukt.')),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: notifier.retry,
                child: Text(l10n.d('Opnieuw proberen')),
              ),
            ],
          ),
        );
    }
  }

  Widget _sessions(
    BuildContext context,
    OciServeExamState state,
    OciServeExamNotifier notifier,
  ) {
    final l10n = context.l10n;
    return ListView(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: Text(l10n.d('Menselijk toezicht bij examens')),
            subtitle: Text(
              l10n.d(
                'OciDeck stelt niet vast wie achter het toetsenbord zit. Organiseer daarom menselijk toezicht tijdens het examen.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (state.sessions.isEmpty)
          Text(l10n.d('Er zijn geen examens beschikbaar.')),
        for (final session in state.sessions)
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(l10n.d('Examen')),
              subtitle: Text(
                [
                  _sessionStatus(l10n, session),
                  if (session.absoluteDeadlineAt != null)
                    _deadline(context, session.absoluteDeadlineAt!),
                ].join('\n'),
              ),
              trailing: FilledButton(
                onPressed:
                    state.serverTime != null &&
                        session.canStartAt(state.serverTime!)
                    ? () => notifier.start(session)
                    : null,
                child: Text(l10n.d('Start examen')),
              ),
            ),
          ),
      ],
    );
  }

  String _deadline(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${context.l10n.d('Uiterste inlevermoment')}: '
        '${material.formatFullDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String _sessionStatus(AppLocalizations l10n, OciServeExamSession session) {
    return switch (session.status) {
      'released' => l10n.d('Vrijgegeven'),
      'scheduled' => l10n.d('Nog niet vrijgegeven'),
      'armed' => l10n.d('Nog niet vrijgegeven'),
      _ => l10n.d('Gesloten'),
    };
  }

  Future<void> _confirmSubmit(
    BuildContext context,
    OciServeExamNotifier notifier,
  ) async {
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.d('Examen inleveren?')),
        content: Text(
          context.l10n.d(
            'Na inleveren kunt u uw antwoorden niet meer wijzigen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.d('Definitief inleveren')),
          ),
        ],
      ),
    );
    if (submit == true) await notifier.submit();
  }
}

class _ExamQuestion extends StatefulWidget {
  const _ExamQuestion({super.key, required this.item, required this.onAnswer});

  final OciServeCurrentExamItem item;
  final ValueChanged<String> onAnswer;

  @override
  State<_ExamQuestion> createState() => _ExamQuestionState();
}

class _ExamQuestionState extends State<_ExamQuestion> {
  final _text = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = widget.item.usesOptions ? _selected : _text.text.trim();
    return ListView(
      children: [
        Text(
          l10n
              .d('Vraag {nummer}')
              .replaceAll('{nummer}', '${widget.item.position + 1}'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        Text(
          widget.item.question,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (widget.item.deadlineAt != null) ...[
          const SizedBox(height: 8),
          Text(
            '${l10n.d('Uiterste inlevermoment')}: '
            '${MaterialLocalizations.of(context).formatFullDate(widget.item.deadlineAt!.toLocal())} '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(widget.item.deadlineAt!.toLocal()))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        if (widget.item.usesOptions)
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (next) => setState(() => _selected = next),
            child: Column(
              children: [
                for (final option in widget.item.options)
                  RadioListTile<String>(
                    value: option.id,
                    title: Text(option.text),
                  ),
              ],
            ),
          )
        else
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l10n.d('Uw antwoord')),
          ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: value == null || value.isEmpty
                ? null
                : () => widget.onAnswer(value),
            child: Text(l10n.d('Antwoord indienen')),
          ),
        ),
      ],
    );
  }
}
