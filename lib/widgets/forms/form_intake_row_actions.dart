// Wat een organisator met één OciServe-inzending kan (FORM_INTAKE.md §7.8):
// een correctieronde openen, hem als behandeld markeren, of hem op de server
// laten opschonen. Bestaat alleen als de werkmap weet dat deze inzending via
// OciServe binnenkwam — anders zijn het gewone lokale acties.
//
// Elke actie is een expliciete knop met een bevestiging waar het om persoons-
// gegevens gaat (opschonen); er gebeurt nooit iets op de achtergrond.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_intake.dart';
import '../../services/form/form_intake_organiser.dart';
import '../../services/form/form_workspace.dart';
import '../../services/ociserve/ociserve_gateway.dart';
import '../../services/ociserve/ociserve_http.dart';
import '../../state/ociserve_provider.dart';

class FormIntakeRowActions extends ConsumerStatefulWidget {
  const FormIntakeRowActions({
    super.key,
    required this.workspace,
    required this.sid,
    required this.onDone,
  });

  final FormWorkspace workspace;
  final String sid;

  /// Er is iets veranderd: de lijst ververst met [message] bovenaan.
  final ValueChanged<String> onDone;

  @override
  ConsumerState<FormIntakeRowActions> createState() =>
      _FormIntakeRowActionsState();
}

class _FormIntakeRowActionsState extends ConsumerState<FormIntakeRowActions> {
  Future<
    ({
      String localFormId,
      IntakeOrganiserRecord record,
      String submissionId,
      IntakeSubmissionLink link,
    })?
  >?
  _found;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _found = lookupIntakeSubmission(widget.workspace, widget.sid);
  }

  String _errorFor(Object error) {
    final l10n = context.l10n;
    if (error is OciServeException) {
      return switch (error.code) {
        'unauthorized' || 'forbidden' => l10n.d(
          'Je mag dit op de server niet. Controleer de organisatie en je rechten.',
        ),
        'unavailable' || 'network_error' => l10n.d(
          'De server is nu niet bereikbaar. Er is niets veranderd — probeer het later opnieuw.',
        ),
        _ => l10n.d('Dat lukte niet op de server. Er is niets veranderd.'),
      };
    }
    return l10n.d('Dat lukte niet op de server. Er is niets veranderd.');
  }

  /// Voert [call] uit binnen de organisator-auth en werkt het record bij als
  /// hij slaagde: een teruggegeven detail ververst de link, `null` betekent
  /// dat de server de inzending niet meer kent en de link weg kan.
  Future<void> _act(
    String Function() describe,
    Future<IntakeSubmissionDetail?> Function(
      OciServeIntakeApi api,
      String accessToken,
    )
    call,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await _found;
      if (found == null) return;
      final detail = await ref
          .read(ociServeProvider.notifier)
          .withIntakeGateway(
            found.record.organizationId,
            (api, token) => call(api, token),
          );
      final submissions = Map<String, IntakeSubmissionLink>.of(
        found.record.submissions,
      );
      if (detail != null) {
        submissions[found.submissionId] = found.link.copyWith(
          state: detail.state,
          revision: detail.revision,
          handled: detail.handled,
        );
      } else {
        // Opschonen: de server kent hem niet meer — de link mag weg, het
        // lokale record in de werkmap blijft bewust staan.
        submissions.remove(found.submissionId);
      }
      await writeIntakeRecord(
        widget.workspace,
        found.localFormId,
        found.record.copyWith(submissions: submissions),
      );
      if (!mounted) return;
      widget.onDone(describe());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCorrection() async {
    final reason = await _ask(
      title: context.l10n.d('Correctieronde openen'),
      body: context.l10n.d(
        'De invuller mag dan een nieuwe versie insturen. Zijn eerdere inzending blijft onveranderd staan.',
      ),
      confirm: context.l10n.d('Correctieronde openen'),
      hint: context.l10n.d('Waarom (niet verplicht)'),
    );
    if (reason == null || !mounted) return;
    final found = await _found;
    if (found == null || !mounted) return;
    await _act(
      () => context.l10n.d('Correctieronde geopend op de server.'),
      (api, token) => api.openIntakeCorrection(
        accessToken: token,
        organizationId: found.record.organizationId,
        formId: found.record.formId,
        submissionId: found.submissionId,
        reason: reason.isEmpty ? null : reason,
        idempotencyKey: const Uuid().v4(),
      ),
    );
  }

  Future<void> _markHandled(bool handled) async {
    final found = await _found;
    if (found == null || !mounted) return;
    await _act(
      () => handled
          ? context.l10n.d('Als behandeld gemarkeerd op de server.')
          : context.l10n.d('Weer als open gemarkeerd op de server.'),
      (api, token) => api.markIntakeHandled(
        accessToken: token,
        organizationId: found.record.organizationId,
        formId: found.record.formId,
        submissionId: found.submissionId,
        handled: handled,
        idempotencyKey: const Uuid().v4(),
      ),
    );
  }

  Future<void> _purge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.d('Inzending opschonen op de server')),
        content: Text(
          context.l10n.d(
            'De inzending verdwijnt bij OciServe; het opschoningsregister daar houdt bij wat er weg is. Wat er in jouw werkmap staat blijft — dat ruim je apart op.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.d('Terug')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.d('Opschonen op de server')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final found = await _found;
    if (found == null || !mounted) return;
    await _act(
      () => context.l10n.d('Opschonen ingepland op de server.'),
      (api, token) => api
          .purgeIntakeSubmission(
            accessToken: token,
            organizationId: found.record.organizationId,
            formId: found.record.formId,
            submissionId: found.submissionId,
            idempotencyKey: const Uuid().v4(),
          )
          .then((_) => null),
    );
  }

  /// Een bevestigingsvenster met een optionele vrije tekst; `null` bij
  /// annuleren.
  Future<String?> _ask({
    required String title,
    required String body,
    required String confirm,
    String? hint,
  }) async {
    final text = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              if (hint != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  decoration: InputDecoration(
                    labelText: hint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.d('Terug')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(text.text.trim()),
              child: Text(confirm),
            ),
          ],
        ),
      );
    } finally {
      text.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return FutureBuilder<
      ({
        String localFormId,
        IntakeOrganiserRecord record,
        String submissionId,
        IntakeSubmissionLink link,
      })?
    >(
      future: _found,
      builder: (context, snapshot) {
        final found = snapshot.data;
        if (found == null) return const SizedBox.shrink();
        final link = found.link;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              l10n
                  .d('Via OciServe · revisie {n} · {toestand}')
                  .replaceAll('{n}', '${link.revision}')
                  .replaceAll('{toestand}', _state(l10n, link.state)),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (link.state == IntakeSubmissionState.submitted)
                  OutlinedButton(
                    onPressed: _busy ? null : _openCorrection,
                    child: Text(l10n.d('Correctieronde openen…')),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _markHandled(!link.handled),
                  child: Text(
                    link.handled
                        ? l10n.d('Weer als open markeren')
                        : l10n.d('Als behandeld markeren'),
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _purge,
                  child: Text(l10n.d('Opschonen op de server…')),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _state(AppLocalizations l10n, IntakeSubmissionState state) =>
      switch (state) {
        IntakeSubmissionState.draft => l10n.d('ontwerp'),
        IntakeSubmissionState.submitted => l10n.d('ingediend'),
        IntakeSubmissionState.correctionOpen => l10n.d('correctieronde open'),
        IntakeSubmissionState.withdrawn => l10n.d('ingetrokken'),
      };
}
